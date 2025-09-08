// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title MEVRedistribution
 * @notice Library for calculating and distributing captured MEV
 * @dev Handles MEV detection, quantification, and fair redistribution to LPs and traders
 */
library MEVRedistribution {
    // ===== STRUCTS =====

    /// @notice MEV calculation parameters
    struct MEVCalculation {
        uint256 actualAmountOut; // Actual tokens received
        uint256 expectedAmountOut; // Expected tokens at fair price
        uint256 mevCaptured; // Difference = MEV captured
        uint256 baseFee; // Current pool base fee
        uint256 adjustedFee; // Fee after MEV adjustment
    }

    /// @notice LP reward distribution
    struct LPReward {
        address lpAddress; // Liquidity provider address
        uint256 liquidityShare; // LP's share of total liquidity
        uint256 rewardAmount; // MEV reward amount
        uint256 blockEarned; // Block when reward was earned
    }

    /// @notice Trader rebate information
    struct TraderRebate {
        address trader; // Trader address
        uint256 rebateAmount; // Rebate amount
        uint256 originalFee; // Fee they would have paid
        uint256 actualFee; // Fee they actually paid
    }

    // ===== CONSTANTS =====

    /// @notice LP share of captured MEV (8000 = 80%)
    uint16 public constant LP_SHARE_BPS = 8000;

    /// @notice Trader rebate share (2000 = 20%)
    uint16 public constant TRADER_REBATE_BPS = 2000;

    /// @notice Basis points denominator
    uint16 public constant BPS_DENOMINATOR = 10000;

    /// @notice Minimum MEV to trigger redistribution (0.0001 ETH equivalent)
    uint256 public constant MIN_MEV_THRESHOLD = 1e14;

    /// @notice Maximum fee reduction from MEV capture (50% of base fee)
    uint16 public constant MAX_FEE_REDUCTION_BPS = 5000;

    // ===== MEV CALCULATION FUNCTIONS =====

    /**
     * @notice Calculate MEV captured from price discrepancy
     * @param amountIn Input token amount
     * @param actualAmountOut Actual output received
     * @param fairPrice External reference price
     * @param currentPrice Pool's current price
     * @return mevAmount Amount of MEV captured
     */
    function calculateMEVFromPriceDiscrepancy(
        uint256 amountIn,
        uint256 actualAmountOut,
        uint256 fairPrice,
        uint256 currentPrice
    ) internal pure returns (uint256 mevAmount) {
        // Calculate expected output at fair price
        uint256 expectedAmountOut = (amountIn * fairPrice) / 1e18;

        // MEV is the difference (if pool price is more favorable than market)
        if (actualAmountOut > expectedAmountOut) {
            mevAmount = actualAmountOut - expectedAmountOut;
        } else {
            mevAmount = 0;
        }

        return mevAmount;
    }

    /**
     * @notice Calculate MEV captured from sandwich attack prevention
     * @param frontRunAmount Amount that would have been front-run
     * @param backRunAmount Amount that would have been back-run
     * @param protectionEffectiveness How effective our protection was (0-100%)
     * @return mevAmount MEV captured by preventing sandwich
     */
    function calculateMEVFromSandwichPrevention(
        uint256 frontRunAmount,
        uint256 backRunAmount,
        uint256 protectionEffectiveness
    ) internal pure returns (uint256 mevAmount) {
        // Total potential MEV from sandwich attack
        uint256 totalSandwichMEV = frontRunAmount + backRunAmount;

        // MEV captured = total MEV * protection effectiveness
        mevAmount = (totalSandwichMEV * protectionEffectiveness) / 100;

        return mevAmount;
    }

    /**
     * @notice Calculate comprehensive MEV capture
     * @param amountIn Input amount
     * @param amountOut Output amount
     * @param marketPrice External market reference
     * @param poolPrice Current pool price
     * @param volume24h 24h trading volume (for context)
     * @return calculation Complete MEV calculation details
     */
    function calculateTotalMEVCapture(
        uint256 amountIn,
        uint256 amountOut,
        uint256 marketPrice,
        uint256 poolPrice,
        uint256 volume24h
    ) internal pure returns (MEVCalculation memory calculation) {
        calculation.actualAmountOut = amountOut;

        // Expected amount at fair market price
        calculation.expectedAmountOut = (amountIn * marketPrice) / 1e18;

        // Basic MEV from price discrepancy
        uint256 priceMEV = calculateMEVFromPriceDiscrepancy(amountIn, amountOut, marketPrice, poolPrice);

        // Additional MEV estimation based on volume (higher volume = more MEV opportunities)
        uint256 volumeMultiplier = volume24h > 1000e18 ? 2 : 1; // Double MEV estimate for high-volume pools

        calculation.mevCaptured = priceMEV * volumeMultiplier;

        // Only count as MEV if above threshold
        if (calculation.mevCaptured < MIN_MEV_THRESHOLD) {
            calculation.mevCaptured = 0;
        }

        return calculation;
    }

    // ===== DYNAMIC FEE CALCULATION =====

    /**
     * @notice Calculate dynamic fee adjustment based on MEV capture
     * @param baseFee Current base fee in basis points
     * @param mevCaptured Amount of MEV captured
     * @param totalTradeValue Total value of the trade
     * @return adjustedFee New fee after MEV adjustment
     */
    function calculateDynamicFee(uint24 baseFee, uint256 mevCaptured, uint256 totalTradeValue)
        internal
        pure
        returns (uint24 adjustedFee)
    {
        if (mevCaptured == 0 || totalTradeValue == 0) {
            return baseFee;
        }

        // Calculate MEV as percentage of trade value
        uint256 mevPercentage = (mevCaptured * BPS_DENOMINATOR) / totalTradeValue;

        // Fee reduction proportional to MEV captured, capped at MAX_FEE_REDUCTION_BPS
        uint256 feeReduction = mevPercentage > MAX_FEE_REDUCTION_BPS ? MAX_FEE_REDUCTION_BPS : mevPercentage;

        // Apply fee reduction
        uint256 reducedFee = (uint256(baseFee) * (BPS_DENOMINATOR - feeReduction)) / BPS_DENOMINATOR;

        adjustedFee = uint24(reducedFee);

        return adjustedFee;
    }

    // ===== MEV DISTRIBUTION FUNCTIONS =====

    /**
     * @notice Calculate LP rewards from captured MEV
     * @param totalMEVCaptured Total MEV captured
     * @param lpLiquidity LP's liquidity amount
     * @param totalLiquidity Total pool liquidity
     * @return reward LP reward details
     */
    function calculateLPReward(uint256 totalMEVCaptured, uint256 lpLiquidity, uint256 totalLiquidity, address lpAddress)
        internal
        view
        returns (LPReward memory reward)
    {
        // LP gets their proportional share of the LP allocation (80% of total MEV)
        uint256 lpPoolShare = (totalMEVCaptured * LP_SHARE_BPS) / BPS_DENOMINATOR;

        // Individual LP reward based on their liquidity share
        uint256 liquidityShare = (lpLiquidity * 1e18) / totalLiquidity;
        uint256 rewardAmount = (lpPoolShare * liquidityShare) / 1e18;

        reward = LPReward({
            lpAddress: lpAddress,
            liquidityShare: liquidityShare,
            rewardAmount: rewardAmount,
            blockEarned: block.number
        });

        return reward;
    }

    /**
     * @notice Calculate trader rebate from captured MEV
     * @param totalMEVCaptured Total MEV captured
     * @param originalFee Fee trader would have paid normally
     * @param trader Trader address
     * @return rebate Trader rebate details
     */
    function calculateTraderRebate(uint256 totalMEVCaptured, uint256 originalFee, address trader)
        internal
        pure
        returns (TraderRebate memory rebate)
    {
        // Trader gets 20% of captured MEV as rebate
        uint256 rebateAmount = (totalMEVCaptured * TRADER_REBATE_BPS) / BPS_DENOMINATOR;

        // Rebate cannot exceed the original fee they would have paid
        rebateAmount = rebateAmount > originalFee ? originalFee : rebateAmount;

        rebate = TraderRebate({
            trader: trader,
            rebateAmount: rebateAmount,
            originalFee: originalFee,
            actualFee: originalFee > rebateAmount ? originalFee - rebateAmount : 0
        });

        return rebate;
    }

    /**
     * @notice Validate MEV distribution adds up correctly
     * @param totalMEVCaptured Total MEV that was captured
     * @param lpRewards Total amount going to LPs
     * @param traderRebates Total amount going to traders
     * @return isValid True if distribution is mathematically correct
     */
    function validateMEVDistribution(uint256 totalMEVCaptured, uint256 lpRewards, uint256 traderRebates)
        internal
        pure
        returns (bool isValid)
    {
        // Check that total distribution doesn't exceed captured MEV
        uint256 totalDistributed = lpRewards + traderRebates;

        // Allow for small rounding errors (less than 0.01%)
        uint256 tolerance = totalMEVCaptured / 10000;

        return totalDistributed <= totalMEVCaptured + tolerance;
    }
}

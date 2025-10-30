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
     * @dev Compares actual output vs expected output at fair market price
     *      MEV is captured when the pool gives a better price than market,
     *      indicating potential arbitrage or sandwich attack opportunities
     * @param amountIn Input token amount (in token decimals)
     * @param actualAmountOut Actual output received from the pool
     * @param fairPrice External reference price (scaled by 1e18)
     * @param currentPrice Pool's current price (currently unused, reserved for future logic)
     * @return mevAmount Amount of MEV captured (0 if pool price worse than market)
     */
    function calculateMEVFromPriceDiscrepancy(
        uint256 amountIn,
        uint256 actualAmountOut,
        uint256 fairPrice,
        uint256 currentPrice
    ) internal pure returns (uint256 mevAmount) {
        // Calculate what the trader should have received at fair market price
        // Formula: expectedOut = (amountIn * fairPrice) / 1e18
        // Example: 1000 USDC * (2500 * 1e18) / 1e18 = 2500 tokens
        uint256 expectedAmountOut = (amountIn * fairPrice) / 1e18;

        // MEV exists when actual output exceeds expected output
        // This indicates the pool had a more favorable price than the market,
        // which could be exploited by MEV bots via arbitrage or sandwich attacks
        if (actualAmountOut > expectedAmountOut) {
            mevAmount = actualAmountOut - expectedAmountOut;
        } else {
            // No MEV to capture - trader got worse or equal price than market
            mevAmount = 0;
        }

        return mevAmount;
    }

    /**
     * @notice Calculate MEV captured from sandwich attack prevention
     * @dev Sandwich attacks involve front-running and back-running a victim's trade.
     *      This function estimates how much MEV we saved by preventing such attacks.
     * @param frontRunAmount Amount MEV bot would have extracted by buying before victim
     * @param backRunAmount Amount MEV bot would have extracted by selling after victim
     * @param protectionEffectiveness How effective our protection was (0-100%)
     *        100 = fully protected, 50 = partially protected, 0 = no protection
     * @return mevAmount MEV captured by preventing sandwich (redirected to LPs/traders)
     */
    function calculateMEVFromSandwichPrevention(
        uint256 frontRunAmount,
        uint256 backRunAmount,
        uint256 protectionEffectiveness
    ) internal pure returns (uint256 mevAmount) {
        // Calculate total MEV that a sandwich attack would have extracted
        // Front-run profit + Back-run profit = Total sandwich profit
        uint256 totalSandwichMEV = frontRunAmount + backRunAmount;

        // Apply protection effectiveness percentage to determine actual MEV captured
        // Example: If sandwich would extract 1000 tokens and we're 80% effective,
        //          we capture 800 tokens to redistribute
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
     * @dev When MEV is captured, we reduce the fee charged to traders as an incentive.
     *      This creates a positive feedback loop: more MEV captured = lower fees = more volume
     * @param baseFee Current base fee in basis points (e.g., 3000 = 0.3%)
     * @param mevCaptured Amount of MEV captured in this trade
     * @param totalTradeValue Total value of the trade (in output token)
     * @return adjustedFee New fee after MEV-based reduction (can't go below 50% of base)
     */
    function calculateDynamicFee(uint24 baseFee, uint256 mevCaptured, uint256 totalTradeValue)
        internal
        pure
        returns (uint24 adjustedFee)
    {
        // If no MEV captured or trade has no value, return base fee unchanged
        if (mevCaptured == 0 || totalTradeValue == 0) {
            return baseFee;
        }

        // Calculate MEV as a percentage of total trade value
        // Example: If MEV = 100 tokens and trade = 10,000 tokens
        //          MEV percentage = (100 * 10000) / 10000 = 100 basis points = 1%
        uint256 mevPercentage = (mevCaptured * BPS_DENOMINATOR) / totalTradeValue;

        // Cap fee reduction at MAX_FEE_REDUCTION_BPS (50% of base fee)
        // This ensures we never reduce fees too drastically
        // Example: If MEV is 10% but max reduction is 5%, we only reduce by 5%
        uint256 feeReduction = mevPercentage > MAX_FEE_REDUCTION_BPS ? MAX_FEE_REDUCTION_BPS : mevPercentage;

        // Apply the fee reduction to base fee
        // Example: baseFee = 3000 (0.3%), reduction = 1500 (0.15%)
        //          reducedFee = 3000 * (10000 - 1500) / 10000 = 2550 (0.255%)
        uint256 reducedFee = (uint256(baseFee) * (BPS_DENOMINATOR - feeReduction)) / BPS_DENOMINATOR;

        // Cast back to uint24 (safe because reducedFee < baseFee < type(uint24).max)
        adjustedFee = uint24(reducedFee);

        return adjustedFee;
    }

    // ===== MEV DISTRIBUTION FUNCTIONS =====

    /**
     * @notice Calculate LP rewards from captured MEV
     * @dev LPs receive 80% of all captured MEV, distributed proportionally to their liquidity share.
     *      This incentivizes liquidity provision and compensates LPs for providing the liquidity
     *      that makes MEV extraction possible in the first place.
     * @param totalMEVCaptured Total MEV captured in this swap/block
     * @param lpLiquidity This specific LP's liquidity amount
     * @param totalLiquidity Total pool liquidity from all LPs
     * @param lpAddress Address of the liquidity provider
     * @return reward Complete LP reward details including amount and share percentage
     */
    function calculateLPReward(uint256 totalMEVCaptured, uint256 lpLiquidity, uint256 totalLiquidity, address lpAddress)
        internal
        view
        returns (LPReward memory reward)
    {
        // Step 1: Calculate total amount going to ALL LPs (80% of captured MEV)
        // Example: If 1000 tokens MEV captured, LP pool gets 800 tokens
        uint256 lpPoolShare = (totalMEVCaptured * LP_SHARE_BPS) / BPS_DENOMINATOR;

        // Step 2: Calculate this LP's share of total liquidity
        // Scaled by 1e18 for precision in division
        // Example: If LP has 50,000 liquidity out of 1,000,000 total
        //          liquidityShare = (50,000 * 1e18) / 1,000,000 = 0.05e18 (5%)
        uint256 liquidityShare = (lpLiquidity * 1e18) / totalLiquidity;

        // Step 3: Calculate individual LP's reward based on their liquidity share
        // Example: 800 tokens * 0.05e18 / 1e18 = 40 tokens
        uint256 rewardAmount = (lpPoolShare * liquidityShare) / 1e18;

        // Construct reward struct with all relevant information
        reward = LPReward({
            lpAddress: lpAddress,
            liquidityShare: liquidityShare, // Stored as 1e18-scaled percentage
            rewardAmount: rewardAmount,
            blockEarned: block.number // Track when reward was earned for vesting/claiming
        });

        return reward;
    }

    /**
     * @notice Calculate trader rebate from captured MEV
     * @dev Traders receive 20% of captured MEV as a rebate, incentivizing them to use ShadowSwap.
     *      The rebate is capped at the original fee to prevent negative effective fees.
     *      This creates better execution prices than traditional DEXs.
     * @param totalMEVCaptured Total MEV captured in this trade
     * @param originalFee Fee trader would have paid at base rate (before any rebate)
     * @param trader Address of the trader receiving the rebate
     * @return rebate Complete trader rebate details including actual fee after rebate
     */
    function calculateTraderRebate(uint256 totalMEVCaptured, uint256 originalFee, address trader)
        internal
        pure
        returns (TraderRebate memory rebate)
    {
        // Calculate trader's share of MEV (20% of total captured)
        // Example: If 1000 tokens MEV captured, trader gets 200 tokens rebate
        uint256 rebateAmount = (totalMEVCaptured * TRADER_REBATE_BPS) / BPS_DENOMINATOR;

        // Cap rebate at original fee to prevent negative net fees
        // Example: If rebate would be 50 tokens but fee was only 30 tokens,
        //          cap rebate at 30 tokens (effective fee becomes 0, not negative)
        rebateAmount = rebateAmount > originalFee ? originalFee : rebateAmount;

        // Construct rebate struct showing fee reduction
        rebate = TraderRebate({
            trader: trader,
            rebateAmount: rebateAmount, // Amount being returned to trader
            originalFee: originalFee, // What they would have paid normally
            actualFee: originalFee > rebateAmount ? originalFee - rebateAmount : 0 // Net fee after rebate
        });

        return rebate;
    }

    /**
     * @notice Validate MEV distribution adds up correctly
     * @dev Critical safety check to ensure we're not distributing more than we captured.
     *      Includes small tolerance for rounding errors that can occur in integer division.
     *      Should be called before any actual token transfers.
     * @param totalMEVCaptured Total MEV that was captured from the trade
     * @param lpRewards Total amount being distributed to all LPs
     * @param traderRebates Total amount being distributed to all traders
     * @return isValid True if distribution is mathematically valid (within tolerance)
     */
    function validateMEVDistribution(uint256 totalMEVCaptured, uint256 lpRewards, uint256 traderRebates)
        internal
        pure
        returns (bool isValid)
    {
        // Sum up all distributions
        // In theory: lpRewards (80%) + traderRebates (20%) = totalMEVCaptured (100%)
        uint256 totalDistributed = lpRewards + traderRebates;

        // Allow for small rounding errors from integer division (0.01% = 1 basis point)
        // This prevents false negatives from Solidity's integer math limitations
        // Example: If MEV = 10000, tolerance = 1 token
        uint256 tolerance = totalMEVCaptured / 10000;

        // Distribution is valid if total distributed doesn't exceed captured amount
        // (plus small tolerance for rounding)
        return totalDistributed <= totalMEVCaptured + tolerance;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IMEVRedistributor
 * @notice Interface for MEV capture and redistribution logic
 */
interface IMEVRedistributor {
    /// @notice MEV distribution configuration
    struct MEVConfig {
        uint16 lpShareBps; // Basis points to LPs (8000 = 80%)
        uint16 traderRebateBps; // Basis points to traders (2000 = 20%)
        uint256 minMEVThreshold; // Minimum MEV to trigger redistribution
        uint256 maxFeeAdjustment; // Maximum fee adjustment from MEV
    }

    /// @notice MEV capture data
    struct MEVCapture {
        uint256 totalCaptured;
        uint256 lpShare;
        uint256 traderShare;
        uint256 blockNumber;
        bytes32 poolId;
    }

    // ===== EVENTS =====

    event MEVCaptured(
        bytes32 indexed poolId, uint256 indexed blockNumber, uint256 totalAmount, uint256 lpShare, uint256 traderShare
    );

    event MEVDistributed(bytes32 indexed poolId, address indexed recipient, uint256 amount, bool isLP);

    // ===== MEV CALCULATION =====

    /**
     * @notice Calculate MEV captured from a swap
     * @param poolId Pool identifier
     * @param amountIn Input token amount
     * @param amountOut Output token amount
     * @param marketPrice External market price reference
     * @return mevAmount Amount of MEV captured
     */
    function calculateMEVCapture(bytes32 poolId, uint256 amountIn, uint256 amountOut, uint256 marketPrice)
        external
        view
        returns (uint256 mevAmount);

    /**
     * @notice Calculate dynamic fee adjustment based on MEV
     * @param baseFee Current base fee
     * @param mevAmount MEV captured
     * @return adjustedFee New fee accounting for MEV redistribution
     */
    function calculateDynamicFee(uint24 baseFee, uint256 mevAmount) external view returns (uint24 adjustedFee);

    // ===== MEV REDISTRIBUTION =====

    /**
     * @notice Distribute captured MEV
     * @param capture MEV capture details
     */
    function distributeMEV(MEVCapture calldata capture) external;

    /**
     * @notice Claim accumulated MEV rewards
     * @param poolId Pool to claim from
     * @param recipient Address to receive rewards
     */
    function claimMEVRewards(bytes32 poolId, address recipient) external;

    /**
     * @notice Get claimable MEV amount
     * @param poolId Pool identifier
     * @param user User address
     * @return amount Claimable amount
     */
    function getClaimableMEV(bytes32 poolId, address user) external view returns (uint256 amount);
}

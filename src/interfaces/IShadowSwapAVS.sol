// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IShadowSwapAVS
 * @notice Interface for EigenLayer AVS that coordinates cross-chain MEV protection
 * @dev This AVS enables operators to run matching engines and validate cross-chain state
 */
interface IShadowSwapAVS {
    /// @notice Represents cross-chain pool state
    struct CrossChainPoolState {
        uint256 chainId;
        bytes32 poolId;
        uint256 totalLiquidity;
        uint256 price; // encoded as sqrt(price) * 2^96
        uint256 lastUpdateBlock;
    }

    /// @notice MEV auction bid from operators
    struct MEVAuctionBid {
        address operator;
        uint256 bidAmount; // Amount operator will pay to LPs
        bytes32 poolId;
        uint256 blockNumber;
        bytes signature;
    }

    /// @notice Encrypted order matching result
    struct OrderMatchResult {
        bytes32 orderId1;
        bytes32 orderId2;
        uint256 matchedAmount;
        bool isValid;
        address[] validators; // Operators who validated this match
    }

    // ===== EVENTS =====

    event OperatorRegistered(address indexed operator);
    event CrossChainStateUpdated(uint256 indexed chainId, bytes32 indexed poolId);
    event MEVAuctionCompleted(bytes32 indexed poolId, address indexed winner, uint256 amount);
    event OrderMatchValidated(bytes32 indexed orderId1, bytes32 indexed orderId2);

    // ===== OPERATOR MANAGEMENT =====

    /**
     * @notice Register as an AVS operator
     */
    function registerOperator() external;

    /**
     * @notice Deregister an operator
     */
    function deregisterOperator() external;

    /**
     * @notice Check if address is registered operator
     */
    function isOperator(address operator) external view returns (bool);

    // ===== CROSS-CHAIN COORDINATION =====

    /**
     * @notice Update pool state from another chain
     * @param state New pool state data
     * @param proof Validity proof from operators
     */
    function updateCrossChainState(CrossChainPoolState calldata state, bytes calldata proof) external;

    /**
     * @notice Get current cross-chain pool state
     * @param chainId Target chain ID
     * @param poolId Pool identifier
     */
    function getCrossChainState(uint256 chainId, bytes32 poolId) external view returns (CrossChainPoolState memory);

    // ===== MEV AUCTIONS =====

    /**
     * @notice Submit bid for MEV auction
     * @param bid Operator's bid details
     */
    function submitMEVBid(MEVAuctionBid calldata bid) external;

    /**
     * @notice Finalize MEV auction for a block
     * @param poolId Pool identifier
     * @param blockNumber Target block number
     * @return winner Address of winning operator
     * @return winningBid Amount winner will pay to LPs
     */
    function finalizeMEVAuction(bytes32 poolId, uint256 blockNumber)
        external
        returns (address winner, uint256 winningBid);

    // ===== ORDER MATCHING =====

    /**
     * @notice Validate encrypted order matching
     * @param result Matching result to validate
     * @param proof Cryptographic proof of valid matching
     */
    function validateOrderMatch(OrderMatchResult calldata result, bytes calldata proof) external;

    /**
     * @notice Get validated matches for a pool
     * @param poolId Pool identifier
     * @param blockNumber Block to query
     */
    function getValidatedMatches(bytes32 poolId, uint256 blockNumber)
        external
        view
        returns (OrderMatchResult[] memory);
}

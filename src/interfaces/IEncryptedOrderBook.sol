// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IEncryptedOrderBook
 * @notice Interface for managing encrypted orders using Fhenix FHE
 */
interface IEncryptedOrderBook {
    /// @notice Encrypted order parameters
    struct EncryptedOrderParams {
        bytes encryptedAmount; // FHE encrypted amount
        bytes encryptedDirection; // FHE encrypted bool (zeroForOne)
        bytes encryptedDeadline; // FHE encrypted deadline
        uint256 plaintextSalt; // Public randomness for uniqueness
    }

    /// @notice Order metadata (public)
    struct OrderMetadata {
        address trader;
        bytes32 poolId;
        uint256 blockCreated;
        bool isActive;
    }

    // ===== EVENTS =====

    event EncryptedOrderCreated(bytes32 indexed orderId, address indexed trader, bytes32 indexed poolId);

    event OrderRevealed(bytes32 indexed orderId, uint256 amount, bool zeroForOne);

    event OrderCancelled(bytes32 indexed orderId);

    // ===== ORDER MANAGEMENT =====

    /**
     * @notice Create new encrypted order
     * @param poolId Target pool
     * @param encryptedParams FHE encrypted order parameters
     * @return orderId Unique order identifier
     */
    function createEncryptedOrder(bytes32 poolId, EncryptedOrderParams calldata encryptedParams)
        external
        returns (bytes32 orderId);

    /**
     * @notice Cancel existing order
     * @param orderId Order to cancel
     */
    function cancelOrder(bytes32 orderId) external;

    /**
     * @notice Reveal order details (after execution or timeout)
     * @param orderId Order to reveal
     * @param amount Plaintext amount
     * @param zeroForOne Plaintext direction
     * @param nonce FHE decryption nonce
     */
    function revealOrder(bytes32 orderId, uint256 amount, bool zeroForOne, bytes calldata nonce) external;

    // ===== ORDER QUERIES =====

    /**
     * @notice Get order metadata
     * @param orderId Order identifier
     */
    function getOrderMetadata(bytes32 orderId) external view returns (OrderMetadata memory);

    /**
     * @notice Get encrypted order data
     * @param orderId Order identifier
     */
    function getEncryptedOrder(bytes32 orderId) external view returns (EncryptedOrderParams memory);

    /**
     * @notice Check if orders can potentially match (without revealing details)
     * @param orderId1 First order
     * @param orderId2 Second order
     * @return canMatch True if orders might match (probabilistic)
     */
    function canOrdersMatch(bytes32 orderId1, bytes32 orderId2) external view returns (bool canMatch);
}

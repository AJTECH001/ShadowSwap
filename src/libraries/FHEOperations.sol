// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FHE, euint64, euint32, ebool, inEuint64, inEuint32, inEbool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/**
 * @title FHEOperations
 * @notice Library for handling FHE operations in ShadowSwap
 * @dev Provides utilities for encrypting, comparing, and manipulating encrypted order data
 */
library FHEOperations {
    // ===== STRUCTS =====

    /// @notice Encrypted swap parameters
    struct EncryptedSwapData {
        euint64 amount; // Encrypted swap amount
        ebool zeroForOne; // Encrypted direction flag
        euint32 maxSlippage; // Encrypted maximum slippage tolerance
        euint32 deadline; // Encrypted deadline block number
    }

    /// @notice Encrypted order matching parameters
    struct EncryptedMatchData {
        euint64 amount1; // First order amount
        euint64 amount2; // Second order amount
        ebool direction1; // First order direction
        ebool direction2; // Second order direction
        euint64 matchedAmount; // Amount that can be matched
    }

    // ===== CONSTANTS =====

    /// @notice Maximum slippage allowed (5% = 500 basis points)
    uint32 public constant MAX_SLIPPAGE_BPS = 500;

    /// @notice Minimum order size to prevent spam (0.001 ETH equivalent)
    uint64 public constant MIN_ORDER_SIZE = 1e15;

    // ===== ENCRYPTION FUNCTIONS =====

    /**
     * @notice Encrypt swap parameters
     * @param amount Plaintext amount to encrypt
     * @param zeroForOne Direction flag to encrypt
     * @param maxSlippage Maximum slippage tolerance
     * @param deadline Deadline block number
     * @return encrypted Encrypted swap data
     */
    function encryptSwapParams(uint64 amount, bool zeroForOne, uint32 maxSlippage, uint32 deadline)
        internal
        pure
        returns (EncryptedSwapData memory encrypted)
    {
        // Convert plaintext values to encrypted values
        encrypted.amount = FHE.asEuint64(amount);
        encrypted.zeroForOne = FHE.asEbool(zeroForOne);
        encrypted.maxSlippage = FHE.asEuint32(maxSlippage);
        encrypted.deadline = FHE.asEuint32(deadline);

        return encrypted;
    }

    /**
     * @notice Encrypt order parameters from user input
     * @param encAmount Encrypted amount input from user
     * @param encDirection Encrypted direction input from user
     * @param encSlippage Encrypted slippage input from user
     * @param encDeadline Encrypted deadline input from user
     * @return encrypted Processed encrypted swap data
     */
    function processEncryptedInput(
        inEuint64 calldata encAmount,
        inEbool calldata encDirection,
        inEuint32 calldata encSlippage,
        inEuint32 calldata encDeadline
    ) internal pure returns (EncryptedSwapData memory encrypted) {
        // Convert user-provided encrypted inputs to internal format
        encrypted.amount = FHE.asEuint64(encAmount);
        encrypted.zeroForOne = FHE.asEbool(encDirection);
        encrypted.maxSlippage = FHE.asEuint32(encSlippage);
        encrypted.deadline = FHE.asEuint32(encDeadline);

        return encrypted;
    }

    // ===== VALIDATION FUNCTIONS =====

    /**
     * @notice Validate encrypted order parameters
     * @param encrypted Encrypted order data to validate
     * @param currentBlock Current block number
     * @return isValid True if order passes validation
     */
    function validateEncryptedOrder(EncryptedSwapData memory encrypted, uint32 currentBlock)
        internal
        view
        returns (ebool isValid)
    {
        // Check minimum order size: amount >= MIN_ORDER_SIZE
        ebool sizeCheck = FHE.gte(encrypted.amount, FHE.asEuint64(MIN_ORDER_SIZE));

        // Check maximum slippage: maxSlippage <= MAX_SLIPPAGE_BPS
        ebool slippageCheck = FHE.lte(encrypted.maxSlippage, FHE.asEuint32(MAX_SLIPPAGE_BPS));

        // Check deadline: deadline > currentBlock
        ebool deadlineCheck = FHE.gt(encrypted.deadline, FHE.asEuint32(currentBlock));

        // All conditions must be true
        isValid = FHE.and(FHE.and(sizeCheck, slippageCheck), deadlineCheck);

        return isValid;
    }

    /**
     * @notice Check if order has expired
     * @param deadline Encrypted deadline
     * @param currentBlock Current block number
     * @return expired True if order has expired
     */
    function isOrderExpired(euint32 deadline, uint32 currentBlock) internal view returns (ebool expired) {
        return FHE.lte(deadline, FHE.asEuint32(currentBlock));
    }

    // ===== ORDER MATCHING FUNCTIONS =====

    /**
     * @notice Check if two encrypted orders can potentially match
     * @param order1 First encrypted order
     * @param order2 Second encrypted order
     * @return canMatch True if orders might match (directions are opposite)
     */
    function canOrdersMatch(EncryptedSwapData memory order1, EncryptedSwapData memory order2)
        internal
        view
        returns (ebool canMatch)
    {
        // Orders can match if they have opposite directions
        // order1.zeroForOne != order2.zeroForOne
        return FHE.ne(order1.zeroForOne, order2.zeroForOne);
    }

    /**
     * @notice Calculate matching amount between two orders
     * @param order1 First encrypted order
     * @param order2 Second encrypted order
     * @return matchData Encrypted matching details
     */
    function calculateOrderMatch(EncryptedSwapData memory order1, EncryptedSwapData memory order2)
        internal
        view
        returns (EncryptedMatchData memory matchData)
    {
        matchData.amount1 = order1.amount;
        matchData.amount2 = order2.amount;
        matchData.direction1 = order1.zeroForOne;
        matchData.direction2 = order2.zeroForOne;

        // Calculate matched amount as minimum of the two amounts
        matchData.matchedAmount = FHE.min(order1.amount, order2.amount);

        return matchData;
    }

    // ===== UTILITY FUNCTIONS =====

    /**
     * @notice Generate unique order ID from encrypted parameters
     * @param trader Address of the trader
     * @param encrypted Encrypted order parameters
     * @param nonce Random nonce for uniqueness
     * @return orderId Unique identifier for the order
     */
    function generateOrderId(address trader, EncryptedSwapData memory encrypted, uint256 nonce)
        internal
        pure
        returns (bytes32 orderId)
    {
        // Note: This generates ID from public data only
        // Encrypted values cannot be directly hashed
        return keccak256(abi.encodePacked(trader, nonce, block.timestamp, block.number));
    }

    /**
     * @notice Set access permissions for encrypted data
     * @param encryptedData Encrypted value to set permissions for
     * @param hookAddress Hook contract address
     * @param traderAddress Trader address
     */
    function setEncryptedDataPermissions(euint64 encryptedData, address hookAddress, address traderAddress) internal {
        // Allow hook contract to access the encrypted data
        FHE.allowThis(encryptedData);

        // Allow trader to access their own encrypted data
        FHE.allow(encryptedData, traderAddress);

        // Allow hook contract to access on behalf of trader
        FHE.allow(encryptedData, hookAddress);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Import Fhenix FHE library
import {FHE, euint64, ebool, euint32, InEuint64, InEbool, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {FHEUtils} from "./FHEUtils.sol";

/**
 * @title FHEOperations
 * @notice Library for Fully Homomorphic Encryption (FHE) operations in ShadowSwap.
 * @dev Provides utilities for encrypting, comparing, and manipulating encrypted order data
 *      using Fhenix's FHE primitives.
 */
library FHEOperations {
    // ===== STRUCTS =====

    /// @notice Encrypted swap parameters
    struct EncryptedSwapData {
        euint64 amount;       // Encrypted swap amount
        ebool zeroForOne;     // Encrypted direction flag
        euint64 sqrtPriceLimitX96; // Encrypted sqrt price limit (Lesson 4) - Using 64 bit handle for compatibility
        euint32 deadline;     // Encrypted deadline
    }

    /// @notice Encrypted order matching parameters
    struct EncryptedMatchData {
        euint64 amount1;          // First order amount (encrypted)
        euint64 amount2;          // Second order amount (encrypted)
        ebool direction1;         // First order direction (encrypted)
        ebool direction2;         // Second order direction (encrypted)
        euint64 matchedAmount;    // Amount that can be matched between orders (encrypted)
    }

    // ===== CONSTANTS =====

    /// @notice Maximum slippage allowed (500 basis points = 5%)
    uint32 public constant MAX_SLIPPAGE_BPS = 500;

    /// @notice Minimum order size to prevent spam (1e15 = 0.001 ETH/Token)
    uint64 public constant MIN_ORDER_SIZE = 1e15;

    // ===== FHE OPERATIONS =====

    /**
     * @notice Encrypt swap parameters for privacy-preserving order submission.
     * @dev Converts plaintext inputs (already encrypted client-side) to on-chain FHE types.
     * @param encAmount Encrypted amount from client
     * @param encDirection Encrypted direction from client
     * @param encPriceLimit Encrypted sqrtPriceLimitX96 from client
     * @param encDeadline Encrypted deadline from client
     * @return EncryptedSwapData struct with all parameters encrypted
     */
    function encryptSwapParams(
        InEuint64 memory encAmount, 
        InEbool memory encDirection, 
        InEuint64 memory encPriceLimit,
        InEuint32 memory encDeadline
    )
        internal
        returns (EncryptedSwapData memory)
    {
        return EncryptedSwapData({
            amount: FHE.asEuint64(encAmount),
            zeroForOne: FHE.asEbool(encDirection),
            sqrtPriceLimitX96: FHE.asEuint64(encPriceLimit), 
            deadline: FHE.asEuint32(encDeadline)
        });
    }

    /**
     * @notice Check if two encrypted orders can be matched.
     * @dev Compares directions (must be opposite) and amounts (must be > 0) using FHE operations.
     * @param matchData Encrypted data for both orders
     * @return ebool Encrypted boolean indicating if orders can be matched
     */
    function canMatchOrders(EncryptedMatchData memory matchData) internal returns (ebool) {
        ebool directionsOpposite = FHEUtils.areOpposite(matchData.direction1, matchData.direction2);
        ebool amount1Valid = FHEUtils.isNonZero(matchData.amount1);
        ebool amount2Valid = FHEUtils.isNonZero(matchData.amount2);
        
        ebool[] memory conditions = new ebool[](3);
        conditions[0] = directionsOpposite;
        conditions[1] = amount1Valid;
        conditions[2] = amount2Valid;
        
        return FHEUtils.allTrue(conditions);
    }

    /**
     * @notice Compute the matched amount between two orders.
     * @dev Calculates min(amount1, amount2) using FHE operations.
     * @param amount1 First order amount (encrypted)
     * @param amount2 Second order amount (encrypted)
     * @return euint64 The smaller of the two amounts (encrypted)
     */
    function computeMatchedAmount(euint64 amount1, euint64 amount2) internal returns (euint64) {
        return FHEUtils.min(amount1, amount2);
    }

    /** 
     * @notice Check if the current pool price is within the user's secret slippage limit.
     * @dev Uniswap V4 uses sqrtPriceLimitX96. This function compares current price against the secret limit.
     * @param currentSqrtPriceX96 The actual sqrt price from the pool (plaintext)
     * @param limitSqrtPriceX96 The encrypted sqrt price limit from the user
     * @param zeroForOne Direction of the swap (encrypted)
     * @return ebool Encrypted boolean indicating if the price is acceptable
     */
    function isPriceValid(uint160 currentSqrtPriceX96, euint64 limitSqrtPriceX96, ebool zeroForOne) internal returns (ebool) {
        euint64 eCurrentPrice = FHE.asEuint64(uint64(currentSqrtPriceX96));
        
        // If zeroForOne (selling Token0): price decreases. Limit must be >= current price.
        // If !zeroForOne (selling Token1): price increases. Limit must be <= current price.
        
        ebool validZeroForOne = FHE.gte(eCurrentPrice, limitSqrtPriceX96);
        ebool validOneForZero = FHE.lte(eCurrentPrice, limitSqrtPriceX96);
        
        return FHE.select(zeroForOne, validZeroForOne, validOneForZero);
    }

    /**
     * @notice Validate order parameters meet minimum requirements.
     * @dev Checks amount >= MIN_ORDER_SIZE.
     *      Deadline validation check is performed alongside this logic using the block number.
     * @param amount Encrypted order amount
     * @param deadline Encrypted deadline
     * @return ebool Encrypted boolean indicating if the order is valid
     */
    function isValidOrder(euint64 amount, euint32 deadline) internal returns (ebool) {
        ebool amountValid = FHE.gte(amount, FHE.asEuint64(MIN_ORDER_SIZE));
        
        euint32 currentBlock = FHE.asEuint32(uint32(block.number));
        ebool deadlineValid = FHE.gt(deadline, currentBlock);
        
        return FHE.and(amountValid, deadlineValid);
    }
}

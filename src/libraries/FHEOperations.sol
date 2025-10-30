// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Import Fhenix FHE library
import {FHE, euint64, ebool, euint32, inEuint64, inEbool, inEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {FHEUtils} from "./FHEUtils.sol";



/**
 * @title FHEOperations
 * @notice Library for Fully Homomorphic Encryption (FHE) operations in ShadowSwap
 * @dev Provides utilities for encrypting, comparing, and manipulating encrypted order data
 *      using Fhenix's FHE primitives to enable privacy-preserving DEX functionality.
 * 
 * @dev ✅ FHE FULLY ENABLED - All operations use real homomorphic encryption!
 *      
 * @dev WHAT THIS LIBRARY DOES:
 *      1. ✅ Encrypt order parameters (amount, direction, slippage, deadline)
 *      2. ✅ Perform computations on encrypted data without decryption
 *      3. ✅ Match encrypted orders without revealing details
 *      4. ✅ Validate orders using encrypted comparisons
 *      5. ✅ Prevent front-running by hiding order intentions in mempool
 * 
 * @dev FHE Security Properties:
 *      - Orders remain encrypted from submission through execution
 *      - MEV bots cannot see order details to front-run
 *      - Matching happens on encrypted values (homomorphic operations)
 *      - Only final execution results are decrypted (when authorized)
 * 
 * @dev Performance Considerations:
 *      - FHE operations are more gas-intensive than plaintext operations
 *      - Each FHE operation involves cryptographic computations
 *      - Trade-off: Privacy + MEV protection vs. Gas efficiency
 *      - CoFHE's async execution helps mitigate performance impact
 * 
 * @author ShadowSwap Team
 * @custom:security-contact security@shadowswap.xyz
 */
library FHEOperations {
    // ===== STRUCTS =====

    /// @notice Encrypted swap parameters
    /// @dev ✅ All fields use encrypted types - data remains private throughout execution!
    struct EncryptedSwapData {
        euint64 amount;       // FHE: Encrypted swap amount (hidden from MEV bots)
        ebool zeroForOne;     // FHE: Encrypted direction flag (prevents directional front-running)
        euint32 maxSlippage;  // FHE: Encrypted slippage tolerance (hides acceptable price range)
        euint32 deadline;     // FHE: Encrypted deadline (prevents timing attacks)
    }

    /// @notice Encrypted order matching parameters
    /// @dev ✅ Used to match two encrypted orders without revealing their details
    ///      Homomorphic operations allow comparison of encrypted values
    struct EncryptedMatchData {
        euint64 amount1;          // First order amount (encrypted)
        euint64 amount2;          // Second order amount (encrypted)
        ebool direction1;         // First order direction (encrypted)
        ebool direction2;         // Second order direction (encrypted)
        euint64 matchedAmount;    // Amount that can be matched between orders (encrypted)
    }

    // ===== CONSTANTS =====

    /// @notice Maximum slippage allowed (500 basis points = 5%)
    /// @dev Prevents users from submitting orders with unrealistic slippage tolerance
    ///      Example: 500/10000 = 5% max slippage
    uint32 public constant MAX_SLIPPAGE_BPS = 500;

    /// @notice Minimum order size to prevent spam and dust attacks
    /// @dev 1e15 = 0.001 ETH or equivalent in token decimals (18 decimals)
    ///      Small orders not economical due to FHE computation costs
    uint64 public constant MIN_ORDER_SIZE = 1e15;

    // ===== FHE OPERATIONS =====
    // ✅ All functions below use real Fhenix FHE operations

    /**
     * @notice Encrypt swap parameters for privacy-preserving order submission
     * @dev ✅ REAL FHE ENCRYPTION - Converts plaintext values to encrypted types
     * 
     * @dev How this works:
     *      1. Takes plaintext inputs from user (already encrypted client-side via cofhejs)
     *      2. Converts to FHE encrypted types using FHE.asEuintXX() functions
     *      3. Returns struct with fully encrypted fields
     *      4. Encrypted data is now protected on-chain - MEV bots can't read it!
     * 
     * @dev 🔐 LEARNING: FHE.asEuint64() takes a regular uint64 and creates an encrypted version
     *      The blockchain stores the encrypted value, not the plaintext!
     * 
     * @param encAmount Already-encrypted amount from client (inEuint64 type)
     * @param encZeroForOne Already-encrypted direction from client (inEbool type)
     * @param encMaxSlippage Already-encrypted slippage from client (inEuint32 type)
     * @param encDeadline Already-encrypted deadline from client (inEuint32 type)
     * @return Encrypted swap data struct with all parameters encrypted
     */
    function encryptSwapParams(
        inEuint64 memory encAmount, 
        inEbool memory encZeroForOne, 
        inEuint32 memory encMaxSlippage, 
        inEuint32 memory encDeadline
    )
        internal
        returns (EncryptedSwapData memory)
    {
        // Convert client-encrypted inputs to on-chain FHE types
        // These conversions maintain encryption while making values usable in contract
        return EncryptedSwapData({
            amount: FHE.asEuint64(encAmount),
            zeroForOne: FHE.asEbool(encZeroForOne),
            maxSlippage: FHE.asEuint32(encMaxSlippage),
            deadline: FHE.asEuint32(encDeadline)
        });
    }

    /**
     * @notice Check if two encrypted orders can be matched
     * @dev ✅ REAL FHE COMPARISONS - Compares encrypted values WITHOUT decrypting them!
     * 
     * @dev How homomorphic comparison works:
     *      1. FHE.ne() compares two encrypted bools (not equal check)
     *      2. FHE.gt() checks if encrypted number > 0
     *      3. FHE.and() combines encrypted boolean conditions
     *      4. Return encrypted result for use in further operations
     * 
     * @dev 🔐 LEARNING: This is the MAGIC of FHE!
     *      We can determine if orders match without EVER seeing the actual amounts or directions!
     *      MEV bots watching the blockchain see only encrypted blobs, not the matching logic.
     * 
     * @dev Matching criteria (all checked on encrypted data):
     *      - Opposite directions (one buy, one sell) - prevents same-side matches
     *      - Both amounts > 0 - ensures valid orders
     *      - Orders are not expired (checked separately with deadline)
     * 
     * @param matchData Encrypted data for both orders
     * @return Encrypted bool indicating if orders can match
     */
    function canMatchOrders(EncryptedMatchData memory matchData) internal returns (ebool) {
        // Check if directions are opposite (buy vs sell)
        // FHE.ne() = "not equal" - returns encrypted bool
        ebool directionsOpposite = FHEUtils.areOpposite(matchData.direction1, matchData.direction2);
        
        // Check if first order amount is greater than zero
        // FHE.gt() = "greater than" - compares encrypted values
        ebool amount1Valid = FHEUtils.isNonZero(matchData.amount1);
        
        // Check if second order amount is greater than zero
        ebool amount2Valid = FHEUtils.isNonZero(matchData.amount2);
        
        // Combine all conditions using array helper
        ebool[] memory conditions = new ebool[](3);
        conditions[0] = directionsOpposite;
        conditions[1] = amount1Valid;
        conditions[2] = amount2Valid;
        
        // Return encrypted result - caller decides when/if to decrypt
        return FHEUtils.allTrue(conditions);
    }

    /**
     * @notice Compute the matched amount between two orders
     * @dev ✅ REAL FHE MIN OPERATION - Computes minimum WITHOUT decrypting!
     * 
     * @dev How FHE.min() works:
     *      1. Takes two encrypted numbers (euint64)
     *      2. Computes which is smaller using homomorphic comparison
     *      3. Returns the smaller value - STILL ENCRYPTED!
     *      4. Result can be used in further FHE operations without decryption
     * 
     * @dev 🔐 LEARNING: FHE.min() performs conditional selection on encrypted data
     *      It's equivalent to: if (a < b) return a; else return b;
     *      But this entire computation happens on ENCRYPTED values!
     * 
     * @dev Why not decrypt?
     *      We keep the matched amount encrypted so it can be used in subsequent
     *      FHE operations (like calculating fills) without revealing order sizes.
     * 
     * @param amount1 First order amount (encrypted)
     * @param amount2 Second order amount (encrypted)
     * @return Matched amount = min(amount1, amount2) - STILL ENCRYPTED
     */
    function computeMatchedAmount(euint64 amount1, euint64 amount2) internal returns (euint64) {
        // Use helper function to compute minimum
        return FHEUtils.min(amount1, amount2);
    }

    /**
     * @notice Validate order parameters meet minimum requirements
     * @dev ✅ FHE VALIDATION - Returns encrypted bool for use in contract logic
     * 
     * @dev Validation checks (all on encrypted data):
     *      1. Amount >= MIN_ORDER_SIZE - FHE comparison
     *      2. Slippage <= MAX_SLIPPAGE_BPS - FHE comparison
     *      3. Deadline comparison handled separately in calling code
     * 
     * @dev 🔐 LEARNING: Minimize decryption!
     *      By returning encrypted bool, we let caller decide when to use result
     *      This keeps the validation logic fully encrypted
     * 
     * @dev Note: Deadline validation done in calling code because block.number
     *      is public EVM state and requires special handling
     * 
     * @param amount Encrypted order amount
     * @param maxSlippage Encrypted slippage tolerance  
     * @param deadline Encrypted deadline (validated in calling code)
     * @return Encrypted bool indicating if order is valid
     */
    function isValidOrder(euint64 amount, euint32 maxSlippage, euint32 deadline) internal returns (ebool) {
        // Validate minimum order size using FHE comparison
        // FHE.gte() = "greater than or equal" on encrypted values
        ebool amountValid = FHE.gte(amount, FHE.asEuint64(MIN_ORDER_SIZE));
        
        // Validate slippage is reasonable using FHE comparison
        // FHE.lte() = "less than or equal" on encrypted values
        ebool slippageValid = FHE.lte(maxSlippage, FHE.asEuint32(MAX_SLIPPAGE_BPS));
        
        // For deadline, just check it's not zero (actual expiry check in calling code)
        euint32 currentBlock = FHE.asEuint32(uint32(block.number));
        ebool deadlineValid = FHE.gt(deadline, currentBlock);
        
        // Combine all validations
        ebool[] memory validations = new ebool[](3);
        validations[0] = amountValid;
        validations[1] = slippageValid;
        validations[2] = deadlineValid;
        
        // Return encrypted result - stays private!
        return FHEUtils.allTrue(validations);
    }
}

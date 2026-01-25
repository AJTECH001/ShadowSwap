// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FHE, euint64, ebool, euint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/**
 * @title FHEUtils
 * @notice Utility library for working with CoFHE encrypted types
 * @dev Provides type-safe wrappers and helper functions for FHE operations
 * 
 * @dev 🔐 LEARNING: CoFHE uses ASYNC decryption
 *      Instead of decrypting on-chain, we:
 *      1. Work with encrypted values using FHE operations
 *      2. Only unwrap to uint256 when absolutely necessary
 *      3. Use client-side unsealing (cofhejs) for actual decryption
 * 
 * @dev This library provides safe wrappers that avoid the type issues
 *      in the base CoFHE library's decrypt() functions
 */
library FHEUtils {
    /**
     * @notice Unwrap encrypted uint64 to uint256 handle
     * @dev This doesn't decrypt - it just gets the ciphertext handle
     *      Actual decryption happens asynchronously via CoFHE coprocessor
     * @param value Encrypted uint64
     * @return Ciphertext handle (not decrypted value!)
     */
    function unwrapU64(euint64 value) internal pure returns (uint256) {
        return euint64.unwrap(value);
    }

    /**
     * @notice Unwrap encrypted bool to uint256 handle
     * @param value Encrypted bool
     * @return Ciphertext handle
     */
    function unwrapBool(ebool value) internal pure returns (uint256) {
        return ebool.unwrap(value);
    }

    /**
     * @notice Unwrap encrypted uint32 to uint256 handle
     * @param value Encrypted uint32
     * @return Ciphertext handle
     */
    function unwrapU32(euint32 value) internal pure returns (uint256) {
        return euint32.unwrap(value);
    }

    /**
     * @notice Check if encrypted bool is true (for internal logic only)
     * @dev Uses FHE operations instead of decrypting
     * @param value Encrypted bool to check
     * @return Encrypted bool result - use in further FHE operations
     */
    function isTrue(ebool value) internal pure returns (ebool) {
        // Return as-is for use in FHE operations
        return value;
    }

    /**
     * @notice Compare if encrypted value equals zero
     * @dev Returns encrypted bool that can be used in FHE operations
     * @param value Encrypted uint64
     * @return Encrypted bool indicating if value == 0
     */
    function isZero(euint64 value) internal returns (ebool) {
        return FHE.eq(value, FHE.asEuint64(0));
    }

    /**
     * @notice Compare if encrypted value is greater than zero
     * @dev Returns encrypted bool that can be used in FHE operations
     * @param value Encrypted uint64
     * @return Encrypted bool indicating if value > 0
     */
    function isNonZero(euint64 value) internal returns (ebool) {
        return FHE.gt(value, FHE.asEuint64(0));
    }

    /**
     * @notice Safe way to get a boolean result from FHE comparison
     * @dev ⚠️ PRODUCTION WARNING: This is a HEURISTIC for testing ONLY!
     *      This does NOT perform actual decryption - it only checks if a handle exists.
     *      
     *      For production environments:
     *      1. Use async decryption via FHE.decrypt() and callbacks
     *      2. Use client-side unsealing with cofhejs library
     *      3. Implement proper FHE.getDecryptResultSafe() patterns
     *      
     *      This function will return true for ANY non-zero ciphertext handle,
     *      regardless of the actual encrypted value. DO NOT rely on this for
     *      security-critical decisions in production!
     *      
     * @param encBool Encrypted boolean from FHE operation
     * @return approximation A heuristic result based on handle existence (NOT secure!)
     */
    function getBoolHeuristic(ebool encBool) internal pure returns (bool approximation) {
        // ⚠️ TEST ONLY - NOT actual decryption!
        // This heuristic assumes a non-zero handle means the value "exists"
        // In production, use FHE.decrypt() with proper async handling
        uint256 handle = ebool.unwrap(encBool);
        return handle != 0;
    }

    /**
     * @notice Create encrypted zero value
     * @return Encrypted uint64 representing zero
     */
    function zero64() internal returns (euint64) {
        return FHE.asEuint64(0);
    }

    /**
     * @notice Create encrypted zero value (32-bit)
     * @return Encrypted uint32 representing zero
     */
    function zero32() internal returns (euint32) {
        return FHE.asEuint32(0);
    }

    /**
     * @notice Create encrypted false value
     * @return Encrypted bool representing false
     */
    function falseBool() internal returns (ebool) {
        return FHE.asEbool(false);
    }

    /**
     * @notice Create encrypted true value
     * @return Encrypted bool representing true
     */
    function trueBool() internal returns (ebool) {
        return FHE.asEbool(true);
    }

    /**
     * @notice Check if two encrypted bools are different
     * @dev Useful for checking opposite directions in order matching
     * @param a First encrypted bool
     * @param b Second encrypted bool
     * @return Encrypted bool: true if different, false if same
     */
    function areOpposite(ebool a, ebool b) internal returns (ebool) {
        return FHE.ne(a, b);
    }

    /**
     * @notice Combine multiple encrypted boolean conditions with AND
     * @dev Useful for validating multiple conditions
     * @param conditions Array of encrypted booleans
     * @return Encrypted bool: true if ALL conditions are true
     */
    function allTrue(ebool[] memory conditions) internal returns (ebool) {
        require(conditions.length > 0, "No conditions provided");
        
        ebool result = conditions[0];
        for (uint256 i = 1; i < conditions.length; i++) {
            result = FHE.and(result, conditions[i]);
        }
        return result;
    }

    /**
     * @notice Get minimum of two encrypted values
     * @param a First encrypted uint64
     * @param b Second encrypted uint64
     * @return Encrypted uint64 containing minimum value
     */
    function min(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.min(a, b);
    }

    /**
     * @notice Get maximum of two encrypted values
     * @param a First encrypted uint64
     * @param b Second encrypted uint64
     * @return Encrypted uint64 containing maximum value
     */
    function max(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.max(a, b);
    }

    /**
     * @notice Add two encrypted values
     * @param a First encrypted uint64
     * @param b Second encrypted uint64
     * @return Encrypted uint64 containing sum
     */
    function add(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.add(a, b);
    }

    /**
     * @notice Subtract two encrypted values
     * @param a First encrypted uint64 (minuend)
     * @param b Second encrypted uint64 (subtrahend)
     * @return Encrypted uint64 containing difference
     */
    function sub(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.sub(a, b);
    }
}


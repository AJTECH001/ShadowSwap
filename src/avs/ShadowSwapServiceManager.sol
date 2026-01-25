// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IShadowSwapHook} from "../interfaces/IShadowSwapHook.sol";

/**
 * @title ShadowSwapServiceManager
 * @notice EigenLayer AVS Service Manager for ShadowSwap.
 * @dev Coordinates off-chain AVS operators to perform privacy-preserving order matching.
 *      1. Receives matching tasks from ShadowSwapHook.
 *      2. Emits events for AVS operators.
 *      3. Verifies operator responses (signatures).
 *      4. Callbacks to ShadowSwapHook to execute valid matches.
 */
contract ShadowSwapServiceManager {
    
    // ===== EVENTS =====

    event NewMatchingTaskCreated(uint32 indexed taskIndex, MatchingTask task);
    event MatchingTaskResponded(uint32 indexed taskIndex, MatchingTask task, address operator);

    // ===== STRUCTS =====

    struct MatchingTask {
        uint32 taskCreatedBlock;
        bytes32 poolId;
        bytes32 latestOrderHash; // Hash of the latest order that triggered this task
    }

    struct TaskResponse {
        uint32 referenceTaskIndex;
        bytes32 orderId1;
        bytes32 orderId2;
        bytes matchedAmountPtr; // Pointer/Handle to the FHE result
    }

    // ===== STATE =====

    address public immutable shadowSwapHook;
    address public immutable avsDirectory; // Mock for now
    
    // Task management
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(address => mapping(uint32 => bytes)) public allTaskResponses;
    uint32 public latestTaskNum;

    // Modifiers
    modifier onlyHook() {
        require(msg.sender == shadowSwapHook, "Only ShadowSwapHook can create tasks");
        _;
    }

    constructor(address _shadowSwapHook, address _avsDirectory) {
        shadowSwapHook = _shadowSwapHook;
        avsDirectory = _avsDirectory;
    }

    // ===== TASK CREATION =====

    /**
     * @notice Create a new matching task.
     * @dev Called by ShadowSwapHook when a new order is placed.
     * @param poolId The pool where the new order was placed.
     * @param latestOrderHash Hash of the new order to help operators sync.
     */
    function createNewMatchingTask(bytes32 poolId, bytes32 latestOrderHash) external onlyHook returns (MatchingTask memory) {
        MatchingTask memory newTask = MatchingTask({
            taskCreatedBlock: uint32(block.number),
            poolId: poolId,
            latestOrderHash: latestOrderHash
        });

        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));
        
        emit NewMatchingTaskCreated(latestTaskNum, newTask);
        
        latestTaskNum = latestTaskNum + 1;

        return newTask;
    }

    // ===== RESPONSE HANDLING =====

    /**
     * @notice Respond to a matching task with a found match.
     * @dev Called by AVS operators who found a match.
     *      In a real AVS, this would verify a BLS signature from the operator set.
     *      For this implementation, we assume a trusted operator signature verification (mock).
     * @param task The original task being responded to.
     * @param response The matching result (two order IDs).
     * @param signature Operator's signature proving they authorized this response (used in production for BLS verification).
     */
    function respondToTask(
        MatchingTask calldata task,
        TaskResponse calldata response,
        bytes calldata signature // Used for BLS signature verification in production
    ) external {
        // Note: In production, verify BLS signature here:
        // require(verifyBLSSignature(task, response, signature), "Invalid operator signature");
        // For now, signature validation is mocked
        (signature); // Silence unused parameter warning
        // 1. Verify task exists (hash check)
        require(
            keccak256(abi.encode(task)) == allTaskHashes[response.referenceTaskIndex],
            "Task does not match stored hash"
        );

        // 2. Verify signature (Simulated AVS Logic)
        // In production: BLS signature check against EigenLayer registry
        // Here: We just emit event and call the hook
        emit MatchingTaskResponded(response.referenceTaskIndex, task, msg.sender);

        // 3. Execute the match on the Hook
        // Note: The hook will re-verify the FHE validity on-chain before executing!
        IShadowSwapHook(shadowSwapHook).executeMatch(
            task.poolId,
            response.orderId1, 
            response.orderId2
        );
    }
}

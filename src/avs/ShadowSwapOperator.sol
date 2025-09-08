// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// TODO: Re-enable when EigenLayer contracts support 0.8.26
// import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
// import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
// import {ISignatureUtilsMixin} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
// import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {IShadowSwapAVS} from "../interfaces/IShadowSwapAVS.sol";

contract ShadowSwapOperator {
    using ECDSA for bytes32;

    struct OperatorInfo {
        address operator;
        string metadataURI;
        uint96 delegatedShares;
        bool isActive;
        uint256 lastTaskCompleted;
        uint256 successfulTasks;
        uint256 totalTasks;
    }

    struct TaskSubmission {
        uint32 taskIndex;
        bytes32 poolKey;
        uint256 actualRedistribution;
        bool isValid;
        bytes signature;
        uint256 timestamp;
    }

    // TODO: Re-enable when EigenLayer contracts support 0.8.26
    // IDelegationManager public immutable delegationManager;
    // IAllocationManager public immutable allocationManager;
    address public immutable delegationManager;
    address public immutable allocationManager;
    IShadowSwapAVS public immutable shadowSwapAVS;

    mapping(address => OperatorInfo) public operatorInfo;
    mapping(address => bool) public registeredOperators;
    mapping(uint32 => mapping(address => TaskSubmission)) public taskSubmissions;
    mapping(address => uint256) public operatorStake;

    address public owner;
    uint256 public constant MINIMUM_STAKE = 32 ether;
    uint256 public constant TASK_TIMEOUT = 1800; // 30 minutes

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyRegisteredOperator() {
        require(registeredOperators[msg.sender], "Operator not registered");
        _;
    }

    modifier onlyActiveOperator() {
        require(operatorInfo[msg.sender].isActive, "Operator not active");
        _;
    }

    event OperatorRegistered(address indexed operator, string metadataURI);
    event OperatorDeregistered(address indexed operator);
    event OperatorStatusUpdated(address indexed operator, bool isActive);
    event TaskSubmitted(
        address indexed operator,
        uint32 indexed taskIndex,
        bytes32 poolKey,
        uint256 actualRedistribution
    );
    event OperatorSlashed(address indexed operator, uint256 amount, string reason);
    event OperatorRewarded(address indexed operator, uint256 amount);

    constructor(
        address _delegationManager,
        address _allocationManager,
        IShadowSwapAVS _shadowSwapAVS
    ) {
        delegationManager = _delegationManager;
        allocationManager = _allocationManager;
        shadowSwapAVS = _shadowSwapAVS;
        owner = msg.sender;
    }

    function registerAsOperator(
        string calldata metadataURI,
        uint32 operatorId
    ) external {
        require(!registeredOperators[msg.sender], "Already registered");
        require(bytes(metadataURI).length > 0, "Invalid metadata URI");

        // TODO: Re-enable when EigenLayer contracts support 0.8.26
        // Register with EigenLayer DelegationManager
        // IDelegationManager.OperatorDetails memory operatorDetails = IDelegationManager.OperatorDetails({
        //     __deprecated_earningsReceiver: msg.sender,
        //     delegationApprover: address(0),
        //     stakerOptOutWindowBlocks: 0
        // });

        // delegationManager.registerAsOperator(operatorDetails, metadataURI);

        // Register with ShadowSwap AVS
        shadowSwapAVS.registerOperatorForAddress(msg.sender);

        // Initialize operator info
        operatorInfo[msg.sender] = OperatorInfo({
            operator: msg.sender,
            metadataURI: metadataURI,
            delegatedShares: 0,
            isActive: true,
            lastTaskCompleted: 0,
            successfulTasks: 0,
            totalTasks: 0
        });

        registeredOperators[msg.sender] = true;

        emit OperatorRegistered(msg.sender, metadataURI);
    }

    function deregisterOperator() external onlyRegisteredOperator {
        // Deregister from ShadowSwap AVS
        shadowSwapAVS.deregisterOperator();

        // Mark as inactive
        operatorInfo[msg.sender].isActive = false;
        registeredOperators[msg.sender] = false;

        emit OperatorDeregistered(msg.sender);
    }

    function submitTaskResponse(
        uint32 taskIndex,
        bytes32 poolKey,
        uint256 actualRedistribution,
        bool isValid,
        bytes calldata signature
    ) external onlyActiveOperator {
        require(
            taskSubmissions[taskIndex][msg.sender].timestamp == 0,
            "Task already submitted"
        );

        // Verify the signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(taskIndex, poolKey, actualRedistribution, isValid)
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        address signer = ethSignedMessageHash.recover(signature);
        require(signer == msg.sender, "Invalid signature");

        // Store task submission
        taskSubmissions[taskIndex][msg.sender] = TaskSubmission({
            taskIndex: taskIndex,
            poolKey: poolKey,
            actualRedistribution: actualRedistribution,
            isValid: isValid,
            signature: signature,
            timestamp: block.timestamp
        });

        // Update operator statistics
        operatorInfo[msg.sender].lastTaskCompleted = block.timestamp;
        operatorInfo[msg.sender].totalTasks++;

        if (isValid) {
            operatorInfo[msg.sender].successfulTasks++;
        }

        emit TaskSubmitted(msg.sender, taskIndex, poolKey, actualRedistribution);
    }

    function getTaskSubmission(
        uint32 taskIndex,
        address operator
    ) external view returns (TaskSubmission memory) {
        return taskSubmissions[taskIndex][operator];
    }

    function updateOperatorMetadata(string calldata metadataURI) external onlyRegisteredOperator {
        operatorInfo[msg.sender].metadataURI = metadataURI;
    }

    function setOperatorStatus(address operator, bool isActive) external onlyOwner {
        require(registeredOperators[operator], "Operator not registered");
        operatorInfo[operator].isActive = isActive;
        emit OperatorStatusUpdated(operator, isActive);
    }

    function slashOperator(
        address operator,
        uint256 amount,
        string calldata reason
    ) external onlyOwner {
        require(registeredOperators[operator], "Operator not registered");
        require(operatorStake[operator] >= amount, "Insufficient stake to slash");

        operatorStake[operator] -= amount;
        
        // Mark operator as inactive if heavily slashed
        if (operatorStake[operator] < MINIMUM_STAKE) {
            operatorInfo[operator].isActive = false;
        }

        emit OperatorSlashed(operator, amount, reason);
    }

    function rewardOperator(address operator, uint256 amount) external onlyOwner {
        require(registeredOperators[operator], "Operator not registered");
        operatorStake[operator] += amount;
        emit OperatorRewarded(operator, amount);
    }

    function getOperatorPerformance(address operator) external view returns (
        uint256 successfulTasks,
        uint256 totalTasks,
        uint256 successRate,
        uint256 lastTaskCompleted
    ) {
        OperatorInfo memory info = operatorInfo[operator];
        successfulTasks = info.successfulTasks;
        totalTasks = info.totalTasks;
        successRate = totalTasks > 0 ? (successfulTasks * 100) / totalTasks : 0;
        lastTaskCompleted = info.lastTaskCompleted;
    }

    function isDelegatedToOperator(
        address staker,
        address operator
    ) external view returns (bool) {
        // TODO: Re-enable when EigenLayer contracts support 0.8.26
        // return delegationManager.delegatedTo(staker) == operator;
        return false; // Placeholder
    }

    function getOperatorStake(address operator) external view returns (uint256) {
        return operatorStake[operator];
    }

    function isOperatorActive(address operator) external view returns (bool) {
        return registeredOperators[operator] && operatorInfo[operator].isActive;
    }

    function getAllRegisteredOperators() external view returns (address[] memory operators) {
        // This would need to be implemented with a counter and array in a production system
        // For now, returning empty array as placeholder
        operators = new address[](0);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        owner = newOwner;
    }

    function emergencyPause(address operator) external onlyOwner {
        require(registeredOperators[operator], "Operator not registered");
        operatorInfo[operator].isActive = false;
        emit OperatorStatusUpdated(operator, false);
    }

    function getOperatorInfo(address operator) external view returns (OperatorInfo memory) {
        return operatorInfo[operator];
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// TODO: Re-enable when EigenLayer contracts support 0.8.26
// import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
// import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
// import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

contract ShadowSwapAVS {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct MEVTask {
        uint32 taskCreatedBlock;
        bytes32 poolKey;
        bytes encryptedOrderData;
        uint256 expectedRedistribution;
        uint32 quorumThresholdPercentage;
        bytes quorumNumbers;
    }

    struct MEVTaskResponse {
        uint32 referenceTaskIndex;
        bytes32 poolKey;
        uint256 actualRedistribution;
        bool isValid;
    }

    struct MEVTaskResponseMetadata {
        uint32 taskResponsedBlock;
        bytes32 hashOfNonSigners;
        uint256 totalStakeAmount;
        uint256 signaturesCheckGasLimit;
    }

    struct QuorumStakeTotals {
        uint96[] signedStakeForQuorum;
        uint96[] totalStakeForQuorum;
    }

    // TODO: Re-enable when EigenLayer contracts support 0.8.26
    // IAllocationManager public immutable allocationManager;
    // IRewardsCoordinator public immutable rewardsCoordinator;
    address public immutable allocationManager;
    address public immutable rewardsCoordinator;

    uint32 public latestTaskNum;

    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(uint32 => bytes32) public allTaskResponses;
    mapping(uint32 => bool) public taskSuccesfullyChallenged;

    EnumerableSet.AddressSet private registeredOperators;

    uint256 public constant TASK_RESPONSE_WINDOW_BLOCK = 30;
    uint32 public constant TASK_CHALLENGE_WINDOW_BLOCK = 100;
    uint256 public constant THRESHOLD_DENOMINATOR = 100;

    address public taskGenerator;
    address public aggregator;
    address public challenger;

    modifier onlyTaskGenerator() {
        require(msg.sender == taskGenerator, "Only task generator");
        _;
    }

    modifier onlyAggregator() {
        require(msg.sender == aggregator, "Only aggregator");
        _;
    }

    modifier onlyChallenger() {
        require(msg.sender == challenger, "Only challenger");
        _;
    }

    event NewMEVTask(uint32 indexed taskIndex, MEVTask task);
    event MEVTaskResponded(
        uint32 indexed taskIndex, MEVTaskResponse taskResponse, MEVTaskResponseMetadata taskResponseMetadata
    );
    event TaskCompleted(uint32 indexed taskIndex);
    event TaskChallengedSuccessfully(uint32 indexed taskIndex, address indexed challenger);
    event TaskChallengedUnsuccessfully(uint32 indexed taskIndex, address indexed challenger);
    event OperatorRegistered(address indexed operator);
    event OperatorDeregistered(address indexed operator);

    constructor(address _allocationManager, address _rewardsCoordinator) {
        allocationManager = _allocationManager;
        rewardsCoordinator = _rewardsCoordinator;
        taskGenerator = msg.sender;
        aggregator = msg.sender;
        challenger = msg.sender;
    }

    function registerOperator() external {
        require(!registeredOperators.contains(msg.sender), "Operator already registered");

        registeredOperators.add(msg.sender);

        emit OperatorRegistered(msg.sender);
    }

    function registerOperatorForAddress(address operator) external {
        require(!registeredOperators.contains(operator), "Operator already registered");

        registeredOperators.add(operator);

        emit OperatorRegistered(operator);
    }

    function deregisterOperator() external {
        require(registeredOperators.contains(msg.sender), "Operator not registered");

        registeredOperators.remove(msg.sender);

        emit OperatorDeregistered(msg.sender);
    }

    function createNewTask(
        bytes32 poolKey,
        bytes calldata encryptedOrderData,
        uint256 expectedRedistribution,
        uint32 quorumThresholdPercentage,
        bytes calldata quorumNumbers
    ) external onlyTaskGenerator {
        MEVTask memory newTask;
        newTask.poolKey = poolKey;
        newTask.encryptedOrderData = encryptedOrderData;
        newTask.expectedRedistribution = expectedRedistribution;
        newTask.taskCreatedBlock = uint32(block.number);
        newTask.quorumThresholdPercentage = quorumThresholdPercentage;
        newTask.quorumNumbers = quorumNumbers;

        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));
        emit NewMEVTask(latestTaskNum, newTask);
        latestTaskNum++;
    }

    function respondToTask(
        MEVTask calldata task,
        MEVTaskResponse calldata taskResponse,
        MEVTaskResponseMetadata calldata taskResponseMetadata
    ) external onlyAggregator {
        uint32 taskIndex = taskResponse.referenceTaskIndex;

        require(keccak256(abi.encode(task)) == allTaskHashes[taskIndex], "Task does not match");
        require(allTaskResponses[taskIndex] == bytes32(0), "Aggregator has already responded to the task");
        require(
            uint32(block.number) <= task.taskCreatedBlock + TASK_RESPONSE_WINDOW_BLOCK,
            "Aggregator has not responded to the task within the response window"
        );

        bytes32 message = keccak256(abi.encode(taskResponse));

        allTaskResponses[taskIndex] = message;

        emit MEVTaskResponded(taskIndex, taskResponse, taskResponseMetadata);
        emit TaskCompleted(taskIndex);
    }

    function raiseAndResolveChallenge(
        MEVTask calldata task,
        MEVTaskResponse calldata taskResponse,
        MEVTaskResponseMetadata calldata taskResponseMetadata,
        address[] memory pubkeysOfNonSigningOperators
    ) external onlyChallenger {
        uint32 referenceTaskIndex = taskResponse.referenceTaskIndex;
        require(allTaskResponses[referenceTaskIndex] != bytes32(0), "Task has not been responded to");
        require(!taskSuccesfullyChallenged[referenceTaskIndex], "Task has already been challenged successfully");
        require(
            uint32(block.number) <= task.taskCreatedBlock + TASK_CHALLENGE_WINDOW_BLOCK, "Challenge window has expired"
        );

        bytes32 message = keccak256(abi.encode(taskResponse));
        require(message == allTaskResponses[referenceTaskIndex], "Task response does not match");

        bool taskValid = _validateMEVTask(task, taskResponse);

        if (!taskValid) {
            taskSuccesfullyChallenged[referenceTaskIndex] = true;

            _slashOperators(pubkeysOfNonSigningOperators);

            emit TaskChallengedSuccessfully(referenceTaskIndex, msg.sender);
        } else {
            emit TaskChallengedUnsuccessfully(referenceTaskIndex, msg.sender);
        }
    }

    function _validateMEVTask(MEVTask calldata task, MEVTaskResponse calldata taskResponse)
        internal
        pure
        returns (bool)
    {
        if (taskResponse.poolKey != task.poolKey) {
            return false;
        }

        uint256 redistributionTolerance = task.expectedRedistribution / 100; // 1% tolerance
        if (
            taskResponse.actualRedistribution < task.expectedRedistribution - redistributionTolerance
                || taskResponse.actualRedistribution > task.expectedRedistribution + redistributionTolerance
        ) {
            return false;
        }

        return taskResponse.isValid;
    }

    function _slashOperators(address[] memory operators) internal {
        for (uint256 i = 0; i < operators.length; i++) {
            if (registeredOperators.contains(operators[i])) {
                registeredOperators.remove(operators[i]);
                // Additional slashing logic would be implemented here
                // This would integrate with EigenLayer's slashing mechanisms
            }
        }
    }

    function getRegisteredOperators() external view returns (address[] memory) {
        return registeredOperators.values();
    }

    function isOperatorRegistered(address operator) external view returns (bool) {
        return registeredOperators.contains(operator);
    }

    function setTaskGenerator(address _taskGenerator) external {
        require(msg.sender == taskGenerator, "Only current task generator");
        taskGenerator = _taskGenerator;
    }

    function setAggregator(address _aggregator) external {
        require(msg.sender == aggregator, "Only current aggregator");
        aggregator = _aggregator;
    }

    function setChallenger(address _challenger) external {
        require(msg.sender == challenger, "Only current challenger");
        challenger = _challenger;
    }
}

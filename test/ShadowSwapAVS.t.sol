// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ShadowSwapAVS} from "../src/avs/ShadowSwapAVS.sol";
import {ShadowSwapOperator} from "../src/avs/ShadowSwapOperator.sol";
import {IShadowSwapAVS} from "../src/interfaces/IShadowSwapAVS.sol";

contract ShadowSwapAVSTest is Test {
    ShadowSwapAVS avs;
    ShadowSwapOperator operatorContract;

    address deployer = makeAddr("deployer");
    address operator1 = 0x2e988A386a799F506693793c6A5AF6B54dfAaBfB; // Matches private key used in tests
    address operator2 = makeAddr("operator2");
    address challenger = makeAddr("challenger");

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy AVS with placeholder addresses for EigenLayer contracts
        avs = new ShadowSwapAVS(
            address(0x1), // placeholder allocation manager
            address(0x2) // placeholder rewards coordinator
        );

        // Deploy operator contract
        operatorContract = new ShadowSwapOperator(
            address(0x3), // placeholder delegation manager
            address(0x1), // placeholder allocation manager
            IShadowSwapAVS(address(avs))
        );

        vm.stopPrank();
    }

    function testOperatorRegistration() public {
        vm.startPrank(operator1);

        // Register operator
        avs.registerOperator();

        // Verify registration
        assertTrue(avs.isOperatorRegistered(operator1));

        // Check operator list
        address[] memory operators = avs.getRegisteredOperators();
        assertEq(operators.length, 1);
        assertEq(operators[0], operator1);

        vm.stopPrank();
    }

    function testOperatorDeregistration() public {
        vm.startPrank(operator1);

        // Register first
        avs.registerOperator();
        assertTrue(avs.isOperatorRegistered(operator1));

        // Then deregister
        avs.deregisterOperator();
        assertFalse(avs.isOperatorRegistered(operator1));

        vm.stopPrank();
    }

    function testTaskCreation() public {
        vm.startPrank(deployer);

        bytes32 poolKey = keccak256("test-pool");
        bytes memory encryptedData = "encrypted-order-data";
        uint256 expectedRedistribution = 1000;
        uint32 quorumThreshold = 66; // 66%
        bytes memory quorumNumbers = abi.encode(uint8(0));

        // Create task
        avs.createNewTask(poolKey, encryptedData, expectedRedistribution, quorumThreshold, quorumNumbers);

        // Verify task was created
        assertEq(avs.latestTaskNum(), 1);

        vm.stopPrank();
    }

    function testTaskResponse() public {
        vm.startPrank(deployer);

        // Create a task first
        bytes32 poolKey = keccak256("test-pool");
        bytes memory encryptedData = "encrypted-order-data";
        uint256 expectedRedistribution = 1000;

        avs.createNewTask(poolKey, encryptedData, expectedRedistribution, 66, abi.encode(uint8(0)));

        // Prepare task response
        ShadowSwapAVS.MEVTask memory task = ShadowSwapAVS.MEVTask({
            taskCreatedBlock: uint32(block.number),
            poolKey: poolKey,
            encryptedOrderData: encryptedData,
            expectedRedistribution: expectedRedistribution,
            quorumThresholdPercentage: 66,
            quorumNumbers: abi.encode(uint8(0))
        });

        ShadowSwapAVS.MEVTaskResponse memory response = ShadowSwapAVS.MEVTaskResponse({
            referenceTaskIndex: 0,
            poolKey: poolKey,
            actualRedistribution: 950, // Close to expected
            isValid: true
        });

        ShadowSwapAVS.MEVTaskResponseMetadata memory metadata = ShadowSwapAVS.MEVTaskResponseMetadata({
            taskResponsedBlock: uint32(block.number),
            hashOfNonSigners: bytes32(0),
            totalStakeAmount: 1000000,
            signaturesCheckGasLimit: 50000
        });

        // Submit response
        avs.respondToTask(task, response, metadata);

        // Verify response was recorded
        assertTrue(avs.allTaskResponses(0) != bytes32(0));

        vm.stopPrank();
    }

    function testTaskChallenge() public {
        vm.startPrank(deployer);

        // Set challenger role first
        avs.setChallenger(challenger);

        // Create and respond to a task first
        bytes32 poolKey = keccak256("test-pool");
        bytes memory encryptedData = "encrypted-order-data";
        uint256 expectedRedistribution = 1000;

        avs.createNewTask(poolKey, encryptedData, expectedRedistribution, 66, abi.encode(uint8(0)));

        ShadowSwapAVS.MEVTask memory task = ShadowSwapAVS.MEVTask({
            taskCreatedBlock: uint32(block.number),
            poolKey: poolKey,
            encryptedOrderData: encryptedData,
            expectedRedistribution: expectedRedistribution,
            quorumThresholdPercentage: 66,
            quorumNumbers: abi.encode(uint8(0))
        });

        // Response with incorrect redistribution (should be challengeable)
        ShadowSwapAVS.MEVTaskResponse memory response = ShadowSwapAVS.MEVTaskResponse({
            referenceTaskIndex: 0,
            poolKey: poolKey,
            actualRedistribution: 500, // Far from expected - invalid
            isValid: true
        });

        ShadowSwapAVS.MEVTaskResponseMetadata memory metadata = ShadowSwapAVS.MEVTaskResponseMetadata({
            taskResponsedBlock: uint32(block.number),
            hashOfNonSigners: bytes32(0),
            totalStakeAmount: 1000000,
            signaturesCheckGasLimit: 50000
        });

        avs.respondToTask(task, response, metadata);

        vm.stopPrank();

        // Now challenge the response
        vm.startPrank(challenger);

        address[] memory nonSigningOperators = new address[](0);

        avs.raiseAndResolveChallenge(task, response, metadata, nonSigningOperators);

        // Verify challenge was successful
        assertTrue(avs.taskSuccesfullyChallenged(0));

        vm.stopPrank();
    }

    function testOperatorContractRegistration() public {
        vm.startPrank(operator1);

        // Register through operator contract
        operatorContract.registerAsOperator("https://operator1-metadata.com", 1);

        // Verify registration in both contracts
        assertTrue(operatorContract.isOperatorActive(operator1));
        assertTrue(avs.isOperatorRegistered(operator1));

        vm.stopPrank();
    }

    function testOperatorTaskSubmission() public {
        vm.startPrank(operator1);

        // Register operator first
        operatorContract.registerAsOperator("https://operator1-metadata.com", 1);

        // Create a signature for task submission
        uint32 taskIndex = 0;
        bytes32 poolKey = keccak256("test-pool");
        uint256 actualRedistribution = 950;
        bool isValid = true;

        // Create a proper signature using vm.sign
        bytes32 messageHash = keccak256(abi.encodePacked(taskIndex, poolKey, actualRedistribution, isValid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Submit task response
        operatorContract.submitTaskResponse(taskIndex, poolKey, actualRedistribution, isValid, signature);

        // Verify task submission was recorded
        ShadowSwapOperator.TaskSubmission memory submission = operatorContract.getTaskSubmission(taskIndex, operator1);
        assertEq(submission.actualRedistribution, actualRedistribution);
        assertTrue(submission.timestamp > 0);

        vm.stopPrank();
    }

    function testOperatorPerformanceTracking() public {
        vm.startPrank(operator1);

        // Register operator
        operatorContract.registerAsOperator("https://operator1-metadata.com", 1);

        // Get initial performance
        (uint256 successful, uint256 total, uint256 rate, uint256 lastCompleted) =
            operatorContract.getOperatorPerformance(operator1);

        assertEq(successful, 0);
        assertEq(total, 0);
        assertEq(rate, 0);

        vm.stopPrank();
    }

    function testOperatorSlashing() public {
        // First register an operator through the operator contract
        vm.startPrank(operator1);
        operatorContract.registerAsOperator("https://operator1-metadata.com", 1);
        vm.stopPrank();

        // Add some stake first so we can slash it
        vm.startPrank(deployer);
        operatorContract.rewardOperator(operator1, 2000); // Add stake first

        // Slash the operator
        operatorContract.slashOperator(operator1, 1000, "Invalid task submission");

        // Verify operator stake was reduced
        uint256 stake = operatorContract.getOperatorStake(operator1);
        assertEq(stake, 1000); // 2000 - 1000 = 1000

        vm.stopPrank();
    }

    function testMultipleOperators() public {
        // Register multiple operators
        vm.startPrank(operator1);
        avs.registerOperator();
        vm.stopPrank();

        vm.startPrank(operator2);
        avs.registerOperator();
        vm.stopPrank();

        // Verify both are registered
        assertTrue(avs.isOperatorRegistered(operator1));
        assertTrue(avs.isOperatorRegistered(operator2));

        address[] memory operators = avs.getRegisteredOperators();
        assertEq(operators.length, 2);
    }
}

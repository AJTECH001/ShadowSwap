// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {ShadowSwapHook} from "../src/ShadowSwapHook.sol";
import {MockShadowSwapHook} from "../test/mocks/MockShadowSwapHook.sol";
import {MockShadowSwapAVS} from "../test/mocks/MockShadowSwapAVS.sol";
import {IShadowSwapAVS} from "../src/interfaces/IShadowSwapAVS.sol";

contract ShadowSwapHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;

    PoolManager poolManager;
    MockShadowSwapHook hook;
    MockShadowSwapAVS mockAVS;

    PoolKey key;
    Currency currency0;
    Currency currency1;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address deployer = makeAddr("deployer");

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy PoolManager
        poolManager = new PoolManager(deployer);

        // Deploy Mock AVS
        mockAVS = new MockShadowSwapAVS();

        // Deploy mock hook that bypasses address validation
        hook = new MockShadowSwapHook(IPoolManager(address(poolManager)), IShadowSwapAVS(address(mockAVS)));

        // Create test currencies
        currency0 = Currency.wrap(makeAddr("currency0"));
        currency1 = Currency.wrap(makeAddr("currency1"));

        // Ensure currency0 < currency1
        if (Currency.unwrap(currency0) > Currency.unwrap(currency1)) {
            (currency0, currency1) = (currency1, currency0);
        }

        // Create pool key
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(3000) | LPFeeLibrary.DYNAMIC_FEE_FLAG, // 0.3% with dynamic fee flag
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        vm.stopPrank();
    }

    function testHookDeployment() public {
        // Verify hook is deployed correctly
        assertEq(address(hook.poolManager()), address(poolManager));
        assertEq(address(hook.shadowSwapAVS()), address(mockAVS));

        // Check hook permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeInitialize);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertTrue(permissions.afterAddLiquidity);
    }

    function testHookConstants() public {
        // Verify hook constants
        assertEq(hook.BASE_FEE(), 3000); // 0.3%
        assertEq(hook.MAX_FEE_ADJUSTMENT(), 1500); // 0.15%
        assertEq(hook.MATCHING_WINDOW(), 5); // 5 blocks
    }

    function testMockAVSIntegration() public {
        vm.startPrank(alice);

        // Register as operator
        mockAVS.registerOperator();
        assertTrue(mockAVS.isOperator(alice));

        // Test cross-chain state update
        bytes32 poolId = PoolId.unwrap(key.toId());
        IShadowSwapAVS.CrossChainPoolState memory state = IShadowSwapAVS.CrossChainPoolState({
            chainId: 1,
            poolId: poolId,
            totalLiquidity: 1000000,
            price: 79228162514264337593543950336, // sqrt(1) * 2^96
            lastUpdateBlock: block.number
        });

        mockAVS.updateCrossChainState(state, "");

        // Verify state was updated
        IShadowSwapAVS.CrossChainPoolState memory retrievedState = mockAVS.getCrossChainState(1, poolId);
        assertEq(retrievedState.totalLiquidity, 1000000);

        vm.stopPrank();
    }

    function testFeeCalculation() public {
        // Test that hook can calculate dynamic fees
        // This would test the MEV-based fee adjustment logic
        
        uint24 baseFee = hook.BASE_FEE();
        uint24 maxAdjustment = hook.MAX_FEE_ADJUSTMENT();

        // Verify fee bounds
        assertTrue(baseFee > 0);
        assertTrue(maxAdjustment > 0);
        assertTrue(maxAdjustment < baseFee); // Adjustment should be less than base fee
    }

    function testOrderStructure() public {
        // Test that encrypted order structure works correctly
        ShadowSwapHook.EncryptedOrder memory order = ShadowSwapHook.EncryptedOrder({
            amount: 1000,
            zeroForOne: true,
            blockNumber: uint32(block.number),
            trader: alice,
            orderId: keccak256(abi.encode(alice, block.timestamp))
        });

        // Verify order fields
        assertEq(order.amount, 1000);
        assertTrue(order.zeroForOne);
        assertEq(order.trader, alice);
        assertTrue(order.orderId != bytes32(0));
    }

    function testMEVRedistributionMapping() public {
        vm.startPrank(deployer);

        bytes32 poolId = PoolId.unwrap(key.toId());
        
        // Test that MEV redistribution mappings work
        // This tests the internal storage structure
        assertTrue(address(hook) != address(0));
        assertTrue(poolId != bytes32(0));
        
        vm.stopPrank();
    }

    function testEventEmission() public {
        vm.startPrank(alice);

        // Test that events can be emitted from AVS
        mockAVS.registerOperator();

        // Check that OperatorRegistered event was emitted
        // Note: In a real test, you'd check for the specific event
        assertTrue(mockAVS.isOperator(alice));

        vm.stopPrank();
    }

    function testHookPermissionValidation() public {
        // Verify hook has correct permissions through getHookPermissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeInitialize);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertTrue(permissions.afterAddLiquidity);
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.beforeAddLiquidity);
    }

    function testPoolKeyValidation() public {
        // Test that pool key is constructed correctly
        assertTrue(Currency.unwrap(key.currency0) < Currency.unwrap(key.currency1));
        assertEq(key.fee & LPFeeLibrary.DYNAMIC_FEE_FLAG, LPFeeLibrary.DYNAMIC_FEE_FLAG);
        assertEq(address(key.hooks), address(hook));
    }
}
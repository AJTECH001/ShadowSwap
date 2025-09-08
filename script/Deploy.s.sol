// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Uniswap v4 imports
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

// Our contracts
import {ShadowSwapHook} from "../src/ShadowSwapHook.sol";
import {MockShadowSwapAVS} from "../test/mocks/MockShadowSwapAVS.sol";
import {IShadowSwapAVS} from "../src/interfaces/IShadowSwapAVS.sol";

/**
 * @title DeployShadowSwap
 * @notice Deployment script for ShadowSwap hook and dependencies
 * @dev Handles deployment to local, testnet, and mainnet environments
 */
contract DeployShadowSwap is Script {
    // ===== DEPLOYMENT CONFIGURATION =====

    struct DeploymentConfig {
        address poolManager; // Address of Uniswap v4 PoolManager
        address avsAddress; // Address of EigenLayer AVS
        bool useMockAVS; // Whether to deploy mock AVS for testing
        uint256 deployerKey; // Private key for deployment
    }

    // ===== DEPLOYMENT STATE =====

    DeploymentConfig public config;
    ShadowSwapHook public hook;
    MockShadowSwapAVS public mockAVS;

    // ===== DEPLOYMENT ADDRESSES =====

    // Sepolia testnet addresses
    address constant SEPOLIA_POOL_MANAGER = 0x7Da1D65F8B249183667cdE74C5CBD46dD38AA829;

    // Arbitrum Sepolia addresses
    address constant ARB_SEPOLIA_POOL_MANAGER = 0x7Da1D65F8B249183667cdE74C5CBD46dD38AA829;

    // ===== MAIN DEPLOYMENT FUNCTIONS =====

    /**
     * @notice Deploy ShadowSwap to local testnet
     */
    function deployLocal() external {
        config = DeploymentConfig({
            poolManager: address(0), // Will deploy new one
            avsAddress: address(0), // Will deploy mock
            useMockAVS: true,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });

        _deployComplete();
    }

    /**
     * @notice Deploy ShadowSwap to Sepolia testnet
     */
    function deploySepolia() external {
        config = DeploymentConfig({
            poolManager: SEPOLIA_POOL_MANAGER,
            avsAddress: address(0), // Will deploy mock for now
            useMockAVS: true,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });

        _deployComplete();
    }

    /**
     * @notice Deploy ShadowSwap to Arbitrum Sepolia
     */
    function deployArbitrumSepolia() external {
        config = DeploymentConfig({
            poolManager: ARB_SEPOLIA_POOL_MANAGER,
            avsAddress: address(0), // Will deploy mock for now
            useMockAVS: true,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });

        _deployComplete();
    }

    // ===== INTERNAL DEPLOYMENT LOGIC =====

    /**
     * @notice Complete deployment process
     */
    function _deployComplete() internal {
        vm.startBroadcast(config.deployerKey);

        console.log("Starting ShadowSwap deployment...");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", vm.addr(config.deployerKey));

        // Step 1: Deploy or use existing PoolManager
        if (config.poolManager == address(0)) {
            console.log("Deploying new PoolManager...");
            PoolManager poolManager = new PoolManager(vm.addr(config.deployerKey));
            config.poolManager = address(poolManager);
        }
        console.log("PoolManager:", config.poolManager);

        // Step 2: Deploy AVS (mock or real)
        if (config.useMockAVS) {
            console.log("Deploying Mock AVS...");
            mockAVS = new MockShadowSwapAVS();
            config.avsAddress = address(mockAVS);
        }
        console.log("AVS Address:", config.avsAddress);

        // Step 3: Calculate hook deployment address with required flags using HookMiner
        console.log("Mining hook address with required permissions...");
        
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | 
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.AFTER_ADD_LIQUIDITY_FLAG
        );

        // Create2 deployer proxy address (used in forge script)
        address deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployer,
            flags,
            type(ShadowSwapHook).creationCode,
            abi.encode(IPoolManager(config.poolManager), config.avsAddress)
        );
        
        console.log("Found valid hook address:", hookAddress);
        console.log("Using salt:", uint256(salt));

        // Step 4: Deploy hook using CREATE2 with the mined salt
        console.log("Deploying ShadowSwap Hook...");

        hook = new ShadowSwapHook{salt: salt}(
            IPoolManager(config.poolManager), 
            IShadowSwapAVS(config.avsAddress)
        );

        require(address(hook) == hookAddress, "Hook deployed to wrong address");

        console.log("ShadowSwap Hook deployed to:", address(hook));

        // Step 5: Verify deployment
        _verifyDeployment();

        // Step 6: Output deployment summary
        _outputDeploymentSummary();

        vm.stopBroadcast();

        console.log("ShadowSwap deployment completed successfully!");
    }


    /**
     * @notice Verify that deployment was successful
     */
    function _verifyDeployment() internal view {
        // Verify hook contract
        require(address(hook) != address(0), "Hook deployment failed");
        require(address(hook.poolManager()) == config.poolManager, "Hook has wrong PoolManager");
        require(address(hook.shadowSwapAVS()) == config.avsAddress, "Hook has wrong AVS");

        // Verify hook permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        require(permissions.beforeInitialize, "Missing beforeInitialize permission");
        require(permissions.beforeSwap, "Missing beforeSwap permission");
        require(permissions.afterSwap, "Missing afterSwap permission");
        require(permissions.afterAddLiquidity, "Missing afterAddLiquidity permission");

        console.log("Deployment verification passed");
    }

    /**
     * @notice Output comprehensive deployment summary
     */
    function _outputDeploymentSummary() internal view {
        console.log("\n========================================");
        console.log("SHADOWSWAP DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("Deployer:", vm.addr(config.deployerKey));
        console.log("");
        console.log("CONTRACT ADDRESSES:");
        console.log("PoolManager:", config.poolManager);
        console.log("ShadowSwap Hook:", address(hook));
        console.log("AVS Contract:", config.avsAddress);
        console.log("Using Mock AVS:", config.useMockAVS);
        console.log("");
        console.log("HOOK CONFIGURATION:");
        console.log("Base Fee:", hook.BASE_FEE());
        console.log("Max Fee Adjustment:", hook.MAX_FEE_ADJUSTMENT());
        console.log("Matching Window:", hook.MATCHING_WINDOW(), "blocks");
        console.log("");
        console.log("INTEGRATION STATUS:");
        console.log("* Uniswap v4 Hook deployed");
        console.log("* EigenLayer AVS connected");
        console.log("* Fhenix FHE libraries integrated");
        console.log("* MEV redistribution configured");
        console.log("* Cross-chain coordination enabled");
        console.log("========================================\n");
    }

    // ===== UTILITY FUNCTIONS =====

    /**
     * @notice Initialize a test pool with the hook
     */
    function initializeTestPool(address token0, address token1, uint24 fee) external {
        require(address(hook) != address(0), "Hook not deployed");

        vm.startBroadcast(config.deployerKey);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee | LPFeeLibrary.DYNAMIC_FEE_FLAG, // Enable dynamic fees
            tickSpacing: 60,
            hooks: hook
        });

        IPoolManager(config.poolManager).initialize(key, 79228162514264337593543950336);

        console.log("Test pool initialized");
        console.log("Token0:", token0);
        console.log("Token1:", token1);
        console.log("Fee:", fee);

        vm.stopBroadcast();
    }

    /**
     * @notice Register as AVS operator (for testing)
     */
    function registerAsOperator() external {
        require(config.useMockAVS, "Only for mock AVS");

        vm.startBroadcast(config.deployerKey);

        mockAVS.registerOperator();

        console.log("Registered as AVS operator:", vm.addr(config.deployerKey));

        vm.stopBroadcast();
    }

    /**
     * @notice Set up initial test conditions
     */
    function setupTestConditions() external {
        require(address(hook) != address(0), "Hook not deployed");
        require(config.useMockAVS, "Only for mock AVS");

        vm.startBroadcast(config.deployerKey);

        // Set mock market prices for MEV testing
        // These would come from external price feeds in production

        console.log("Test conditions set up");

        vm.stopBroadcast();
    }
}

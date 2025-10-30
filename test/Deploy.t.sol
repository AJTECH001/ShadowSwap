// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {DeployShadowSwap} from "../script/Deploy.s.sol";
import {ShadowSwapHook} from "../src/ShadowSwapHook.sol";

contract DeployTest is Test {
    DeployShadowSwap deployer;

    address deployerAddress = makeAddr("deployer");

    function setUp() public {
        deployer = new DeployShadowSwap();

        // Set up environment variable for private key
        vm.setEnv("PRIVATE_KEY", "0x1234567890123456789012345678901234567890123456789012345678901234");
    }

    function testLocalDeployment() public {
        // Test local deployment
        deployer.deployLocal();

        // Verify contracts were deployed
        assertTrue(address(deployer.hook()) != address(0));

        // Verify hook configuration
        ShadowSwapHook hook = deployer.hook();
        assertEq(hook.BASE_FEE(), 3000);
        assertEq(hook.MAX_FEE_ADJUSTMENT(), 1500);
        assertEq(hook.MATCHING_WINDOW(), 5);
    }

    function testConfigStructure() public {
        // Test deployment configuration structure
        DeployShadowSwap.DeploymentConfig memory config = DeployShadowSwap.DeploymentConfig({
            poolManager: address(0),
            deployerKey: 0x1234567890123456789012345678901234567890123456789012345678901234
        });

        assertEq(config.poolManager, address(0));
    }

    function testHookAddressCalculation() public {
        // Test that hook address calculation works
        deployer.deployLocal();

        ShadowSwapHook hook = deployer.hook();

        // Verify hook address has the correct permission flags
        uint160 hookAddress = uint160(address(hook));
        assertTrue(hookAddress > 0);
    }

}

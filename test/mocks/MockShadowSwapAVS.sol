// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ShadowSwapServiceManager} from "../../src/avs/ShadowSwapServiceManager.sol";

/**
 * @title MockShadowSwapAVS
 * @notice A simple mock for ShadowSwapServiceManager to facilitate script testing.
 */
contract MockShadowSwapAVS is ShadowSwapServiceManager {
    constructor(address _hook, address _avsDir) ShadowSwapServiceManager(_hook, _avsDir) {}
}

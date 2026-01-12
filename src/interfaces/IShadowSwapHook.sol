// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IShadowSwapHook {
    function executeMatch(bytes32 poolId, bytes32 orderId1, bytes32 orderId2) external;
}

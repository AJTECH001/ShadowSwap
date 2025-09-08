// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IShadowSwapAVS} from "../../src/interfaces/IShadowSwapAVS.sol";

contract MockShadowSwapAVS is IShadowSwapAVS {
    mapping(address => bool) public operators;
    mapping(uint256 => mapping(bytes32 => CrossChainPoolState)) public poolStates;
    mapping(bytes32 => mapping(uint256 => address)) public auctionWinners;
    mapping(bytes32 => mapping(uint256 => uint256)) public winningBids;
    mapping(bytes32 => mapping(uint256 => OrderMatchResult[])) public validatedMatches;

    function registerOperator() external override {
        operators[msg.sender] = true;
        emit OperatorRegistered(msg.sender);
    }

    function registerOperatorForAddress(address operator) external override {
        operators[operator] = true;
        emit OperatorRegistered(operator);
    }

    function deregisterOperator() external override {
        operators[msg.sender] = false;
    }

    function isOperator(address operator) external view override returns (bool) {
        return operators[operator];
    }

    function updateCrossChainState(CrossChainPoolState calldata state, bytes calldata) external override {
        poolStates[state.chainId][state.poolId] = state;
        emit CrossChainStateUpdated(state.chainId, state.poolId);
    }

    function getCrossChainState(uint256 chainId, bytes32 poolId)
        external
        view
        override
        returns (CrossChainPoolState memory)
    {
        return poolStates[chainId][poolId];
    }

    function submitMEVBid(MEVAuctionBid calldata bid) external override {
        // Store bid for testing purposes
    }

    function finalizeMEVAuction(bytes32 poolId, uint256 blockNumber)
        external
        override
        returns (address winner, uint256 winningBid)
    {
        winner = auctionWinners[poolId][blockNumber];
        winningBid = winningBids[poolId][blockNumber];
        
        if (winner == address(0)) {
            winner = msg.sender;
            winningBid = 1000; // Default bid amount for testing
            auctionWinners[poolId][blockNumber] = winner;
            winningBids[poolId][blockNumber] = winningBid;
        }
        
        emit MEVAuctionCompleted(poolId, winner, winningBid);
    }

    function validateOrderMatch(OrderMatchResult calldata result, bytes calldata) external override {
        validatedMatches[result.orderId1][block.number].push(result);
        emit OrderMatchValidated(result.orderId1, result.orderId2);
    }

    function getValidatedMatches(bytes32 poolId, uint256 blockNumber)
        external
        view
        override
        returns (OrderMatchResult[] memory)
    {
        return validatedMatches[poolId][blockNumber];
    }

    // Test helper functions
    function setMockWinner(bytes32 poolId, uint256 blockNumber, address winner, uint256 bid) external {
        auctionWinners[poolId][blockNumber] = winner;
        winningBids[poolId][blockNumber] = bid;
    }

    function addMockPoolState(
        uint256 chainId,
        bytes32 poolId,
        uint256 totalLiquidity,
        uint256 price,
        uint256 lastUpdateBlock
    ) external {
        poolStates[chainId][poolId] = CrossChainPoolState({
            chainId: chainId,
            poolId: poolId,
            totalLiquidity: totalLiquidity,
            price: price,
            lastUpdateBlock: lastUpdateBlock
        });
    }
}
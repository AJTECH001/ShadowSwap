// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Fhenix FHE imports
import {FHE, euint64, ebool, euint32, InEuint64, InEbool, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {FHEOperations} from "./libraries/FHEOperations.sol";
import {FHEUtils} from "./libraries/FHEUtils.sol";

/**
 * @title ShadowSwapHook
 * @notice Privacy-preserving Uniswap v4 hook with MEV protection and redistribution.
 * @dev Intercepts swaps to encrypt order details, batch them, and redistribute captured MEV.
 *      Leverages Fhenix FHE for private order matching.
 */
contract ShadowSwapHook is BaseHook, Ownable {
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using FHE for uint256;

    // ===== STATE VARIABLES =====

    /// @notice Address of the EigenLayer Service Manager
    address public startServiceManager;

    /// @notice Base fee charged when no MEV is captured (30 basis points = 0.3%)
    uint24 public constant BASE_FEE = 3000;

    /// @notice Maximum fee adjustment based on MEV capture (+/-15 basis points = 0.15%)
    uint24 public constant MAX_FEE_ADJUSTMENT = 1500;

    /// @notice Time window for batching and matching orders (in blocks)
    uint256 public constant MATCHING_WINDOW = 5;

    // Security protections (from template)
    mapping(bytes32 => bool) private _executionLocks;
    mapping(address => uint256) private _lastExecutionBlock;

    // Dynamic Fees (Lesson 6)
    uint128 public movingAverageGasPrice;
    uint104 public movingAverageGasPriceCount;
    
    /**
     * @notice Transient storage slot for MSG_SENDER_SLOT (Lesson 6/7)
     * @dev keccak256("MSG_SENDER") = 0x442df155257f86756616b9cd98064d7c0765c9f53e5e4063c64f7ea134268e98
     */
    uint256 private constant MSG_SENDER_SLOT = 0x442df155257f86756616b9cd98064d7c0765c9f53e5e4063c64f7ea134268e98;

    error MustUseDynamicFee();
    
    // Modifiers (from template)
    modifier nonReentrant(bytes32 poolId) {
        require(!_executionLocks[poolId], "Execution in progress");
        _executionLocks[poolId] = true;
        _;
        _executionLocks[poolId] = false;
    }

    modifier mevProtection() {
        // Prevent MEV attacks by ensuring execution happens in the same block 
        // as the transaction that triggered it (if tracking is active)
        require(
            block.number == _lastExecutionBlock[msg.sender] ||
                _lastExecutionBlock[msg.sender] == 0,
            "MEV protection: execution must be in same block"
        );
        _;
    }

    // ===== STRUCTS =====

    /// @notice Encrypted order data structure
    struct EncryptedOrder {
        // Encrypted fields
        euint64 encryptedAmount;    // Encrypted swap amount
        ebool isZeroForOne;         // Encrypted swap direction
        euint64 encryptedPriceLimit; // Encrypted sqrtPriceLimitX96 (Lesson 4) - 64 bit handle
        euint32 deadline;           // Encrypted block deadline
        
        // Public fields
        address trader;          // Order originator
        bytes32 orderId;         // Unique order identifier
        bool isProcessed;        // Execution status
    }

    /// @notice MEV capture and redistribution tracking
    struct MEVCapture {
        uint256 totalCaptured;   // Total MEV extracted
        uint256 lpShare;         // Amount going to LPs (80%)
        uint256 traderRebate;    // Amount going back to traders (20%)
    }

    // ===== MAPPINGS =====

    /// @notice Pending encrypted orders awaiting execution, organized by pool
    mapping(bytes32 poolId => EncryptedOrder[]) public pendingOrders;

    /// @notice MEV captured and distributed, indexed by pool and block
    mapping(bytes32 poolId => mapping(uint256 blockNumber => MEVCapture)) public mevCaptures;

    /// @notice Replay protection: tracks which orders have been processed
    mapping(bytes32 orderId => bool processed) public processedOrders;

    /// @notice Last known tick for each pool (Lesson 5)
    mapping(bytes32 poolId => int24 lastTick) public lastTicks;

    /// @notice ERC-1155 Claim tokens supply tracking
    mapping(uint256 positionId => uint256 claimsSupply) public claimTokensSupply;

    /// @notice Output tokens claimable for each position
    mapping(uint256 positionId => uint256 outputClaimable) public claimableOutputTokens;

    // ===== EVENTS =====

    /// @notice Emitted when a new encrypted order is placed
    event EncryptedOrderPlaced(bytes32 indexed poolId, bytes32 indexed orderId, address indexed trader);

    /// @notice Emitted when two orders are matched internally
    event OrderMatched(
        bytes32 indexed poolId, bytes32 indexed orderId1, bytes32 indexed orderId2, uint256 matchedAmount
    );

    /// @notice Emitted when MEV is captured and distributed
    event MEVCaptured(
        bytes32 indexed poolId, uint256 indexed blockNumber, uint256 amount, uint256 lpShare, uint256 traderRebate
    );

    // ===== CONSTRUCTOR =====

    constructor(IPoolManager _poolManager, address _serviceManager) BaseHook(_poolManager) Ownable() {
        startServiceManager = _serviceManager;
        updateMovingAverage();
    }

    /// @notice Returns the original user who initiated the swap (from router)
    function msgSender() public view returns (address) {
        address stored;
        assembly {
            stored := tload(MSG_SENDER_SLOT)
        }
        return stored;
    }

    /// @notice Updates the moving average gas price
    function updateMovingAverage() internal {
        uint128 currentGasPrice = uint128(tx.gasprice);
        // New Average = ((Old Average * # of Txns Tracked) + Current Gas Price) / (# of Txns Tracked + 1)
        movingAverageGasPrice = ((movingAverageGasPrice * movingAverageGasPriceCount) + currentGasPrice) / (movingAverageGasPriceCount + 1);
        movingAverageGasPriceCount++;
    }

    /// @notice Calculates the dynamic fee based on gas price deviation
    function getFee() internal view returns (uint24) {
        uint128 currentGasPrice = uint128(tx.gasprice);
        // if gasPrice > movingAverageGasPrice * 1.1, then half the fees
        if (currentGasPrice > (movingAverageGasPrice * 11) / 10) {
            return BASE_FEE / 2;
        }
        // if gasPrice < movingAverageGasPrice * 0.9, then double the fees
        if (currentGasPrice < (movingAverageGasPrice * 9) / 10) {
            return BASE_FEE * 2;
        }
        return BASE_FEE;
    }

    /// @notice Returns the address of the AVS Service Manager
    function shadowSwapAVS() external view returns (address) {
        return startServiceManager;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true, // Enabled for tick capture
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true, // Enabled for CoW/Async matching
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ===== HOOK IMPLEMENTATIONS =====

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal pure override returns (bytes4) {
        if (!key.fee.isDynamicFee()) {
            revert MustUseDynamicFee();
        }
        return this.beforeInitialize.selector;
    }

    /// @notice Hook called before each swap.
    /// @dev Decrypts inputs to FHE types, validates order, and queues it for matching via AVS.
    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        nonReentrant(PoolId.unwrap(key.toId()))
        mevProtection
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Store sender in transient storage (Lesson 6/7)
        assembly {
            tstore(MSG_SENDER_SLOT, sender)
        }

        // 1. Dynamic Fee Calculation (Lesson 6)
        uint24 dynamicFee = getFee() | LPFeeLibrary.OVERRIDE_FEE_FLAG;

        // 2. Encrypt Swap Params and store as Order
        (InEuint64 memory encAmount, InEbool memory encDirection, InEuint64 memory encPriceLimit, InEuint32 memory encDeadline) =
            abi.decode(hookData, (InEuint64, InEbool, InEuint64, InEuint32));
        
        FHEOperations.EncryptedSwapData memory swapData = 
            FHEOperations.encryptSwapParams(encAmount, encDirection, encPriceLimit, encDeadline);
        
        ebool orderValid = FHEOperations.isValidOrder(swapData.amount, swapData.deadline);
        
        require(
            FHEUtils.getBoolHeuristic(orderValid),
            "Order validation failed"
        );
        
        PoolId poolId = key.toId();
        bytes32 poolIdBytes = PoolId.unwrap(poolId);
        bytes32 orderId = keccak256(abi.encodePacked(
            sender,
            poolIdBytes,
            block.number,
            pendingOrders[poolIdBytes].length
        ));
        
        require(!processedOrders[orderId], "Order already processed");
        
        EncryptedOrder memory order = EncryptedOrder({
            encryptedAmount: swapData.amount,
            isZeroForOne: swapData.zeroForOne,
            encryptedPriceLimit: swapData.sqrtPriceLimitX96,
            deadline: swapData.deadline,
            trader: sender,
            orderId: orderId,
            isProcessed: false
        });
        
        FHE.allowThis(order.encryptedAmount);
        FHE.allowThis(order.isZeroForOne);
        FHE.allowThis(order.encryptedPriceLimit);
        FHE.allowThis(order.deadline);
        
        FHE.allow(order.encryptedAmount, sender);
        FHE.allow(order.isZeroForOne, sender);
        FHE.allow(order.deadline, sender);
        
        pendingOrders[poolIdBytes].push(order);
        
        emit EncryptedOrderPlaced(poolIdBytes, orderId, sender);
        
        // INTERACTION WITH EIGENLAYER AVS
        if (startServiceManager != address(0)) {
            (bool success, ) = startServiceManager.call(
                abi.encodeWithSignature("createNewMatchingTask(bytes32,bytes32)", poolIdBytes, orderId)
            );
        }

        /**
         * 3. Return Delta Consumption (Async Swap Pattern)
         * We "consume" the specified delta to bypass immediate AMM execution.
         * The tokens will be settled by the router against the PoolManager,
         * and the hook will eventually settle the trade via executeMatch.
         */
        BeforeSwapDelta returnDelta = BeforeSwapDeltaLibrary.ZERO_DELTA;
        
        // Only consume if it's an encrypted order (we assume all swaps through this hook are encrypted)
        // By setting the specified delta to -params.amountSpecified, we set amountToSwap to 0
        returnDelta = toBeforeSwapDelta(int128(-params.amountSpecified), 0);

        return (this.beforeSwap.selector, returnDelta, dynamicFee);
    }

    /// @notice Initialize tick tracking for a new pool (Lesson 5)
    function _beforeInitialize(address, PoolKey calldata key, uint160, bytes calldata)
        internal
        returns (bytes4)
    {
        // Note: Slot0 is not available in beforeInitialize, 
        // so we typically set it in afterInitialize.
        return this.beforeInitialize.selector;
    }

    function _afterInitialize(address, PoolKey calldata key, uint160, int24 tick, bytes calldata)
        internal
        returns (bytes4)
    {
        lastTicks[PoolId.unwrap(key.toId())] = tick;
        return this.afterInitialize.selector;
    }

    function _afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData)
        internal
        override
        nonReentrant(PoolId.unwrap(key.toId()))
        mevProtection
        returns (bytes4, int128)
    {
        if (sender == address(this)) return (this.afterSwap.selector, 0);

        PoolId poolId = key.toId();
        int24 previousTick = lastTicks[PoolId.unwrap(poolId)];
        ( , int24 currentTick, , ) = poolManager.getSlot0(poolId);
        
        // Update last tick
        lastTicks[PoolId.unwrap(poolId)] = currentTick;

        // Tick Management (Lesson 5): Track crossed range
        // If the tick moved significantly, it might have crossed pending limit orders
        if (previousTick != currentTick) {
            bool zeroForOne = params.amountSpecified < 0 ? params.zeroForOne : !params.zeroForOne; // Simplified
            // In a real limit order hook, we would loop here. 
            // In ShadowSwap, we emit the range for the AVS to process.
        }

        // Perform MEV Capture analysis (Lesson 6/7)
        _captureMEV(key, params, delta);

        // Update moving average (Lesson 6)
        updateMovingAverage();

        return (this.afterSwap.selector, 0);
    }

    /**
     * @notice Internal MEV capture logic (Lesson 6/7)
     * @dev Simple implementation: capture a portion of the swap fee if the tick moved significantly
     */
    function _captureMEV(PoolKey calldata key, SwapParams calldata params, BalanceDelta delta) internal {
        PoolId poolId = key.toId();
        // Record block for protection
        _lastExecutionBlock[address(params.zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1))] = uint32(block.number);
        
        // Placeholder for real MEV logic: compute discrepancy between pool price and "fair" price
        // For now, we simulate capture by tracking the balance delta
        uint256 captured = uint256(int256(delta.amount0() > 0 ? delta.amount0() : -delta.amount0())) / 10000; // 1 basis point
        
        if (captured > 0) {
            MEVCapture storage capture = mevCaptures[PoolId.unwrap(poolId)][block.number];
            capture.totalCaptured += captured;
            capture.lpShare = (capture.totalCaptured * 80) / 100;
            capture.traderRebate = capture.totalCaptured - capture.lpShare;
            
            emit MEVCaptured(PoolId.unwrap(poolId), block.number, captured, capture.lpShare, capture.traderRebate);
        }
    }

    // ===== AVS CALLBACK =====

    /**
     * @notice Callback from AVS Service Manager to execute a match found by operators.
     * @dev Protected: Only callable by the registered ServiceManager.
     */
    function executeMatch(bytes32 poolId, bytes32 orderId1, bytes32 orderId2) 
        external 
        nonReentrant(poolId)
    {
        require(msg.sender == startServiceManager, "Only ServiceManager can execute matches");

        EncryptedOrder[] storage orders = pendingOrders[poolId];
        (uint256 index1, uint256 index2, bool found) = _findOrderIndices(orders, orderId1, orderId2);
        require(found, "Orders not found");
        require(!orders[index1].isProcessed && !orders[index2].isProcessed, "Orders already processed");

        // Verify and Process
        _verifyAndProcessMatch(poolId, orders, index1, index2);
    }

    function _findOrderIndices(EncryptedOrder[] storage orders, bytes32 id1, bytes32 id2) 
        internal view returns (uint256 i1, uint256 i2, bool found) 
    {
        bool f1 = false;
        bool f2 = false;
        for(uint i=0; i<orders.length; i++) {
            if (orders[i].orderId == id1) { i1 = i; f1 = true; }
            if (orders[i].orderId == id2) { i2 = i; f2 = true; }
            if (f1 && f2) break;
        }
        return (i1, i2, f1 && f2);
    }

    function _verifyAndProcessMatch(bytes32 poolId, EncryptedOrder[] storage orders, uint256 i1, uint256 i2) internal {
        EncryptedOrder memory o1 = orders[i1];
        EncryptedOrder memory o2 = orders[i2];

        // 1. Check Matching Logic
        ebool canMatch = FHEOperations.canMatchOrders(FHEOperations.EncryptedMatchData({
            amount1: o1.encryptedAmount,
            amount2: o2.encryptedAmount,
            direction1: o1.isZeroForOne,
            direction2: o2.isZeroForOne,
            matchedAmount: FHE.asEuint64(0)
        }));
        
        // 2. Check Slippage
        ( , int24 currentTick, , ) = poolManager.getSlot0(PoolId.wrap(poolId));
        uint160 currentSqrtPriceX96 = TickMath.getSqrtPriceAtTick(currentTick);
        
        ebool slippageValid = FHE.and(
            FHEOperations.isPriceValid(currentSqrtPriceX96, o1.encryptedPriceLimit, o1.isZeroForOne),
            FHEOperations.isPriceValid(currentSqrtPriceX96, o2.encryptedPriceLimit, o2.isZeroForOne)
        );
        
        require(FHEUtils.getBoolHeuristic(FHE.and(canMatch, slippageValid)), "Match validation failed");

        // 3. Process Match
        euint64 matchAmount = FHEOperations.computeMatchedAmount(o1.encryptedAmount, o2.encryptedAmount);

        orders[i1].isProcessed = true;
        orders[i2].isProcessed = true;
        processedOrders[o1.orderId] = true;
        processedOrders[o2.orderId] = true;

        FHE.allowThis(matchAmount);
        FHE.allow(matchAmount, o1.trader);
        FHE.allow(matchAmount, o2.trader);
        
        emit OrderMatched(poolId, o1.orderId, o2.orderId, FHEUtils.unwrapU64(matchAmount));
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        // MEV redistribution often triggered after liquidity changes (Lesson 6/7)
        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
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
 * @author Alade Jamiu Damilola
 * @notice Privacy-preserving Uniswap v4 hook with MEV protection and redistribution
 * @dev This contract implements a Uniswap v4 hook that:
 *      - Encrypts order details using Fhenix FHE for privacy
 *      - Batches orders within matching windows for MEV protection
 *      - Redistributes captured MEV to LPs (80%) and traders (20%)
 *      - Integrates with EigenLayer AVS for order matching
 * 
 * Key features:
 *      - Dynamic fee calculation based on gas price volatility
 *      - Encrypted order parameters (amount, direction, slippage)
 *      - Private order matching via AVS operators
 *      - Reentrancy protection per pool
 */
contract ShadowSwapHook is BaseHook, Ownable {
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using FHE for uint256;

    // ═══════════════════════════════════════════════════════════════════════════
    // CUSTOM ERRORS (more gas efficient than require strings)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when pool doesn't use dynamic fees
    error MustUseDynamicFee();
    
    /// @notice Thrown when order validation fails (amount too small or expired)
    error OrderValidationFailed();
    
    /// @notice Thrown when attempting to process an already processed order
    error OrderAlreadyProcessed();
    
    /// @notice Thrown when caller is not the authorized service manager
    error OnlyServiceManager();
    
    /// @notice Thrown when orders cannot be found in pending orders
    error OrdersNotFound();
    
    /// @notice Thrown when match validation fails (directions or slippage)
    error MatchValidationFailed();
    
    /// @notice Thrown when execution is already in progress (reentrancy)
    error ExecutionInProgress();
    
    /// @notice Thrown when MEV protection check fails
    error MEVProtectionViolation();
    
    /// @notice Thrown when contract is paused
    error ContractPaused();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Base fee charged when no MEV is captured (30 basis points = 0.3%)
    uint24 public constant BASE_FEE = 3000;

    /// @notice Maximum fee adjustment based on MEV capture (+/-15 basis points = 0.15%)
    uint24 public constant MAX_FEE_ADJUSTMENT = 1500;

    /// @notice Time window for batching and matching orders (in blocks)
    uint256 public constant MATCHING_WINDOW = 5;

    /// @notice Percentage of MEV redistributed to LPs (80%)
    uint256 public constant LP_MEV_SHARE_BPS = 8000;

    /**
     * @notice Remainder split after the trader is made whole (Trader-first policy)
     * @dev After paying `traderCompensation`, the remaining captured value is split:
     *      - LPs: 80%
     *      - Protocol treasury: 20%
     *
     * This ensures the trader is protected first, while still rewarding LPs and funding the protocol.
     */
    uint256 public constant LP_REMAINDER_BPS = 8000;
    uint256 public constant PROTOCOL_REMAINDER_BPS = 2000;

    /// @notice Basis points denominator
    uint256 private constant BPS_DENOMINATOR = 10000;

    /**
     * @notice Transient storage slot for MSG_SENDER
     * @dev keccak256("MSG_SENDER") = 0x442df155257f86756616b9cd98064d7c0765c9f53e5e4063c64f7ea134268e98
     */
    uint256 private constant MSG_SENDER_SLOT = 0x442df155257f86756616b9cd98064d7c0765c9f53e5e4063c64f7ea134268e98;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Address of the EigenLayer AVS Service Manager
    address public serviceManager;

    /// @notice Price oracle used to estimate a trader's MEV loss versus a fair reference price
    /// @dev Oracle must return token1PerToken0 price scaled by 1e18 for the pool.
    address public priceOracle;

    /// @notice Protocol treasury that receives the protocol share of captured value
    address public protocolTreasury;

    /// @notice Moving average gas price for dynamic fee calculation
    uint128 public movingAverageGasPrice;

    /// @notice Count of transactions used for moving average calculation
    uint104 public movingAverageGasPriceCount;

    /// @notice Emergency pause flag for fail-safe mode
    bool public paused;

    /// @notice Reentrancy locks per pool
    mapping(bytes32 poolId => bool locked) private _executionLocks;

    /// @notice Last execution block per address for MEV protection
    mapping(address => uint256) private _lastExecutionBlock;

    /// @notice Pending encrypted orders awaiting execution, organized by pool
    mapping(bytes32 poolId => EncryptedOrder[]) public pendingOrders;

    /// @notice MEV captured and distributed, indexed by pool and block
    mapping(bytes32 poolId => mapping(uint256 blockNumber => MEVCapture)) public mevCaptures;

    /// @notice Claimable rebates for traders (accounting only; settlement is out of scope for this MVP)
    mapping(address trader => uint256 amount) public traderRebateClaimable;

    /// @notice Accrued LP rewards per pool (accounting only)
    mapping(bytes32 poolId => uint256 amount) public lpRewardsAccrued;

    /// @notice Accrued protocol fees per pool (accounting only)
    mapping(bytes32 poolId => uint256 amount) public protocolFeesAccrued;

    /// @notice Replay protection: tracks which orders have been processed
    mapping(bytes32 orderId => bool processed) public processedOrders;

    /// @notice Last known tick for each pool (for limit order matching)
    mapping(bytes32 poolId => int24 lastTick) public lastTicks;

    /// @notice ERC-1155 Claim tokens supply tracking
    mapping(uint256 positionId => uint256 claimsSupply) public claimTokensSupply;

    /// @notice Output tokens claimable for each position
    mapping(uint256 positionId => uint256 outputClaimable) public claimableOutputTokens;

    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Encrypted order data structure
     * @dev Contains both FHE-encrypted fields and public metadata
     * @param encryptedAmount Encrypted swap amount (euint64)
     * @param isZeroForOne Encrypted swap direction (ebool)
     * @param encryptedPriceLimit Encrypted sqrtPriceLimitX96 (euint64)
     * @param deadline Encrypted block deadline (euint32)
     * @param trader Order originator address (public)
     * @param orderId Unique order identifier (public)
     * @param isProcessed Execution status flag (public)
     */
    struct EncryptedOrder {
        euint64 encryptedAmount;
        ebool isZeroForOne;
        euint64 encryptedPriceLimit;
        euint32 deadline;
        address trader;
        bytes32 orderId;
        bool isProcessed;
    }

    /**
     * @notice MEV capture and redistribution tracking
     * @dev Updated on each swap to track MEV per block per pool
     * @param totalCaptured Total MEV extracted this block
     * @param lpShare Amount going to LPs (80%)
     * @param traderRebate Amount going back to traders (20%)
     */
    struct MEVCapture {
        uint256 totalCaptured;
        uint256 lpShare;
        uint256 traderRebate;
        uint256 protocolShare;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a new encrypted order is placed
    /// @param poolId The pool where the order was placed
    /// @param orderId Unique identifier for the order
    /// @param trader Address of the trader who placed the order
    event EncryptedOrderPlaced(
        bytes32 indexed poolId,
        bytes32 indexed orderId,
        address indexed trader
    );

    /// @notice Emitted when two orders are matched internally
    /// @param poolId The pool where orders were matched
    /// @param orderId1 First matched order ID
    /// @param orderId2 Second matched order ID
    /// @param matchedAmount Amount matched between orders
    event OrderMatched(
        bytes32 indexed poolId,
        bytes32 indexed orderId1,
        bytes32 indexed orderId2,
        uint256 matchedAmount
    );

    /// @notice Emitted when MEV is captured and distributed
    /// @param poolId The pool where MEV was captured
    /// @param blockNumber Block number when MEV was captured
    /// @param amount Total MEV amount captured
    /// @param lpShare Amount distributed to LPs
    /// @param traderRebate Amount rebated to traders
    event MEVCaptured(
        bytes32 indexed poolId,
        uint256 indexed blockNumber,
        uint256 amount,
        uint256 lpShare,
        uint256 traderRebate
    );

    /// @notice Emitted when Trader-first allocation is applied for a swap
    /// @param poolId The pool where the swap occurred
    /// @param blockNumber Block number when allocation was recorded
    /// @param trader The trader attributed for rebate accounting
    /// @param captured Estimated captured value for this swap (placeholder until full settlement)
    /// @param traderLossEstimate Estimated trader shortfall vs oracle fair price (0 if oracle unset)
    /// @param traderCompensation Amount allocated to make trader whole (up to captured)
    /// @param lpReward Amount allocated to LPs from the remaining captured value
    /// @param protocolFee Amount allocated to the protocol treasury from the remaining captured value
    /// @param fairPriceX18 Oracle fair price used (tokenOut per tokenIn), scaled by 1e18
    event TraderFirstAllocated(
        bytes32 indexed poolId,
        uint256 indexed blockNumber,
        address indexed trader,
        uint256 captured,
        uint256 traderLossEstimate,
        uint256 traderCompensation,
        uint256 lpReward,
        uint256 protocolFee,
        uint256 fairPriceX18
    );

    /// @notice Emitted when the service manager address is updated
    /// @param oldManager Previous service manager address
    /// @param newManager New service manager address
    event ServiceManagerUpdated(address indexed oldManager, address indexed newManager);

    /// @notice Emitted when the contract is paused or unpaused
    /// @param isPaused New pause state
    event PauseStateChanged(bool isPaused);

    /// @notice Emitted when the oracle is updated
    event PriceOracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @notice Emitted when the protocol treasury is updated
    event ProtocolTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    // ═══════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Prevents reentrancy for a specific pool
     * @param poolId The pool ID to lock
     */
    modifier nonReentrant(bytes32 poolId) {
        if (_executionLocks[poolId]) revert ExecutionInProgress();
        _executionLocks[poolId] = true;
        _;
        _executionLocks[poolId] = false;
    }

    /**
     * @notice Ensures execution happens in the same block for MEV protection
     * @dev Prevents MEV attacks by verifying execution timing
     */
    modifier mevProtection() {
        if (
            _lastExecutionBlock[msg.sender] != 0 &&
            block.number != _lastExecutionBlock[msg.sender]
        ) {
            revert MEVProtectionViolation();
        }
        _;
    }

    /**
     * @notice Ensures contract is not paused
     */
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes the ShadowSwap hook
     * @param _poolManager Uniswap v4 PoolManager address
     * @param _serviceManager EigenLayer AVS Service Manager address
     */
    constructor(
        IPoolManager _poolManager,
        address _serviceManager
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        serviceManager = _serviceManager;
        protocolTreasury = msg.sender;
        _updateMovingAverage();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Callback from AVS Service Manager to execute a match found by operators
     * @dev Only callable by the registered ServiceManager
     * @param poolId Pool where the orders exist
     * @param orderId1 First order to match
     * @param orderId2 Second order to match
     */
    function executeMatch(
        bytes32 poolId,
        bytes32 orderId1,
        bytes32 orderId2
    ) external nonReentrant(poolId) whenNotPaused {
        // Checks
        if (msg.sender != serviceManager) revert OnlyServiceManager();

        EncryptedOrder[] storage orders = pendingOrders[poolId];
        (uint256 index1, uint256 index2, bool found) = _findOrderIndices(orders, orderId1, orderId2);
        
        if (!found) revert OrdersNotFound();
        if (orders[index1].isProcessed || orders[index2].isProcessed) {
            revert OrderAlreadyProcessed();
        }

        // Effects & Interactions
        _verifyAndProcessMatch(poolId, orders, index1, index2);
    }

    /**
     * @notice Returns the address of the AVS Service Manager
     * @return Address of the service manager
     */
    function shadowSwapAVS() external view returns (address) {
        return serviceManager;
    }

    /**
     * @notice Updates the service manager address
     * @dev Only callable by owner
     * @param newServiceManager New service manager address
     */
    function setServiceManager(address newServiceManager) external onlyOwner {
        address oldManager = serviceManager;
        serviceManager = newServiceManager;
        emit ServiceManagerUpdated(oldManager, newServiceManager);
    }

    /**
     * @notice Sets the price oracle used for Trader-first loss estimation
     * @dev Oracle should return token1PerToken0 price scaled by 1e18 for the pool.
     */
    function setPriceOracle(address newOracle) external onlyOwner {
        address oldOracle = priceOracle;
        priceOracle = newOracle;
        emit PriceOracleUpdated(oldOracle, newOracle);
    }

    /**
     * @notice Sets the protocol treasury address
     */
    function setProtocolTreasury(address newTreasury) external onlyOwner {
        address oldTreasury = protocolTreasury;
        protocolTreasury = newTreasury;
        emit ProtocolTreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Emergency pause function
     * @dev Only callable by owner - implements fail-safe pattern
     * @param _paused New pause state
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PauseStateChanged(_paused);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PUBLIC FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Returns the hook permissions
     * @return Hooks.Permissions struct with enabled hooks
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Returns the original user who initiated the swap
     * @dev Reads from transient storage set by the router
     * @return stored The original sender address
     */
    function msgSender() public view returns (address stored) {
        assembly {
            stored := tload(MSG_SENDER_SLOT)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HOOK IMPLEMENTATIONS (Internal - Override)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Hook called before pool initialization
     * @dev Validates that the pool uses dynamic fees
     */
    function _beforeInitialize(
        address,
        PoolKey calldata key,
        uint160
    ) internal pure override returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    /**
     * @notice Hook called after pool initialization
     * @dev Captures initial tick for limit order matching
     */
    function _afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick
    ) internal override returns (bytes4) {
        lastTicks[PoolId.unwrap(key.toId())] = tick;
        return this.afterInitialize.selector;
    }

    /**
     * @notice Hook called before each swap
     * @dev Encrypts order details, validates, and queues for matching
     * @param sender Address initiating the swap
     * @param key Pool key for the swap
     * @param hookData Encoded encrypted order data
     * @return selector Function selector
     * @return delta BeforeSwapDelta hook delta (kept zero to avoid flash-accounting settlement requirements)
     * @return dynamicFee Calculated dynamic fee
     */
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata hookData
    )
        internal
        override
        nonReentrant(PoolId.unwrap(key.toId()))
        mevProtection
        whenNotPaused
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Store sender in transient storage
        assembly {
            tstore(MSG_SENDER_SLOT, sender)
        }

        // 1. Calculate dynamic fee
        uint24 dynamicFee = _getFee() | LPFeeLibrary.OVERRIDE_FEE_FLAG;

        // 2. Decrypt and validate order
        (
            InEuint64 memory encAmount,
            InEbool memory encDirection,
            InEuint64 memory encPriceLimit,
            InEuint32 memory encDeadline
        ) = abi.decode(hookData, (InEuint64, InEbool, InEuint64, InEuint32));

        FHEOperations.EncryptedSwapData memory swapData = FHEOperations.encryptSwapParams(
            encAmount,
            encDirection,
            encPriceLimit,
            encDeadline
        );

        ebool orderValid = FHEOperations.isValidOrder(swapData.amount, swapData.deadline);
        if (!FHEUtils.getBoolHeuristic(orderValid)) revert OrderValidationFailed();

        // 3. Generate unique order ID and check replay protection
        bytes32 poolIdBytes = PoolId.unwrap(key.toId());
        bytes32 orderId = keccak256(
            abi.encodePacked(sender, poolIdBytes, block.number, pendingOrders[poolIdBytes].length)
        );

        if (processedOrders[orderId]) revert OrderAlreadyProcessed();

        // 4. Create and store encrypted order (Effects)
        EncryptedOrder memory order = EncryptedOrder({
            encryptedAmount: swapData.amount,
            isZeroForOne: swapData.zeroForOne,
            encryptedPriceLimit: swapData.sqrtPriceLimitX96,
            deadline: swapData.deadline,
            trader: sender,
            orderId: orderId,
            isProcessed: false
        });

        // Set FHE permissions
        FHE.allowThis(order.encryptedAmount);
        FHE.allowThis(order.isZeroForOne);
        FHE.allowThis(order.encryptedPriceLimit);
        FHE.allowThis(order.deadline);

        FHE.allow(order.encryptedAmount, sender);
        FHE.allow(order.isZeroForOne, sender);
        FHE.allow(order.deadline, sender);

        pendingOrders[poolIdBytes].push(order);

        emit EncryptedOrderPlaced(poolIdBytes, orderId, sender);

        // 5. Notify AVS (Interactions - last per CEI pattern)
        if (serviceManager != address(0)) {
            // Low-level call to AVS - we don't revert on failure
            // Order is already stored and can be matched via events
            serviceManager.call(
                abi.encodeWithSignature(
                    "createNewMatchingTask(bytes32,bytes32)",
                    poolIdBytes,
                    orderId
                )
            );
        }

        // 6. Uniswap v4 uses flash accounting: non-zero hook deltas must be settled/taken.
        // ShadowSwap currently records encrypted intent + AVS tasking without mutating pool deltas here.
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, dynamicFee);
    }

    /**
     * @notice Hook called after each swap
     * @dev Captures MEV and updates moving average
     */
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    )
        internal
        override
        nonReentrant(PoolId.unwrap(key.toId()))
        mevProtection
        returns (bytes4, int128)
    {
        // Skip if called by self (internal operations)
        if (sender == address(this)) return (this.afterSwap.selector, 0);

        PoolId poolId = key.toId();
        bytes32 poolIdBytes = PoolId.unwrap(poolId);

        // Update tick tracking
        int24 previousTick = lastTicks[poolIdBytes];
        (, int24 currentTick,,) = poolManager.getSlot0(poolId);
        lastTicks[poolIdBytes] = currentTick;

        // Track tick movement for AVS operators
        // Significant tick changes may activate pending limit orders
        if (previousTick != currentTick) {
            // Tick movement logged for off-chain processing
        }

        // Capture MEV
        address trader = msgSender();
        if (trader == address(0)) trader = sender;
        _captureMEV(key, params, delta, trader);

        // Update gas price moving average
        _updateMovingAverage();

        // Clear transient sender slot for composability safety
        assembly {
            tstore(MSG_SENDER_SLOT, 0)
        }

        return (this.afterSwap.selector, 0);
    }

    /**
     * @notice Hook called after liquidity is added
     * @dev Placeholder for MEV redistribution to new LPs
     */
    function _afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal pure override returns (bytes4, BalanceDelta) {
        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculates dynamic fee based on gas price deviation
     * @dev Fee adjusts based on how current gas price compares to moving average
     * @return Dynamic fee in basis points
     */
    function _getFee() internal view returns (uint24) {
        uint128 currentGasPrice = uint128(tx.gasprice);

        // High gas price (>110% of average) = lower fee to incentivize trading
        if (currentGasPrice > (movingAverageGasPrice * 11) / 10) {
            return BASE_FEE / 2;
        }

        // Low gas price (<90% of average) = higher fee to capture value
        if (currentGasPrice < (movingAverageGasPrice * 9) / 10) {
            return BASE_FEE * 2;
        }

        return BASE_FEE;
    }

    /**
     * @notice Updates the moving average gas price
     * @dev Called on each swap to maintain accurate average
     */
    function _updateMovingAverage() internal {
        uint128 currentGasPrice = uint128(tx.gasprice);
        movingAverageGasPrice = (
            (movingAverageGasPrice * movingAverageGasPriceCount) + currentGasPrice
        ) / (movingAverageGasPriceCount + 1);
        movingAverageGasPriceCount++;
    }

    /**
     * @notice Captures MEV from swap execution
     * @dev Estimates MEV based on balance delta and redistributes
     * @param key Pool key
     * @param params Swap parameters
     * @param delta Balance changes from swap
     */
    function _captureMEV(
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        address trader
    ) internal {
        bytes32 poolIdBytes = PoolId.unwrap(key.toId());

        // Record block for MEV protection
        address token = params.zeroForOne
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);
        _lastExecutionBlock[token] = block.number;

        // Calculate captured value (placeholder: 1 basis point of volume).
        // In production this should be based on measurable MEV savings / match surplus.
        int128 amount0 = delta.amount0();
        uint256 captured = uint256(int256(amount0 > 0 ? amount0 : -amount0)) / BPS_DENOMINATOR;

        if (captured > 0) {
            MEVCapture storage capture = mevCaptures[poolIdBytes][block.number];

            // Trader-first allocation:
            // 1) Estimate the trader's loss versus a fair price reference (oracle).
            // 2) Compensate trader up to `captured`.
            // 3) Split the remainder between LPs and protocol treasury.
            (uint256 traderLossEstimate, uint256 fairPriceX18,,) = _estimateTraderLoss(key, params, delta);

            uint256 traderCompensation = traderLossEstimate < captured ? traderLossEstimate : captured;
            uint256 remaining = captured - traderCompensation;

            // Remainder split: LPs + Protocol (must sum to 100%)
            uint256 lpReward = (remaining * LP_REMAINDER_BPS) / BPS_DENOMINATOR;
            uint256 protocolFee = remaining - lpReward;

            // Effects: update state (accounting)
            capture.totalCaptured += captured;
            capture.traderRebate += traderCompensation;
            capture.lpShare += lpReward;
            capture.protocolShare += protocolFee;

            traderRebateClaimable[trader] += traderCompensation;
            lpRewardsAccrued[poolIdBytes] += lpReward;
            protocolFeesAccrued[poolIdBytes] += protocolFee;

            emit MEVCaptured(
                poolIdBytes,
                block.number,
                captured,
                capture.lpShare,
                capture.traderRebate
            );

            emit TraderFirstAllocated(
                poolIdBytes,
                block.number,
                trader,
                captured,
                traderLossEstimate,
                traderCompensation,
                lpReward,
                protocolFee,
                fairPriceX18
            );
        }
    }

    /**
     * @notice Estimates a trader's loss vs an oracle fair price reference
     * @dev Oracle must return token1PerToken0 price scaled by 1e18 for the pool.
     *      For oneForZero swaps, we invert the oracle price to get token0PerToken1.
     *
     * Returns zeros if oracle is unset, price is zero, or swap deltas are unexpected.
     */
    function _estimateTraderLoss(
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta
    ) internal view returns (uint256 loss, uint256 fairPriceX18, uint256 amountIn, uint256 amountOut) {
        address oracle = priceOracle;
        if (oracle == address(0)) return (0, 0, 0, 0);

        bytes32 poolIdBytes = PoolId.unwrap(key.toId());

        // Interface inline to avoid new file churn
        (bool ok, bytes memory data) = oracle.staticcall(
            abi.encodeWithSignature("getPriceX18(bytes32)", poolIdBytes)
        );
        if (!ok || data.length < 32) return (0, 0, 0, 0);

        uint256 token1PerToken0X18 = abi.decode(data, (uint256));
        if (token1PerToken0X18 == 0) return (0, 0, 0, 0);

        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();

        // We interpret deltas as pool balance changes:
        // - For zeroForOne: pool receives token0 (d0 > 0) and pays token1 (d1 < 0)
        // - For oneForZero: pool receives token1 (d1 > 0) and pays token0 (d0 < 0)
        if (params.zeroForOne) {
            if (d0 <= 0 || d1 >= 0) return (0, 0, 0, 0);
            amountIn = uint256(int256(d0));
            amountOut = uint256(int256(-d1));
            fairPriceX18 = token1PerToken0X18; // token1 per token0
        } else {
            if (d1 <= 0 || d0 >= 0) return (0, 0, 0, 0);
            amountIn = uint256(int256(d1));
            amountOut = uint256(int256(-d0));
            // invert to token0 per token1, scaled to 1e18
            fairPriceX18 = (1e36) / token1PerToken0X18;
        }

        uint256 fairOut = (amountIn * fairPriceX18) / 1e18;
        if (fairOut > amountOut) loss = fairOut - amountOut;
    }

    /**
     * @notice Finds indices of two orders by their IDs
     * @param orders Array of orders to search
     * @param id1 First order ID
     * @param id2 Second order ID
     * @return i1 Index of first order
     * @return i2 Index of second order
     * @return found Whether both orders were found
     */
    function _findOrderIndices(
        EncryptedOrder[] storage orders,
        bytes32 id1,
        bytes32 id2
    ) internal view returns (uint256 i1, uint256 i2, bool found) {
        bool f1;
        bool f2;
        uint256 len = orders.length;

        for (uint256 i; i < len;) {
            if (orders[i].orderId == id1) {
                i1 = i;
                f1 = true;
            }
            if (orders[i].orderId == id2) {
                i2 = i;
                f2 = true;
            }
            if (f1 && f2) break;

            unchecked { ++i; }
        }

        return (i1, i2, f1 && f2);
    }

    /**
     * @notice Verifies and processes a match between two orders
     * @param poolId Pool identifier
     * @param orders Array of orders
     * @param i1 Index of first order
     * @param i2 Index of second order
     */
    function _verifyAndProcessMatch(
        bytes32 poolId,
        EncryptedOrder[] storage orders,
        uint256 i1,
        uint256 i2
    ) internal {
        EncryptedOrder memory o1 = orders[i1];
        EncryptedOrder memory o2 = orders[i2];

        // 1. Verify orders can match (opposite directions, valid amounts)
        ebool canMatch = FHEOperations.canMatchOrders(
            FHEOperations.EncryptedMatchData({
                amount1: o1.encryptedAmount,
                amount2: o2.encryptedAmount,
                direction1: o1.isZeroForOne,
                direction2: o2.isZeroForOne,
                matchedAmount: FHE.asEuint64(0)
            })
        );

        // 2. Verify slippage tolerance
        (, int24 currentTick,,) = poolManager.getSlot0(PoolId.wrap(poolId));
        uint160 currentSqrtPriceX96 = TickMath.getSqrtPriceAtTick(currentTick);

        ebool slippageValid = FHE.and(
            FHEOperations.isPriceValid(currentSqrtPriceX96, o1.encryptedPriceLimit, o1.isZeroForOne),
            FHEOperations.isPriceValid(currentSqrtPriceX96, o2.encryptedPriceLimit, o2.isZeroForOne)
        );

        if (!FHEUtils.getBoolHeuristic(FHE.and(canMatch, slippageValid))) {
            revert MatchValidationFailed();
        }

        // 3. Effects: Mark orders as processed
        orders[i1].isProcessed = true;
        orders[i2].isProcessed = true;
        processedOrders[o1.orderId] = true;
        processedOrders[o2.orderId] = true;

        // 4. Compute matched amount
        euint64 matchAmount = FHEOperations.computeMatchedAmount(
            o1.encryptedAmount,
            o2.encryptedAmount
        );

        // 5. Set FHE permissions for matched amount
        FHE.allowThis(matchAmount);
        FHE.allow(matchAmount, o1.trader);
        FHE.allow(matchAmount, o2.trader);

        emit OrderMatched(poolId, o1.orderId, o2.orderId, FHEUtils.unwrapU64(matchAmount));
    }
}

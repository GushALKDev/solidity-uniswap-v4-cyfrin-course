// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {CurrencyLib} from "../libraries/CurrencyLib.sol";
import {StateLibrary} from "../libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "../types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {TStore} from "../TStore.sol";

contract LimitOrder is TStore {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for int128;
    using SafeCast for uint128;
    using CurrencyLib for address;

    error NotPoolManager();
    error WrongTickSpacing();
    error NotAllowedAtCurrentTick();
    error BucketFilled();
    error BucketNotFilled();

    uint256 constant ADD_LIQUIDITY = 1;
    uint256 constant REMOVE_LIQUIDITY = 2;

    event Place(
        bytes32 indexed poolId,
        uint256 indexed slot,
        address indexed user,
        int24 tickLower,
        bool zeroForOne,
        uint128 liquidity
    );
    event Cancel(
        bytes32 indexed poolId,
        uint256 indexed slot,
        address indexed user,
        int24 tickLower,
        bool zeroForOne,
        uint128 liquidity
    );
    event Take(
        bytes32 indexed poolId,
        uint256 indexed slot,
        address indexed user,
        int24 tickLower,
        bool zeroForOne,
        uint256 amount0,
        uint256 amount1
    );
    event Fill(
        bytes32 indexed poolId,
        uint256 indexed slot,
        int24 tickLower,
        bool zeroForOne,
        uint256 amount0,
        uint256 amount1
    );

    // Bucket of limit orders
    struct Bucket {
        bool filled;
        uint256 amount0;
        uint256 amount1;
        // Total liquidity
        uint128 liquidity;
        // Liquidity provided per user
        mapping(address => uint128) sizes;
    }

    IPoolManager public immutable poolManager;

    // Bucket id => current slot to place limit orders
    mapping(bytes32 => uint256) public slots;
    // Bucket id => slot => Bucket
    mapping(bytes32 => mapping(uint256 => Bucket)) public buckets;
    // Pool id => last tick
    mapping(PoolId => int24) public ticks;

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
        Hooks.validateHookPermissions(address(this), getHookPermissions());
    }

    receive() external payable {}

    function getHookPermissions()
        public
        pure
        returns (Hooks.Permissions memory)
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick
    ) external onlyPoolManager returns (bytes4) {
        // Write your code here
        ticks[key.toId()] = tick;
        return this.afterInitialize.selector;
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    )
        external
        onlyPoolManager
        setAction(REMOVE_LIQUIDITY)
        returns (bytes4, int128)
    {
        // Write your code here

        (int24 tickLower, int24 tickUpper) = _getTickRange(
            // Previous tick
            ticks[key.toId()],
            // Current tick
            _getTick(key.toId()),
            // Tick spacing
            key.tickSpacing
        );

        PoolId poolId = key.toId();
        for (int24 tick = tickLower; tick <= tickUpper; tick += key.tickSpacing) {
            //! Orders filled are in opposite direction of the swap
            bool zeroForOne = !params.zeroForOne;

            // Find bucket
            bytes32 bucketId = getBucketId(poolId, tick, zeroForOne);
            uint256 slot = slots[bucketId];
            Bucket storage bucket = buckets[bucketId][slot];

            if (bucket.liquidity == 0) continue;

            // Increment slot for next orders at this tick
            slots[bucketId] = slot + 1;

            // Fill the limit order
            (int256 d,) = poolManager.modifyLiquidity({
                    key:key,
                    params: ModifyLiquidityParams({
                        tickLower: tick,
                        tickUpper: tick + key.tickSpacing,
                        liquidityDelta: -int128(bucket.liquidity),
                        salt: bytes32(0)
                    }),
                    hookData:""
                });

                // Get balance delta
                BalanceDelta fillDelta = BalanceDelta.wrap(d);
                uint256 amount0 = uint128(fillDelta.amount0());
                uint256 amount1 = uint128(fillDelta.amount1());

                // Take the tokens from poolManager
                if (amount0 > 0) {
                    poolManager.take(key.currency0, address(this), amount0);
                }
                if (amount1 > 0) {
                    poolManager.take(key.currency1, address(this), amount1);
                }

                // Update bucket
                bucket.filled = true;
                bucket.amount0 += amount0;
                bucket.amount1 += amount1;

                emit Fill(
                    PoolId.unwrap(poolId),
                    slot,
                    tick,
                    zeroForOne,
                    bucket.amount0,
                    bucket.amount1
                );
        }

        // Update to current tick after swap
        ticks[poolId] = _getTick(poolId);

        return (this.afterSwap.selector, 0);
    }

    function unlockCallback(bytes calldata data)
        external
        onlyPoolManager
        returns (bytes memory)
    {
        uint256 action = _getAction();

        if (action == ADD_LIQUIDITY) {
            // Write your code here
            (   address sender,
                uint256 ethValue,
                PoolKey memory key,
                int24 tickLower,
                bool zeroForOne,
                uint128 liquidity
            ) = abi.decode(data, (address, uint256, PoolKey, int24, bool, uint128));
            
            if (tickLower == ticks[key.toId()]) revert NotAllowedAtCurrentTick();

            // Add liquidity limit order
            (int256 d,) = poolManager.modifyLiquidity({
                key: key,
                params: ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickLower + key.tickSpacing,
                    liquidityDelta: int256(uint256(liquidity)),
                    salt: bytes32(0)
                }),
                hookData: ""
            });

            // Handle payments
            // Get balance delta
            BalanceDelta delta = BalanceDelta.wrap(d);
            // Get amounts
            int128 amount0 = delta.amount0();
            int128 amount1 = delta.amount1();

            // Handle the amounts and currencies as needed
            address currency;
            uint256 amountToPay;
            if (zeroForOne) {
                require(amount0 < 0 && amount1 == 0, "Tick crossed");
                currency = key.currency0;
                amountToPay = (-amount0).toUint256();
            } else {
                require(amount0 == 0 && amount1 < 0, "Tick crossed");
                currency = key.currency1;
                amountToPay = (-amount1).toUint256();
            }

            // Sync and settle payments
            poolManager.sync(currency);

            // Pay the required amount
            if (currency == address(0)) {
                require(ethValue>= amountToPay, "Insufficient ETH sent");
                poolManager.settle{value: amountToPay}();
                if (ethValue > amountToPay) {
                    // Refund excess ETH
                    _sendEth(sender, ethValue - amountToPay);
                }
            } else {
                require(ethValue == 0, "ETH sent for ERC20");
                IERC20(currency).transferFrom(sender, address(poolManager), amountToPay);
                poolManager.settle();
            }

            return "";
        } else if (action == REMOVE_LIQUIDITY) {
            // Write your code here
            (
                PoolKey memory key,
                int24 tickLower,
                uint128 size
            ) = abi.decode(data, (PoolKey, int24, uint128));

            // Remove liquidity limit order
            (int256 d, int256 f) = poolManager.modifyLiquidity({
                key: key,
                params: ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickLower + key.tickSpacing,
                    liquidityDelta: -int256(uint256(size)),
                    salt: bytes32(0)
                }),
                hookData:""
            });

            // Delta includes fees
            uint256 amount0;
            uint256 amount1;
            uint256 fee0;
            uint256 fee1;

            // Get balance delta
            BalanceDelta delta = BalanceDelta.wrap(d);
            if (delta.amount0() > 0) {
                amount0 = uint256(uint128(delta.amount0()));
                poolManager.take(key.currency0, address(this), amount0);
            }
            if (delta.amount1() > 0) {
                amount1 = uint256(uint128(delta.amount1()));
                poolManager.take(key.currency1, address(this), amount1);
            }

            // Get fees accrued
            BalanceDelta feesAccrued = BalanceDelta.wrap(f);
            if (feesAccrued.amount0() > 0) {
                fee0 = uint256(uint128(feesAccrued.amount0()));
            }
            if (feesAccrued.amount1() > 0) {
                fee1 = uint256(uint128(feesAccrued.amount1()));
            }

            return abi.encode(amount0, amount1, fee0, fee1);
        }

        revert("Invalid action");
    }

    function place(
        PoolKey calldata key,
        int24 tickLower,
        bool zeroForOne,
        uint128 liquidity
    ) external payable setAction(ADD_LIQUIDITY) {
        // Write your code here
        bytes memory data = abi.encode(msg.sender, msg.value, key, tickLower, zeroForOne, liquidity);
        if (tickLower % key.tickSpacing != 0) revert WrongTickSpacing();
        poolManager.unlock(data);

        // Find bucket
        PoolId poolId = key.toId();
        bytes32 bucketId = getBucketId(poolId, tickLower, zeroForOne);
        uint256 slot = slots[bucketId];
        Bucket storage bucket = buckets[bucketId][slot];

        // Update bucket
        bucket.liquidity += liquidity;
        bucket.sizes[msg.sender] += liquidity;
        emit Place(
            PoolId.unwrap(poolId),
            slot,
            msg.sender,
            tickLower,
            zeroForOne,
            liquidity
        );
    }

    function cancel(PoolKey calldata key, int24 tickLower, bool zeroForOne)
        external
        setAction(REMOVE_LIQUIDITY)
    {
        // Write your code here
        // Find bucket
        PoolId poolId = key.toId();
        bytes32 bucketId = getBucketId(poolId, tickLower, zeroForOne);
        uint256 slot = slots[bucketId];
        Bucket storage bucket = buckets[bucketId][slot];

        // Revert if bucket is already filled
        if (bucket.filled) revert BucketFilled();

        // Remove user's liquidity
        uint128 userLiquidity = bucket.sizes[msg.sender];
        require(userLiquidity > 0, "limit order size = 0");
        bucket.liquidity -= userLiquidity;
        bucket.sizes[msg.sender] = 0;

        // Call unlock callback to remove liquidity from pool
        bytes memory res = poolManager.unlock(abi.encode(key, tickLower, userLiquidity));

        // Decode returned amounts
        (uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1) = abi.decode(res, (uint256, uint256, uint256, uint256));

        // Last user to cancel receives all fees
        if (bucket.liquidity > 0) {
            // Update bucket amounts with fees
            bucket.amount0 += fee0;
            bucket.amount1 += fee1;
            //! AMOUNT0 AND AMOUNT1 INCLUDE FEES
            // Send amounts minus fees to the user
            if (amount0 > fee0) {
                key.currency0.transferOut(msg.sender, amount0 - fee0);
            }
            if (amount1 > fee1) {
                key.currency1.transferOut(msg.sender, amount1 - fee1);
            }
        }
        // If the bucket liquidity is empty, send amounts + fees to the user
        else {
            amount0 += bucket.amount0;
            bucket.amount0 = 0;
            if (amount0 > 0) key.currency0.transferOut(msg.sender, amount0);
            amount1 += bucket.amount1;
            bucket.amount1 = 0;
            if (amount1 > 0) key.currency1.transferOut(msg.sender, amount1);
        }

        // Emit event
        emit Cancel(
            PoolId.unwrap(poolId),
            slot,
            msg.sender,
            tickLower,
            zeroForOne,
            userLiquidity
        );
    }

    function take(
        PoolKey calldata key,
        int24 tickLower,
        bool zeroForOne,
        uint256 slot
    ) external {
        // Write your code here
        // Find bucket
        PoolId poolId = key.toId();
        bytes32 bucketId = getBucketId(poolId, tickLower, zeroForOne);
        Bucket storage bucket = buckets[bucketId][slot];

        // Revert if bucket is not filled
        if (!bucket.filled) revert BucketNotFilled();

        uint256 liquidity = uint256(bucket.liquidity);
        uint256 size = uint256(bucket.sizes[msg.sender]);
        require(size > 0, "size = 0");
        bucket.sizes[msg.sender] = 0;

        // Calculate proportional amounts based on user's share
        // Note: recommended to use mulDiv here for precision
        uint256 amount0 = bucket.amount0 * size / liquidity;
        uint256 amount1 = bucket.amount1 * size / liquidity;

        // Send amounts to the user
        if (amount0 > 0) {
            key.currency0.transferOut(msg.sender, amount0);
        }
        if (amount1 > 0) {
            key.currency1.transferOut(msg.sender, amount1);
        }

        // Emit event
        emit Take(
            PoolId.unwrap(poolId),
            slot,
            msg.sender,
            tickLower,
            zeroForOne,
            amount0,
            amount1
        );
    }

    function getBucketId(PoolId poolId, int24 tick, bool zeroForOne)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(PoolId.unwrap(poolId), tick, zeroForOne));
    }

    function getBucket(bytes32 id, uint256 slot)
        public
        view
        returns (
            bool filled,
            uint256 amount0,
            uint256 amount1,
            uint128 liquidity
        )
    {
        Bucket storage bucket = buckets[id][slot];
        return (bucket.filled, bucket.amount0, bucket.amount1, bucket.liquidity);
    }

    function getOrderSize(bytes32 id, uint256 slot, address user)
        public
        view
        returns (uint128)
    {
        return buckets[id][slot].sizes[user];
    }

    function _getTick(PoolId poolId) private view returns (int24 tick) {
        (, tick,,) = StateLibrary.getSlot0(address(poolManager), poolId);
    }

    function _getTickLower(int24 tick, int24 tickSpacing)
        private
        pure
        returns (int24)
    {
        int24 compressed = tick / tickSpacing;
        // Round towards negative infinity
        if (tick < 0 && tick % tickSpacing != 0) compressed--;
        return compressed * tickSpacing;
    }

    function _getTickRange(int24 tick0, int24 tick1, int24 tickSpacing)
        private
        pure
        returns (int24 lower, int24 upper)
    {
        // Last lower tick
        int24 l0 = _getTickLower(tick0, tickSpacing);
        // Current lower tick
        int24 l1 = _getTickLower(tick1, tickSpacing);

        if (tick0 <= tick1) {
            lower = l0;
            upper = l1 - tickSpacing;
        } else {
            lower = l1 + tickSpacing;
            upper = l0;
        }
    }

    function _sendEth(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "Send ETH failed");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";

import {IERC20} from "../interfaces/IERC20.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/IUnlockCallback.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {SwapParams} from "../types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {CurrencyLib} from "../libraries/CurrencyLib.sol";
import {MIN_SQRT_PRICE, MAX_SQRT_PRICE} from "../Constants.sol";
import {TStore} from "../TStore.sol";

contract Router is TStore, IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for int128;
    using SafeCast for uint128;
    using CurrencyLib for address;

    // Actions
    uint256 private constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint256 private constant SWAP_EXACT_IN = 0x07;
    uint256 private constant SWAP_EXACT_OUT_SINGLE = 0x08;
    uint256 private constant SWAP_EXACT_OUT = 0x09;

    IPoolManager public immutable poolManager;

    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMin;
        bytes hookData;
    }

    struct ExactOutputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountOut;
        uint128 amountInMax;
        bytes hookData;
    }

    struct PathKey {
        address currency;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        bytes hookData;
    }

    struct ExactInputParams {
        address currencyIn;
        // First element + currencyIn determines the first pool to swap
        // Last element + previous path element's currency determines the last pool to swap
        PathKey[] path;
        uint128 amountIn;
        uint128 amountOutMin;
    }

    struct ExactOutputParams {
        address currencyOut;
        // Last element + currencyOut determines the last pool to swap
        // First element + second path element's currency determines the first pool to swap
        PathKey[] path;
        uint128 amountOut;
        uint128 amountInMax;
    }

    error UnsupportedAction(uint256 action);

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "not pool manager");
        _;
    }

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    receive() external payable {}

    function unlockCallback(bytes calldata data)
        external
        onlyPoolManager
        returns (bytes memory)
    {
        uint256 action = _getAction();
        // Write your code here
        // Ensure the caller is the PoolManager
        require(msg.sender == address(poolManager), "Caller is not PoolManager");

        // Handle different actions based on the action type
        if (action == SWAP_EXACT_IN_SINGLE) {
            (address caller, ExactInputSingleParams memory params) = abi.decode(data, (address, ExactInputSingleParams));
        
            // Execute the swap
            (int128 amount0, int128 amount1) = _swap({
                    zeroForOne: params.zeroForOne,
                    poolKey: params.poolKey,
                    amountSpecified: -(params.amountIn.toInt256()),
                    hookData: params.hookData
                });

            // Currency determination
            (address currencyIn, address currencyOut, uint256 amountIn, uint256 amountOut) = params.zeroForOne
                ? (params.poolKey.currency0, params.poolKey.currency1, (-amount0).toUint256(), amount1.toUint256())
                : (params.poolKey.currency1, params.poolKey.currency0, (-amount1).toUint256(), amount0.toUint256());

            // Ensure the output amount meets the minimum requirement
            require(amountOut >= params.amountOutMin, "insufficient output amount");

            _takeAndSettle({
                caller: caller,
                currencyIn: currencyIn,
                amountIn: amountIn,
                currencyOut: currencyOut,
                amountOut: amountOut
            });

            return abi.encode(amountOut);

        } else if (action == SWAP_EXACT_OUT_SINGLE) {
            // Handle SWAP_EXACT_OUT_SINGLE action
            (address caller, ExactOutputSingleParams memory params) = abi.decode(data, (address, ExactOutputSingleParams));

            // Execute the swap
            (int128 amount0, int128 amount1) = _swap({
                    zeroForOne: params.zeroForOne,
                    poolKey: params.poolKey,
                    amountSpecified: (params.amountOut.toInt256()),
                    hookData: params.hookData
                });

            // Currency determination
            (address currencyIn, address currencyOut, uint256 amountIn, uint256 amountOut) = params.zeroForOne
                ? (params.poolKey.currency0, params.poolKey.currency1, (-amount0).toUint256(), amount1.toUint256())
                : (params.poolKey.currency1, params.poolKey.currency0, (-amount1).toUint256(), amount0.toUint256());
                
            // Ensure the output amount meets the minimum requirement
            require(amountIn < params.amountInMax, "too much input amount");

            _takeAndSettle({
                caller: caller,
                currencyIn: currencyIn,
                amountIn: amountIn,
                currencyOut: currencyOut,
                amountOut: amountOut
            });

            return abi.encode(amountIn);

        } else if (action == SWAP_EXACT_IN) {
            // Handle SWAP_EXACT_IN action
            (address caller, ExactInputParams memory params) = abi.decode(data, (address, ExactInputParams));

            // Execute the multi-hop swap
            // Get the length of the path
            uint256 pathLength = params.path.length;

            // Initialize variables for the swap loop
            address currencyIn = params.currencyIn;
            int256 amountIn = params.amountIn.toInt256();

            // Loop through each hop in the path
            for (uint256 i = 0; i < pathLength; i++) {

                // Determine the pool key for the current hop
                PathKey memory path = params.path[i];

                (address currency0, address currency1) = currencyIn < path.currency ?
                    (currencyIn, path.currency) :
                    (path.currency, currencyIn);

                bool zeroForOne = currency0 == currencyIn;

                PoolKey memory poolKey = PoolKey({
                        currency0: currency0,
                        currency1: currency1,
                        fee: path.fee,
                        tickSpacing: path.tickSpacing,
                        hooks: path.hooks
                    });

                // Execute the swap
                (int128 amount0, int128 amount1) = _swap({
                    zeroForOne: zeroForOne,
                    poolKey: poolKey,
                    amountSpecified: -amountIn,
                    hookData: path.hookData
                });
                
                // Set the amountIn of the next hop with the amountOut of the current hop
                currencyIn = path.currency;
                amountIn = (zeroForOne ? amount1 : amount0).toInt256();
            }

            // Ensure the output amount meets the minimum requirement
            require(uint256(amountIn) >= uint256(params.amountOutMin), "insufficient output amount");

            // Take and settle
            _takeAndSettle({
                caller: caller,
                currencyIn: params.currencyIn,
                amountIn: params.amountIn,
                currencyOut: currencyIn,
                amountOut: uint256(amountIn)
            });

            return abi.encode(uint256(amountIn));

        } else if (action == SWAP_EXACT_OUT) {
            // Handle SWAP_EXACT_OUT action
            (address caller, ExactOutputParams memory params) = abi.decode(data, (address, ExactOutputParams));

            // Execute the multi-hop swap
            // Get the length of the path
            uint256 pathLength = params.path.length;

            // Initialize variables for the swap loop
            address currencyOut = params.currencyOut;
            int256 amountOut = params.amountOut.toInt256();

            // Loop through each hop in the path
            for (uint256 i = pathLength; i > 0; i--) {

                // Determine the pool key for the current hop
                PathKey memory path = params.path[i-1];

                (address currency0, address currency1) = path.currency < currencyOut ?
                    (path.currency, currencyOut) :
                    (currencyOut, path.currency);

                bool zeroForOne = currencyOut == currency1;

                PoolKey memory poolKey = PoolKey({
                        currency0: currency0,
                        currency1: currency1,
                        fee: path.fee,
                        tickSpacing: path.tickSpacing,
                        hooks: path.hooks
                    });

                // Execute the swap
                (int128 amount0, int128 amount1) = _swap({
                    zeroForOne: zeroForOne,
                    poolKey: poolKey,
                    amountSpecified: amountOut,
                    hookData: path.hookData
                });
                
                // Set the amountOut of the next hop with the amountIn of the current hop
                currencyOut = path.currency;
                amountOut = (zeroForOne ? -amount0 : -amount1).toInt256();
            }

            // Ensure the input amount meets the maximum requirement
            require(uint256(amountOut) <= uint256(params.amountInMax), "amount in > max");

            // Transfer input currency from caller to router if not native currency
            if (currencyOut != address(0)) currencyOut.transferIn(caller, uint256(amountOut));

            // Take and settle
            _takeAndSettle({
                caller: caller,
                currencyIn: currencyOut,
                amountIn: uint256(amountOut),
                currencyOut: params.currencyOut,
                amountOut: params.amountOut
            });

            return abi.encode(uint256(amountOut));
        }
        
        revert UnsupportedAction(action);
    }

    function swapExactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        setAction(SWAP_EXACT_IN_SINGLE)
        returns (uint256 amountOut)
    {
        // Write your code here
        // Determine the input currency based on the swap direction
        address currencyIn = params.zeroForOne ? params.poolKey.currency0 : params.poolKey.currency1;

        // Transfer the input amount from the sender to the router (if not native currency)
        if (currencyIn != address(0)) {
            currencyIn.transferIn(msg.sender, params.amountIn);
        }

        // Trigger the swap via unlock callback
        bytes memory res = poolManager.unlock(abi.encode(msg.sender, params));
        amountOut = abi.decode(res, (uint256));

        // After the swap, transfer any remaining input currency back to the sender
        if (currencyIn.balanceOf(address(this)) > 0) {
            currencyIn.transferOut(msg.sender, currencyIn.balanceOf(address(this)));
        }
    }

    function swapExactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        setAction(SWAP_EXACT_OUT_SINGLE)
        returns (uint256 amountIn)
    {
        // Write your code here
        // Determine the input currency based on the swap direction
        address currencyIn = params.zeroForOne ? params.poolKey.currency0 : params.poolKey.currency1;

        // Transfer the max input amount from the sender to the router first
        currencyIn.transferIn(msg.sender, params.amountInMax);
        
        // Trigger the swap via unlock callback and decode the actual amount used
        bytes memory res = poolManager.unlock(abi.encode(msg.sender, params));
        amountIn = abi.decode(res, (uint256));

        // Refund any remaining input currency back to the sender
        uint256 refunded = currencyIn.balanceOf(address(this));
        if (refunded > 0) {
            currencyIn.transferOut(msg.sender, refunded);
        }
    }

    function swapExactInput(ExactInputParams calldata params)
        external
        payable
        setAction(SWAP_EXACT_IN)
        returns (uint256 amountOut)
    {
        // Write your code here
        // Determine the input currency based on the swap direction
        address currencyIn = params.currencyIn;

        // Transfer the input amount from the sender to the router (if not native currency)
        if (currencyIn != address(0)) {
            currencyIn.transferIn(msg.sender, params.amountIn);
        }

        // Trigger the swap via unlock callback
        bytes memory res = poolManager.unlock(abi.encode(msg.sender, params));
        amountOut = abi.decode(res, (uint256));

        // After the swap, transfer any remaining input currency back to the sender
        if (currencyIn.balanceOf(address(this)) > 0) {
            currencyIn.transferOut(msg.sender, currencyIn.balanceOf(address(this)));
        }
    }

    function swapExactOutput(ExactOutputParams calldata params)
        external
        payable
        setAction(SWAP_EXACT_OUT)
        returns (uint256 amountIn)
    {
        // Write your code here
        // Determine the input currency based on the swap direction
        address currencyIn = params.path[0].currency;

        // Trigger the swap via unlock callback
        bytes memory res = poolManager.unlock(abi.encode(msg.sender, params));
        amountIn = abi.decode(res, (uint256));

        // After the swap, transfer any remaining input currency back to the sender
        if (currencyIn.balanceOf(address(this)) > 0) {
            currencyIn.transferOut(msg.sender, currencyIn.balanceOf(address(this)));
        }
    }

    function _swap(
        bool zeroForOne,
        PoolKey memory poolKey,
        int256 amountSpecified,
        bytes memory hookData
    ) internal returns (int128 amountIn, int128 amountOut) {
        // Calculate the swap parameters for the current hop
        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
        });
        
        // Perform the swap
        int256 d = poolManager.swap(poolKey, swapParams, hookData);

        // Extract balance delta
        BalanceDelta delta = BalanceDelta.wrap(d);

        // Update amountIn for the next hop
        return (delta.amount0(), delta.amount1());
    }

    function _takeAndSettle(
        address caller,
        uint256 amountIn,
        address currencyIn,
        address currencyOut,
        uint256 amountOut
    ) internal {

        // Transfer output currency to the caller
        poolManager.take(currencyOut, caller, amountOut);

        // Sync the input currency
        poolManager.sync(currencyIn);

        // Transfer input currency from the caller to the pool manager and settle
        if (currencyIn == address(0)) {
            poolManager.settle{value: amountIn}();
        }
        else {
            IERC20(currencyIn).transfer(address(poolManager), amountIn);
            poolManager.settle();
        }
    }
}
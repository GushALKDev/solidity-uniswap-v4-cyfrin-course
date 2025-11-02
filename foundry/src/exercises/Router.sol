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
            SwapParams memory swapParams = SwapParams({
                zeroForOne: params.zeroForOne,
                amountSpecified: -int256(uint256(params.amountIn)),
                sqrtPriceLimitX96: params.zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            });

            int256 d = poolManager.swap(params.poolKey, swapParams, params.hookData);

            // Extract balance delta
            BalanceDelta delta = BalanceDelta.wrap(d);
            int128 amount0 = delta.amount0();
            int128 amount1 = delta.amount1();

            (
                address currencyIn,
                address currencyOut,
                uint256 amountIn,
                uint256 amountOut
            ) = params.zeroForOne
                ? (
                    params.poolKey.currency0,
                    params.poolKey.currency1,
                    (-amount0).toUint256(),
                    amount1.toUint256()
                )
                : (
                    params.poolKey.currency1,
                    params.poolKey.currency0,
                    (-amount1).toUint256(),
                    amount0.toUint256()
                );

            // Ensure the output amount meets the minimum requirement
            require(amountOut >= params.amountOutMin, "insufficient output amount");

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

            return abi.encode(amountOut);

        } else if (action == SWAP_EXACT_OUT_SINGLE) {
            // Handle SWAP_EXACT_OUT_SINGLE action
            (address caller, ExactOutputSingleParams memory params) = abi.decode(data, (address, ExactOutputSingleParams));
        
            // Execute the swap
            SwapParams memory swapParams = SwapParams({
                zeroForOne: params.zeroForOne,
                amountSpecified: int256(uint256(params.amountOut)),
                sqrtPriceLimitX96: params.zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            });

            int256 d = poolManager.swap(params.poolKey, swapParams, params.hookData);

            // Extract balance delta
            BalanceDelta delta = BalanceDelta.wrap(d);
            int128 amount0 = delta.amount0();
            int128 amount1 = delta.amount1();

            (
                address currencyIn,
                address currencyOut,
                uint256 amountIn,
                uint256 amountOut
            ) = params.zeroForOne
                ? (
                    params.poolKey.currency0,
                    params.poolKey.currency1,
                    (-amount0).toUint256(),
                    amount1.toUint256()
                )
                : (
                    params.poolKey.currency1,   
                    params.poolKey.currency0,
                    (-amount1).toUint256(),
                    amount0.toUint256()
                );

            // Ensure the output amount meets the minimum requirement
            require(amountIn < params.amountInMax, "too much input amount");

            // Transfer output currency to the caller
            poolManager.take(currencyOut, caller, amountOut);

            // Transfer input currency from the caller to the Router (if not native currency)
            if (currencyIn != address(0)) {
                currencyIn.transferIn(caller, amountIn);
            }

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

            return abi.encode(amountIn);

        } else if (action == SWAP_EXACT_IN) {
            // Handle SWAP_EXACT_IN action
        } else if (action == SWAP_EXACT_OUT) {
            // Handle SWAP_EXACT_OUT action
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

        // Trigger the swap via unlock callback
        bytes memory res = poolManager.unlock(abi.encode(msg.sender, params));
        amountIn = abi.decode(res, (uint256));

        // After the swap, transfer any remaining input currency back to the sender
        if (currencyIn.balanceOf(address(this)) > 0) {
            currencyIn.transferOut(msg.sender, currencyIn.balanceOf(address(this)));
        }
    }

    function swapExactInput(ExactInputParams calldata params)
        external
        payable
        setAction(SWAP_EXACT_IN)
        returns (uint256 amountOut)
    {
        // Write your code here
    }

    function swapExactOutput(ExactOutputParams calldata params)
        external
        payable
        setAction(SWAP_EXACT_OUT)
        returns (uint256 amountIn)
    {
        // Write your code here
    }
}
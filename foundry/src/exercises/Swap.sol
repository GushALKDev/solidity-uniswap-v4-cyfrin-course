// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// import {console} from "forge-std/Test.sol";

import {IERC20} from "../interfaces/IERC20.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/IUnlockCallback.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {SwapParams} from "../types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {CurrencyLib} from "../libraries/CurrencyLib.sol";
import {MIN_SQRT_PRICE, MAX_SQRT_PRICE} from "../Constants.sol";

contract Swap is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for int128;
    using SafeCast for uint128;
    using CurrencyLib for address;

    IPoolManager public immutable poolManager;

    struct SwapExactInputSingleHop {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMin;
    }

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
        // Write your code here
        // Decode the data to extract msgSender and params
        (address msgSender, SwapExactInputSingleHop memory params) = abi.decode(data, (address, SwapExactInputSingleHop));

        // Execute the swap logic here
        // delta contains the change in token balances after the swap
        // int256 (256 bits total)
        // ┌─────────────────┬─────────────────┐
        // │  amount1        │    amount0      │
        // │  (128 bits)     │   (128 bits)    │
        // └─────────────────┴─────────────────┘

        int256 delta = poolManager.swap({
            key: params.poolKey,
            params: SwapParams({
                zeroForOne: params.zeroForOne,
                // amountSpecified < 0 = amount in
                // amountSpecified > 0 = amount out
                // - is used because we are doing EXACT INPUT SWAP
                amountSpecified: -(params.amountIn.toInt256()),
                // price = currency 1 / currency 0
                // 0 for 1 = price decreases → use MIN_SQRT_PRICE (lower bound)
                // 1 for 0 = price increases → use MAX_SQRT_PRICE (upper bound)
                // This allows the swap to execute at any price (no strict limit)
                // In production: calculate tighter bounds based on acceptable slippage
                sqrtPriceLimitX96: params.zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            hookData: ""
        });

        // Convert int256 to BalanceDelta type
        // BalanceDelta packs two int128 values into one int256:
        // [128 bits: amount1][128 bits: amount0]
        // Negative = tokens paid/given, Positive = tokens received
        BalanceDelta balanceDelta = BalanceDelta.wrap(delta);
        int128 amount0 = balanceDelta.amount0();
        int128 amount1 = balanceDelta.amount1();
        
        // Determine currencyIn, currencyOut, amountIn, amountOut based on swap direction
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
        require(amountOut >= params.amountOutMin, "amount out < min");

        // Transfer the output tokens to the msgSender
        poolManager.take({
            currency: currencyOut,
            to: msgSender,
            amount: amountOut
        });

        // Sync the pool manager with the input currency to prepare for settlement
        poolManager.sync(currencyIn);

        // Settle the input tokens to the pool manager
        if (currencyIn == address(0)) {
            poolManager.settle{value: amountIn}();
        } else {
            IERC20(currencyIn).transfer(address(poolManager), amountIn);
            poolManager.settle();
        }

        return "";
    }

    function swap(SwapExactInputSingleHop calldata params) external payable {
        // Write your code here
        // Determine which token is being swapped in
        address currencyIn = params.zeroForOne
            ? params.poolKey.currency0
            : params.poolKey.currency1;

        // Transfer tokens from user to this contract
        currencyIn.transferIn(msg.sender, uint256(params.amountIn));
        
        // Trigger the swap via unlock callback
        poolManager.unlock(abi.encode(msg.sender, params));

        // Refund any remaining tokens back from this contract to the user
        uint256 bal = currencyIn.balanceOf(address(this));
        if (bal > 0) {
            currencyIn.transferOut(msg.sender, bal);
        }
    }
}

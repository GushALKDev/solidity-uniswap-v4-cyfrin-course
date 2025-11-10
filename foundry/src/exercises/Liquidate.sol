// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";
import {IUniversalRouter} from "../interfaces/IUniversalRouter.sol";
import {IV4Router} from "../interfaces/IV4Router.sol";
import {Actions} from "../libraries/Actions.sol";
import {Commands} from "../libraries/Commands.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {UNIVERSAL_ROUTER, PERMIT2, WETH} from "../Constants.sol";

interface IFlash {
    function flash(address token, uint256 amount, bytes calldata data)
        external;
}

interface IFlashReceiver {
    function flashCallback(
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external;
}

interface ILiquidator {
    function getDebt(address token, address user)
        external
        view
        returns (uint256);
    function liquidate(address collateral, address borrowedToken, address user)
        external;
}

contract Liquidate is IFlashReceiver {
    IUniversalRouter constant router = IUniversalRouter(UNIVERSAL_ROUTER);
    IPermit2 constant permit2 = IPermit2(PERMIT2);
    IWETH constant weth = IWETH(WETH);
    IFlash public immutable flash;
    ILiquidator public immutable liquidator;

    constructor(address _flash, address _liquidator) {
        flash = IFlash(_flash);
        liquidator = ILiquidator(_liquidator);
    }

    receive() external payable {}

    function liquidate(
        // Token to flash loan
        address tokenToRepay,
        // User to liquidate
        address user,
        // V4 pool to swap collateral
        PoolKey calldata key
    ) external {
        // Write your code here
        // Map address(0) to WETH
        (address v4Token0, address v4Token1) = (key.currency0, key.currency1);
        if (v4Token0 == address(0)) {
            v4Token0 = WETH;
        }
        require (tokenToRepay == v4Token0 || tokenToRepay == v4Token1   , "Invalid pool");

        // Get token amount to liquidate
        uint256 debt = liquidator.getDebt(tokenToRepay, user);

        // Flash loan
        flash.flash(tokenToRepay, debt, abi.encode(key, user));

        // Send profit to msg.sender
        uint256 balance = IERC20(tokenToRepay).balanceOf(address(this));
        if (balance > 0) {
            IERC20(tokenToRepay).transfer(msg.sender, balance);
        }
    }

    function flashCallback(
        address tokenToRepay,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external {
        // Write your code here
        // Decode data
        (PoolKey memory key, address user) = abi.decode(data, (PoolKey, address));

        // Set currency addresses
        address v4Token0 = key.currency0 == address(0) ? WETH : key.currency0;
        address v4Token1 = key.currency1;

        // Determine collateral
        address collateral = tokenToRepay == v4Token0 ? v4Token1 : v4Token0;

        // Approve borrowed token to liquidator
        IERC20(tokenToRepay).approve(address(liquidator), amount);

        // Liquidate user
        liquidator.liquidate(collateral, tokenToRepay, user);

        // Swap collateral to borrowed token
        uint256 collateralBalance = IERC20(collateral).balanceOf(address(this));

        // Unwrap WETH if needed
        if (collateral == WETH) {
            weth.withdraw(collateralBalance);
        }

        // Perform swap using Universal Router
        bool zeroForOne = collateral == v4Token0;
        swap({
            key: key,
            amountIn: uint128(collateralBalance),
            amountOutMin: uint128(amount + fee),
            zeroForOne: zeroForOne
        });

        // Repay flash loan
        uint256 totalRepayment = amount + fee;

        // Wrap ETH to WETH if needed
        address currencyOut = zeroForOne ? key.currency1 : key.currency0;
        if (currencyOut == address(0)) {
            weth.deposit{value: address(this).balance}();
        }

        uint256 tokenToRepayBalance = IERC20(tokenToRepay).balanceOf(address(this));
        require(tokenToRepayBalance >= totalRepayment, "Insufficient funds to repay flash loan");
        IERC20(tokenToRepay).transfer(address(flash), totalRepayment);
    }

    function swap(
        PoolKey memory key,
        uint128 amountIn,
        uint128 amountOutMin,
        bool zeroForOne
    ) private {
        (address currencyIn, address currencyOut) = zeroForOne
            ? (key.currency0, key.currency1)
            : (key.currency1, key.currency0);

        if (currencyIn != address(0)) {
            approve(currencyIn, uint160(amountIn), uint48(block.timestamp));
        }

        // UniversalRouter inputs
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // V4 actions and params
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        // SWAP_EXACT_IN_SINGLE
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                hookData: bytes("")
            })
        );
        // SETTLE_ALL (currency, max amount)
        params[1] = abi.encode(currencyIn, uint256(amountIn));
        // TAKE_ALL (currency, min amount)
        params[2] = abi.encode(currencyOut, uint256(amountOutMin));

        // Universal router input
        inputs[0] = abi.encode(actions, params);

        uint256 msgVal = currencyIn == address(0) ? address(this).balance : 0;
        router.execute{value: msgVal}(commands, inputs, block.timestamp);
    }

    function approve(address token, uint160 amount, uint48 expiration)
        private
    {
        IERC20(token).approve(address(permit2), uint256(amount));
        permit2.approve(token, address(router), amount, expiration);
    }
}

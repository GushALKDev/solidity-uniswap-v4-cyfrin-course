// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";
import {IUniversalRouter} from "../interfaces/IUniversalRouter.sol";
import {IV4Router} from "../interfaces/IV4Router.sol";
import {Actions} from "../libraries/Actions.sol";
import {Commands} from "../libraries/Commands.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {UNIVERSAL_ROUTER, PERMIT2} from "../Constants.sol";

contract UniversalRouterExercises {
    IUniversalRouter constant router = IUniversalRouter(UNIVERSAL_ROUTER);
    IPermit2 constant permit2 = IPermit2(PERMIT2);

    receive() external payable {}

    function swap(
        PoolKey calldata key,
        uint128 amountIn,
        uint128 amountOutMin,
        bool zeroForOne
    ) external payable {
        // Write your code here
        // Set currencyIn and currencyOut based on swap direction
        (address currencyIn, address currencyOut) = zeroForOne
            ? (key.currency0, key.currency1)
            : (key.currency1, key.currency0);

        // Transfer tokens from user to this contract
        transferFrom(currencyIn, msg.sender, uint256(amountIn));

        // Approve Permit2 to spend tokens
        if (currencyIn != address(0)) {
            approve(currencyIn, uint160(amountIn), type(uint48).max);
        }

        // UniversalRouter inputs
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // V4 actions and parameters
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

        // Set the inputs for the UniversalRouter
        inputs[0] = abi.encode(actions, params);

        // Execute the swap via UniversalRouter
        router.execute{value: msg.value}(commands, inputs, block.timestamp);

        // Withdraw any remaining tokens to user
        withdraw(key.currency0, msg.sender);
        withdraw(key.currency1, msg.sender);
    }

    function approve(address token, uint160 amount, uint48 expiration)
        private
    {
        IERC20(token).approve(address(permit2), uint256(amount));
        permit2.approve(token, address(router), amount, expiration);
    }

    function transferFrom(address currency, address src, uint256 amt) private {
        if (currency == address(0)) {
            require(msg.value == amt, "not enough ETH sent");
        } else {
            IERC20(currency).transferFrom(src, address(this), amt);
        }
    }

    function withdraw(address currency, address receiver) private {
        if (currency == address(0)) {
            uint256 bal = address(this).balance;
            if (bal > 0) {
                (bool ok,) = receiver.call{value: bal}("");
                require(ok, "Transfer ETH failed");
            }
        } else {
            uint256 bal = IERC20(currency).balanceOf(address(this));
            if (bal > 0) {
                IERC20(currency).transfer(receiver, bal);
            }
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPool} from "../interfaces/aave-v3/IPool.sol";
import {AAVE_V3_POOL} from "../Constants.sol";

interface IFlashReceiver {
    function flashCallback(
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external;
}

contract Flash {
    IPool public constant pool = IPool(AAVE_V3_POOL);

    function flash(address token, uint256 amount, bytes calldata data)
        external
    {
        pool.flashLoanSimple({
            receiverAddress: address(this),
            asset: token,
            amount: amount,
            params: abi.encode(msg.sender, data),
            referralCode: 0
        });
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) public returns (bool) {
        require(msg.sender == address(pool), "not authorized");
        require(initiator == address(this), "invalid initiator");

        (address caller, bytes memory data) =
            abi.decode(params, (address, bytes));
        IERC20(token).transfer(caller, amount);
        IFlashReceiver(caller).flashCallback(token, amount, fee, data);

        IERC20(token).approve(msg.sender, amount + fee);

        return true;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPool} from "../interfaces/aave-v3/IPool.sol";
import {AAVE_V3_POOL} from "../Constants.sol";

contract Liquidator {
    IPool public constant pool = IPool(AAVE_V3_POOL);

    function getDebt(address token, address user)
        public
        view
        returns (uint256)
    {
        IPool.ReserveData memory reserve = pool.getReserveData(token);
        return IERC20(reserve.variableDebtTokenAddress).balanceOf(user);
    }

    function liquidate(address collateral, address borrowedToken, address user)
        external
    {
        uint256 debt = getDebt(borrowedToken, user);

        IERC20(borrowedToken).transferFrom(msg.sender, address(this), debt);
        IERC20(borrowedToken).approve(address(pool), debt);

        pool.liquidationCall({
            collateralAsset: collateral,
            debtAsset: borrowedToken,
            user: user,
            debtToCover: debt,
            receiveAToken: false
        });

        uint256 bal = IERC20(collateral).balanceOf(address(this));
        IERC20(collateral).transfer(msg.sender, bal);
    }
}

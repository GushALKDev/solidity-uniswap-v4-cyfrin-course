// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IPermit2} from "../src/interfaces/IPermit2.sol";
import {IUniversalRouter} from "../src/interfaces/IUniversalRouter.sol";
import {Permit2Hash} from "../src/libraries/Permit2Hash.sol";
import {Commands} from "../src/libraries/Commands.sol";
import {USDC, UNIVERSAL_ROUTER, PERMIT2} from "../src/Constants.sol";

contract UniversalRouterPermit2 is Test {
    IERC20 constant usdc = IERC20(USDC);
    IUniversalRouter constant router = IUniversalRouter(UNIVERSAL_ROUTER);
    IPermit2 constant permit2 = IPermit2(PERMIT2);

    uint256 constant PRIVATE_KEY = 123456789;
    address signer;

    receive() external payable {}

    function setUp() public {
        signer = vm.addr(PRIVATE_KEY);
        require(signer.code.length == 0, "signer is not EOA");
    }

    function prepare(uint48 nonce)
        internal
        view
        returns (IPermit2.PermitSingle memory, bytes memory)
    {
        IPermit2.PermitSingle memory params = IPermit2.PermitSingle({
            details: IPermit2.PermitDetails({
                token: USDC,
                amount: 1,
                expiration: uint48(block.timestamp + 1000),
                nonce: nonce
            }),
            spender: UNIVERSAL_ROUTER,
            sigDeadline: block.timestamp + 1000
        });

        bytes32 hash =
            Permit2Hash.hashTypedData(PERMIT2, Permit2Hash.hash(params));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        return (params, sig);
    }

    function test_universal_router_permit2() public {
        (IPermit2.PermitSingle memory params, bytes memory sig) = prepare(0);

        bytes memory commands = abi.encodePacked(uint8(Commands.PERMIT2_PERMIT));
        // PermitSingle permitSingle
        // bytes signature
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(params, sig);

        // permit2.permit(signer, params, sig);

        // Need to prank signer for Universal router to pass correct msg.sender to permit2
        vm.prank(signer);
        router.execute(commands, inputs, block.timestamp);
    }

    function test_universal_router_permit2_allow_revert() public {
        (IPermit2.PermitSingle memory params, bytes memory sig) = prepare(128);

        bytes memory commands = abi.encodePacked(
            uint8(
                uint256(uint8(Commands.FLAG_ALLOW_REVERT))
                    | Commands.PERMIT2_PERMIT
            )
        );
        // PermitSingle permitSingle
        // bytes signature
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(params, sig);

        vm.prank(signer);
        router.execute(commands, inputs, block.timestamp);
    }
}

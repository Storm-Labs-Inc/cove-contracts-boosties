// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Script } from "forge-std/Script.sol";
import { Constants } from "test/utils/Constants.sol";
import { Yearn4626RouterExt } from "./../src/Yearn4626RouterExt.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { console } from "forge-std/console.sol";

contract Wtf is Script, Constants {
    function run() public {
        (address testAccount, uint256 testAccountPK) =
            deriveRememberKey({ mnemonic: "test test test test test test test test test test test junk", index: 0 });

        vm.prank(testAccount);
        Yearn4626RouterExt router = Yearn4626RouterExt(payable(0x65f47fC50cfB5aCe107aD58F5cf7E9E9420E8095));

        (uint256 v, bytes32 r, bytes32 s) = vm.sign(
            testAccountPK, // user's private key
            keccak256(
                abi.encodePacked(
                    "\x19\x01", // EIP-712 encoding
                    IERC20Permit(0x81d93531720d86f0491DeE7D03f30b3b5aC24e59).DOMAIN_SEPARATOR(),
                    // Frontend should use deadline with enough buffer and with the correct nonce
                    // keccak256(abi.encode(PERMIT_TYPEHASH, user, address(router), depositAmount,
                    // sourceToken.nonces(user),
                    // block.timestamp + 100_000))
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH, testAccount, address(router), 100_000_000_000_000_000_000, 0, 1_712_273_717
                        )
                    )
                )
            )
        );

        bytes[] memory data = new bytes[](1);
        data[0] =
            hex"f3995c6700000000000000000000000081d93531720d86f0491dee7d03f30b3b5ac24e590000000000000000000000000000000000000000000000056bc75e2d6310000000000000000000000000000000000000000000000000000000000000660f3935000000000000000000000000000000000000000000000000000000000000001bd446edb1a3f219522fb55945ca53f49bfb5f5ac4362e0c62f55528415187caf20f9a6bfd1f6e5abea50fec3553c8fad03808efee47ba046f6a6c2eab9a39cde2";
        router.multicall(data);

        console.log("v: %s, r: %s, s: %s", vm.toString(v), vm.toString(r), vm.toString(s));
    }
}

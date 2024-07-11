// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { DYFIRedeemer } from "src/DYFIRedeemer.sol";

contract TestCantRedeem is Test {
    address public constant DYFI_REDEEMER = 0x986F38B5b096070eE64B12Da762468606C8B0706;

    DYFIRedeemer public dYfiRedeemer;

    function test_poc() public {
        dYfiRedeemer = DYFIRedeemer(payable(DYFI_REDEEMER));

        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_733_563);
        // This will revert as the price is outdated becasue of the misaligned check
        dYfiRedeemer.getLatestPrice();
    }
}

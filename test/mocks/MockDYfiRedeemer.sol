// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants } from "test/utils/Constants.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract MockDYFIRedeemer is Constants, StdCheats {
    function massRedeem(address[] calldata accounts, uint256[] calldata dYfiAmounts) external {
        for (uint256 i = 0; i < accounts.length; i++) {
            IERC20(MAINNET_DYFI).transferFrom(accounts[i], address(this), dYfiAmounts[i]);
        }
        for (uint256 i = 0; i < accounts.length; i++) {
            deal(MAINNET_YFI, address(this), dYfiAmounts[i], true);
            IERC20(MAINNET_YFI).transfer(accounts[i], dYfiAmounts[i]);
        }
    }
}

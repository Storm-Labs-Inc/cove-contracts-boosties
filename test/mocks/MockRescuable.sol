// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Rescuable } from "src/Rescuable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockRescuable is Rescuable {
    constructor() { }

    function rescue(IERC20 token, address to, uint256 balance) external {
        _rescue(token, to, balance);
    }
}

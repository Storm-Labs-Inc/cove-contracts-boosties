// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Rescuable } from "src/Rescuable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockRescuable is Rescuable {
    // solhint-disable-next-line no-empty-blocks
    constructor() { }

    function rescue(IERC20 token, address to, uint256 balance) external {
        _rescue(token, to, balance);
    }
}

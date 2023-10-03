// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { ERC20Pausable } from "@openzeppelin-5.0/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import { Ownable } from "@openzeppelin-5.0/contracts/access/Ownable.sol";

contract CoveYFI is ERC20Pausable, Ownable {
    constructor() ERC20("Cove YFI", "coveYFI") Ownable(msg.sender) { }
}

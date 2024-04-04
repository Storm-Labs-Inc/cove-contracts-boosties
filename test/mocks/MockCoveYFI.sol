// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract MockCoveYFI is ERC20Mock {
    address private immutable _YFI;

    constructor(address yfi) ERC20Mock() {
        _YFI = yfi;
    }

    function deposit(uint256 balance) external returns (uint256) {
        return _deposit(balance, msg.sender);
    }

    function deposit(uint256 balance, address receiver) external returns (uint256) {
        return _deposit(balance, receiver);
    }

    function _deposit(uint256 balance, address receiver) internal returns (uint256) {
        _mint(receiver, balance);
        IERC20(_YFI).transferFrom(msg.sender, address(this), balance);
        return balance;
    }
}

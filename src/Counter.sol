// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

contract Counter {
    uint256 public number;
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function setNumber(uint256 newNumber) public {
        number = newNumber;
        for (uint256 i = 0; i < 100; i++) {
            number++;
        }
        for (uint256 i = 0; i < 100; i++) {
            number--;
        }
    }

    function increment() public {
        number++;
    }
}

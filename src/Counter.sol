// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

contract Counter {
    uint256 public number;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}

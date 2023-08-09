// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { Counter } from "src/Counter.sol";

contract CounterTest is BaseTest {
    Counter public counter;

    function setUp() public override {
        super.setUp();
        counter = new Counter();
        counter.setNumber(0);
    }

    function testIncrement() public {
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testSetNumber(uint256 x) public {
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }
}

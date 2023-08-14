pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";

contract Safe {
    receive() external payable { }

    function withdraw() external {
        payable(msg.sender).transfer(address(this).balance);
    }
}

contract SafeTest is Test {
    Safe _safe;

    // Needed so the test contract itself can receive ether
    // when withdrawing
    receive() external payable { }

    function setUp() public {
        _safe = new Safe();
    }

    // amount is restricted to the amount contracts are given while
    // testing which is 2**96 wei
    function testFuzz_Withdraw(uint96 amount) public {
        // assumes will restrict fuzzing inputs
        vm.assume(amount > 0.1 ether);
        payable(address(_safe)).transfer(amount);
        uint256 preBalance = address(this).balance;
        _safe.withdraw();
        uint256 postBalance = address(this).balance;
        assertEq(preBalance + amount, postBalance);
    }
}

pragma solidity ^0.8.18;

contract MockTarget {
    bytes public data;
    uint256 public value;

    fallback() external payable {
        // store calldata
        data = msg.data;
        value = msg.value;
    }
}

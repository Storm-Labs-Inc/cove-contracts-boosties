// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

contract MockChainLinkOracle {
    uint256 public price;
    uint256 public timestamp;

    constructor(uint256 _price) {
        price = _price;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function setTimestamp(uint256 _timestamp) external {
        timestamp = _timestamp;
    }

    function latestRoundData() external view returns (uint80, int256 _price, uint256, uint256 _timeStamp, uint80) {
        return (0, int256(price), 0, timestamp, 0);
    }

    function decimals() external pure returns (uint256) {
        return 8;
    }
}

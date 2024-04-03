// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

contract MockChainLinkOracle {
    uint256 public price;
    uint256 public timestamp;
    uint80 public roundID = 0;
    uint80 public answeredInRound = 0;

    constructor(uint256 _price) {
        price = _price;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function setRoundID(uint80 _roundID) external {
        roundID = _roundID;
    }

    function setAnswerInRound(uint80 _answeredInRound) external {
        answeredInRound = _answeredInRound;
    }

    function setTimestamp(uint256 _timestamp) external {
        timestamp = _timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80 _roundID, int256 _price, uint256, uint256 _timeStamp, uint80 _answeredInRound)
    {
        return (roundID, int256(price), 0, timestamp, answeredInRound);
    }

    function decimals() external pure returns (uint256) {
        return 8;
    }
}

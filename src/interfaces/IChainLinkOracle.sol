// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IChainLinkOracle {
    function latestRoundData()
        external
        view
        returns (uint80 roundID, int256 price, uint256 startedAt, uint256 timeStamp, uint80 answeredInRound);
    function decimals() external view returns (uint256);
}

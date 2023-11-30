// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IYfiRewardPool {
    event CheckpointToken(uint256 time, uint256 tokens);

    function claim() external returns (uint256);
    function checkpoint_token() external;
    function checkpoint_total_supply() external;
}

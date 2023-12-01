// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IStakingDelegateRewards {
    function getReward(address stakingToken) external returns (uint256);
}

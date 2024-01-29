// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBaseRewardsGauge {
    function depositRewardToken(address rewardToken, uint256 amount) external;
}

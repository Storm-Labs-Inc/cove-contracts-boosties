// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

interface IBaseRewardsGauge {
    function depositRewardToken(address rewardToken, uint256 amount) external;
}

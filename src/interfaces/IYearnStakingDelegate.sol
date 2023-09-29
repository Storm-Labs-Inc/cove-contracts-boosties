// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IYearnStakingDelegate {
    struct UserInfo {
        uint128 balance;
        uint128 rewardDebt;
    }

    function depositToGauge(address vault, uint256 amount) external;
    function withdrawFromGauge(address vault, uint256 amount) external;
    // mapping(address user => mapping(address vault => UserInfo)) public userInfo;

    function userInfo(address user, address vault) external view returns (UserInfo memory);
    function harvest(address vault) external returns (uint256);
    function setRewardSplit(uint80 treasuryPct, uint80 compoundPct, uint80 veYfiPct) external;
}

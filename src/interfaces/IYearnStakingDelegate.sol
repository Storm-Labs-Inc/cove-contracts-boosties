// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IYearnStakingDelegate {
    struct UserInfo {
        uint128 balance;
        uint128 rewardDebt;
    }

    function depositToGauge(address vault, uint256 amount) external;
    function withdrawFromGauge(address vault, uint256 amount) external;
    function lockYfi(uint256 amount) external;

    function userInfo(address user, address vault) external view returns (UserInfo memory);
    function harvest(address vault) external returns (uint256);
    function setRewardSplit(uint80 treasuryPct, uint80 compoundPct, uint80 veYfiPct) external;
    function balances(address gauge, address user) external view returns (uint256);
}

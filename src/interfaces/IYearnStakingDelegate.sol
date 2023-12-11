// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IVotingYFI } from "./deps/yearn/veYFI/IVotingYFI.sol";

interface IYearnStakingDelegate {
    // Struct definitions
    struct RewardSplit {
        uint80 treasury;
        uint80 user;
        uint80 lock;
    }

    function deposit(address gauge, uint256 amount) external;
    function withdraw(address gauge, uint256 amount) external;
    function lockYfi(uint256 amount) external returns (IVotingYFI.LockedBalance memory);
    function harvest(address vault) external returns (uint256);
    function setGaugeRewardSplit(address gauge, uint80 treasuryPct, uint80 compoundPct, uint80 veYfiPct) external;
    function setSwapAndLock(address swapAndLock) external;
    function balanceOf(address user, address gauge) external view returns (uint256);
    function gaugeStakingRewards(address gauge) external view returns (address);
    function gaugeRewardReceivers(address gauge) external view returns (address);
    function gaugeRewardSplit(address gauge) external view returns (uint80, uint80, uint80);
}

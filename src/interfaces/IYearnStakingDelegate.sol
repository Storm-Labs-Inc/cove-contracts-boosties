// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IVotingYFI } from "./deps/yearn/veYFI/IVotingYFI.sol";

interface IYearnStakingDelegate {
    function deposit(address gauge, uint256 amount) external;
    function withdraw(address gauge, uint256 amount) external;
    function lockYfi(uint256 amount) external returns (IVotingYFI.LockedBalance memory);
    function harvest(address vault) external returns (uint256);
    function setRewardSplit(address gauge, uint80 treasuryPct, uint80 compoundPct, uint80 veYfiPct) external;
    function setSwapAndLock(address swapAndLock) external;
    function balances(address gauge, address user) external view returns (uint256);
    function gaugeStakingRewards(address gauge) external view returns (address);
}

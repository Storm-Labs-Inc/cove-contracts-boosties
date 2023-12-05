// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IVotingYFI } from "./deps/yearn/veYFI/IVotingYFI.sol";
import { IYearnStakingDelegateEvents } from "./IYearnStakingDelegateEvents.sol";

interface IYearnStakingDelegate is IYearnStakingDelegateEvents {
    function deposit(address gauge, uint256 amount) external;
    function withdraw(address gauge, uint256 amount) external;
    function lockYfi(uint256 amount) external returns (IVotingYFI.LockedBalance memory);
    function harvest(address vault) external returns (uint256);
    function setRewardSplit(address gauge, uint80 treasuryPct, uint80 compoundPct, uint80 veYfiPct) external;
    function setSwapAndLock(address swapAndLock) external;
    function balanceOf(address user, address gauge) external view returns (uint256);
    function gaugeStakingRewards(address gauge) external view returns (address);
}

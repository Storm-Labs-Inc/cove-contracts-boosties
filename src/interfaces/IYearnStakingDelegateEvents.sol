// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IYearnStakingDelegateEvents {
    // Struct definitions
    struct RewardSplit {
        uint80 treasury;
        uint80 user;
        uint80 lock;
    }

    event LockYfi(address indexed sender, uint256 amount);
    event GaugeRewardsSet(address indexed gauge, address stakingRewardsContract, address receiver);
    event PerpetualLockSet(bool shouldLock);
    event GaugeRewardSplitSet(address indexed gauge, RewardSplit split);
    event SwapAndLockSet(address swapAndLockContract);
    event TreasurySet(address newTreasury);
    event Deposit(address indexed sender, address indexed gauge, uint256 amount);
    event Withdraw(address indexed sender, address indexed gauge, uint256 amount);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IVotingYFI } from "./deps/yearn/veYFI/IVotingYFI.sol";

interface IYearnStakingDelegate {
    // Struct definitions
    struct RewardSplit {
        uint64 treasury;
        uint64 coveYfi;
        uint64 user;
        uint64 lock;
    }

    struct ExitRewardSplit {
        uint128 treasury;
        uint128 coveYfi;
    }

    struct BoostRewardSplit {
        uint128 treasury;
        uint128 coveYfi;
    }

    function deposit(address gauge, uint256 amount) external;
    function withdraw(address gauge, uint256 amount) external;
    function withdraw(address gauge, uint256 amount, address receiver) external;
    function lockYfi(uint256 amount) external returns (IVotingYFI.LockedBalance memory);
    function harvest(address vault) external returns (uint256);
    function setCoveYfiRewardForwarder(address forwarder) external;
    function setGaugeRewardSplit(
        address gauge,
        uint64 treasuryPct,
        uint64 coveYfiPct,
        uint64 userPct,
        uint64 veYfiPct
    )
        external;

    function setBoostRewardSplit(uint128 treasuryPct, uint128 coveYfiPct) external;
    function setExitRewardSplit(uint128 treasuryPct, uint128 coveYfiPct) external;
    function setSwapAndLock(address swapAndLock) external;
    function balanceOf(address user, address gauge) external view returns (uint256);
    function totalDeposited(address gauge) external view returns (uint256);
    function depositLimit(address gauge) external view returns (uint256);
    function availableDepositLimit(address gauge) external view returns (uint256);
    function gaugeStakingRewards(address gauge) external view returns (address);
    function gaugeRewardReceivers(address gauge) external view returns (address);
    function getGaugeRewardSplit(address gauge) external view returns (RewardSplit memory);
    function getBoostRewardSplit() external view returns (BoostRewardSplit memory);
    function getExitRewardSplit() external view returns (ExitRewardSplit memory);
}

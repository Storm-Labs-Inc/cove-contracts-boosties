// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Clone } from "lib/clones-with-immutable-args/src/Clone.sol";
import { YearnStakingDelegate } from "./YearnStakingDelegate.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract GaugeRewardReceiver is Clone {
    // Libraries
    using SafeERC20 for IERC20;

    function stakingDelegate() public pure returns (address) {
        return _getArgAddress(0);
    }

    function gauge() public pure returns (address) {
        return _getArgAddress(20);
    }

    function rewardToken() public pure returns (address) {
        return _getArgAddress(40);
    }

    function strategy() public pure returns (address) {
        return _getArgAddress(60);
    }

    /// @notice Harvest rewards from the gauge and distribute to treasury, compound, and veYFI
    /// @return userRewardsAmount amount of rewards harvested for the msg.sender
    // TODO(Trail of Bits): PTAL at how to fix this reentrancy
    // slither-disable-start reentrancy-no-eth
    function harvest(
        address swapAndLock,
        address treasury,
        YearnStakingDelegate.RewardSplit memory rewardSplit
    )
        external
        returns (uint256)
    {
        // Read pending dYFI rewards from the gauge
        // Yearn's gauge implementation always returns true
        // Ref: https://github.com/yearn/veYFI/blob/master/contracts/Gauge.sol#L493
        // slither-disable-next-line unused-return
        IGauge(gauge()).getReward(stakingDelegate());
        uint256 totalRewardsAmount = IERC20(rewardToken()).balanceOf(address(this));

        // Store the amount of dYFI to use for locking later
        uint256 swapAndLockAmount = totalRewardsAmount * uint256(rewardSplit.lock) / 1e18;
        uint256 treasuryAmount = totalRewardsAmount * uint256(rewardSplit.treasury) / 1e18;
        uint256 strategyAmount = totalRewardsAmount - swapAndLockAmount - treasuryAmount;

        // Transfer pending rewards to the user
        if (strategyAmount != 0) {
            IERC20(rewardToken()).safeTransfer(strategy(), strategyAmount);
        }
        // Trasnfer rewards to the treasury
        if (rewardSplit.treasury != 0) {
            IERC20(rewardToken()).safeTransfer(treasury, treasuryAmount);
        }
        // Transfer rewards to the swap and lock contract
        if (swapAndLockAmount != 0) {
            IERC20(rewardToken()).safeTransfer(swapAndLock, swapAndLockAmount);
        }

        return strategyAmount;
    }
    // slither-disable-end reentrancy-no-eth
}

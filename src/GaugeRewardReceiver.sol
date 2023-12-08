// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Clone } from "lib/clones-with-immutable-args/src/Clone.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { StakingDelegateRewards } from "src/StakingDelegateRewards.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { Errors } from "src/libraries/Errors.sol";

/// @title GaugeRewardReceiver
/// @notice Contract to receive rewards from a Yearn gauge and distribute them according to specified splits.
/// @dev Inherits from Clone and ReentrancyGuardUpgradeable for creating clones acts and preventing reentrancy attacks.
contract GaugeRewardReceiver is Clone, ReentrancyGuardUpgradeable {
    // Libraries
    using SafeERC20 for IERC20;

    /// @dev Initializes the contract by disabling initializers from the Clone pattern.
    constructor() {
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */
    /// @notice Initializes the GaugeRewardReceiver contract.
    function initialize() public initializer {
        __ReentrancyGuard_init();
        IERC20(rewardToken()).safeApprove(stakingDelegateRewards(), type(uint256).max);
    }

    /* ========== VIEWS ========== */

    /// @notice Gets the address of the staking delegate from the contract's immutable arguments.
    /// @return The address of the staking delegate.
    function stakingDelegate() public pure returns (address) {
        return _getArgAddress(0);
    }

    /// @notice Gets the address of the gauge from the contract's immutable arguments.
    /// @return The address of the gauge.
    function gauge() public pure returns (address) {
        return _getArgAddress(20);
    }

    /// @notice Gets the address of the reward token from the contract's immutable arguments.
    /// @return The address of the reward token.
    function rewardToken() public pure returns (address) {
        return _getArgAddress(40);
    }

    /// @notice Gets the address of the staking delegate rewards contract from the contract's immutable arguments.
    /// @return The address of the staking delegate rewards contract.
    function stakingDelegateRewards() public pure returns (address) {
        return _getArgAddress(60);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // TODO(Trail of Bits): PTAL at how to fix this reentrancy
    // slither-disable-start reentrancy-no-eth
    /// @notice Harvest rewards from the gauge and distribute to treasury, compound, and veYFI
    /// @param swapAndLock Address of the SwapAndLock contract.
    /// @param treasury Address of the treasury to receive a portion of the rewards.
    /// @param rewardSplit Struct containing the split percentages for lock, treasury, and user rewards.
    /// @return userRewardsAmount The amount of rewards harvested for the user.
    function harvest(
        address swapAndLock,
        address treasury,
        YearnStakingDelegate.RewardSplit memory rewardSplit
    )
        external
        nonReentrant
        returns (uint256)
    {
        if (msg.sender != stakingDelegate()) {
            revert Errors.NotAuthorized();
        }
        if (rewardSplit.lock + rewardSplit.treasury + rewardSplit.user != 1e18) {
            revert Errors.InvalidRewardSplit();
        }
        // Read pending dYFI rewards from the gauge
        // Yearn's gauge implementation always returns true
        // Ref: https://github.com/yearn/veYFI/blob/master/contracts/Gauge.sol#L493
        // slither-disable-next-line unused-return
        IGauge(gauge()).getReward(stakingDelegate());
        uint256 totalRewardsAmount = IERC20(rewardToken()).balanceOf(address(this));

        // Store the amount of dYFI to use for locking later
        uint256 swapAndLockAmount = totalRewardsAmount * uint256(rewardSplit.lock) / 1e18;
        uint256 treasuryAmount = totalRewardsAmount * uint256(rewardSplit.treasury) / 1e18;
        uint256 userAmount = totalRewardsAmount - swapAndLockAmount - treasuryAmount;

        // Transfer rewards to the staking delegate rewards contract
        if (userAmount != 0) {
            StakingDelegateRewards(stakingDelegateRewards()).notifyRewardAmount(gauge(), userAmount);
        }
        // Transfer rewards to the treasury
        if (rewardSplit.treasury != 0) {
            IERC20(rewardToken()).safeTransfer(treasury, treasuryAmount);
        }
        // Transfer rewards to the swap and lock contract
        if (swapAndLockAmount != 0) {
            IERC20(rewardToken()).safeTransfer(swapAndLock, swapAndLockAmount);
        }

        return userAmount;
    }
    // slither-disable-end reentrancy-no-eth
}

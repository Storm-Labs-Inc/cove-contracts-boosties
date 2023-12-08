// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IStakingDelegateRewards } from "src/interfaces/deps/yearn/veYFI/IStakingDelegateRewards.sol";

/// @title Staking Delegate Rewards
/// @notice Contract for managing staking rewards with functionality to update
/// balances, notify new rewards, and recover tokens.
/// @dev Inherits from IStakingDelegateRewards, AccessControl, and ReentrancyGuard.
contract StakingDelegateRewards is IStakingDelegateRewards, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    uint256 public constant DEFAULT_DURATION = 7 days;

    // slither-disable-start naming-convention
    address private immutable _REWARDS_TOKEN;
    address private immutable _STAKING_DELEGATE;
    // slither-disable-end naming-convention

    mapping(address => uint256) public periodFinish;
    mapping(address => uint256) public rewardRate;
    mapping(address => uint256) public rewardsDuration;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public rewardPerTokenStored;
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public rewards;
    mapping(address => address) public rewardDistributors;
    mapping(address => uint256) public totalSupply;
    mapping(address => mapping(address => uint256)) public balanceOf;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Constructor that sets the rewards token and staking delegate addresses.
     * @param rewardsToken_ The ERC20 token to be used as the rewards token.
     * @param stakingDelegate_ The address of the staking delegate contract.
     */
    constructor(address rewardsToken_, address stakingDelegate_) {
        // Checks
        // Check for zero addresses
        if (rewardsToken_ == address(0) || stakingDelegate_ == address(0)) {
            revert Errors.ZeroAddress();
        }

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _REWARDS_TOKEN = rewardsToken_;
        _STAKING_DELEGATE = stakingDelegate_;
    }

    /* ========== VIEWS ========== */

    /// @notice Returns the address of the rewards token.
    /// @return The address of the rewards token.
    function rewardToken() external view returns (address) {
        return _REWARDS_TOKEN;
    }

    /// @notice Returns the address of the staking delegate.
    /// @return The address of the staking delegate.
    function stakingDelegate() external view returns (address) {
        return _STAKING_DELEGATE;
    }

    /// @notice Calculates the last time a reward was applicable for the given staking token.
    /// @param stakingToken The address of the staking token.
    /// @return The last applicable timestamp for rewards.
    function lastTimeRewardApplicable(address stakingToken) public view returns (uint256) {
        uint256 finish = periodFinish[stakingToken];
        // slither-disable-next-line timestamp
        return block.timestamp < finish ? block.timestamp : finish;
    }

    /// @notice Calculates the accumulated reward per token stored.
    /// @param stakingToken The address of the staking token.
    /// @return The accumulated reward per token.
    function rewardPerToken(address stakingToken) public view returns (uint256) {
        uint256 totalSupply_ = totalSupply[stakingToken];
        if (totalSupply_ == 0) {
            return rewardPerTokenStored[stakingToken];
        }
        return rewardPerTokenStored[stakingToken]
            + (lastTimeRewardApplicable(stakingToken) - lastUpdateTime[stakingToken]) * rewardRate[stakingToken] * 1e18
                / totalSupply_;
    }

    /// @notice Calculates the amount of reward earned by an account for a given staking token.
    /// @param account The address of the user's account.
    /// @param stakingToken The address of the staking token.
    /// @return The amount of reward earned.
    function earned(address account, address stakingToken) public view returns (uint256) {
        return rewards[account][stakingToken]
            + (
                balanceOf[account][stakingToken]
                    * (rewardPerToken(stakingToken) - userRewardPerTokenPaid[account][stakingToken]) / 1e18
            );
    }

    /// @notice Calculates the total reward for a given duration for a staking token.
    /// @param stakingToken The address of the staking token.
    /// @return The total reward for the given duration.
    function getRewardForDuration(address stakingToken) external view returns (uint256) {
        return rewardRate[stakingToken] * rewardsDuration[stakingToken];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Claims reward for a given staking token.
    /// @param stakingToken The address of the staking token.
    function getReward(address stakingToken) external nonReentrant {
        _getReward(msg.sender, stakingToken);
    }

    /// @notice Claims reward for a given user and staking token.
    /// @param user The address of the user to claim rewards for.
    /// @param stakingToken The address of the staking token.
    function getReward(address user, address stakingToken) external nonReentrant {
        _getReward(user, stakingToken);
    }

    /// @notice Updates the reward state for a given user and staking token.
    /// @param user The address of the user to update rewards for.
    /// @param stakingToken The address of the staking token.
    function _getReward(address user, address stakingToken) internal {
        _updateReward(user, stakingToken);
        uint256 reward = rewards[user][stakingToken];
        if (reward > 0) {
            rewards[user][stakingToken] = 0;
            IERC20(_REWARDS_TOKEN).safeTransfer(user, reward);
            emit RewardPaid(user, stakingToken, reward);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */
    /// @notice Updates the balance of a user for a given staking token.
    /// @param user The address of the user to update the balance for.
    /// @param stakingToken The address of the staking token.
    /// @param totalAmount The new total amount to set for the user's balance.
    function updateUserBalance(address user, address stakingToken, uint256 totalAmount) external {
        if (msg.sender != _STAKING_DELEGATE) {
            revert Errors.OnlyStakingDelegateCanUpdateUserBalance();
        }
        _updateReward(user, stakingToken);
        uint256 currentUserBalance = balanceOf[user][stakingToken];
        balanceOf[user][stakingToken] = totalAmount;
        totalSupply[stakingToken] = totalSupply[stakingToken] - currentUserBalance + totalAmount;
        emit UserBalanceUpdated(user, stakingToken, totalAmount);
    }

    /// @notice Adds a new staking token to the contract.
    /// @param stakingToken The address of the staking token to add.
    /// @param rewardDistributioner The address allowed to notify new rewards for the staking token.
    function addStakingToken(address stakingToken, address rewardDistributioner) external {
        if (msg.sender != _STAKING_DELEGATE) {
            revert Errors.OnlyStakingDelegateCanAddStakingToken();
        }
        if (rewardDistributors[stakingToken] != address(0)) {
            revert Errors.StakingTokenAlreadyAdded();
        }
        rewardDistributors[stakingToken] = rewardDistributioner;
        rewardsDuration[stakingToken] = DEFAULT_DURATION;
        emit StakingTokenAdded(stakingToken, rewardDistributioner);
        emit RewardsDurationUpdated(stakingToken, DEFAULT_DURATION);
    }

    /// @notice Notifies a new reward amount for a given staking token.
    /// @param stakingToken The address of the staking token to notify the reward for.
    /// @param reward The amount of the new reward.
    function notifyRewardAmount(address stakingToken, uint256 reward) external nonReentrant {
        if (msg.sender != rewardDistributors[stakingToken]) {
            revert Errors.OnlyRewardDistributorCanNotifyRewardAmount();
        }
        _updateReward(address(0), stakingToken);

        uint256 periodFinish_ = periodFinish[stakingToken];
        // slither-disable-next-line timestamp
        if (block.timestamp >= periodFinish_) {
            rewardRate[stakingToken] = reward / rewardsDuration[stakingToken];
        } else {
            uint256 remaining = periodFinish_ - block.timestamp;
            uint256 leftover = remaining * rewardRate[stakingToken];
            rewardRate[stakingToken] = (reward + leftover) / rewardsDuration[stakingToken];
        }

        lastUpdateTime[stakingToken] = block.timestamp;
        periodFinish[stakingToken] = block.timestamp + (rewardsDuration[stakingToken]);
        IERC20(_REWARDS_TOKEN).safeTransferFrom(msg.sender, address(this), reward);
        emit RewardAdded(stakingToken, reward);
    }

    /// @notice Allows recovery of ERC20 tokens other than the staking and rewards tokens.
    /// @param tokenAddress The address of the token to recover.
    /// @param to The address to send the recovered tokens to.
    /// @param tokenAmount The amount of tokens to recover.
    /// @dev Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(
        address tokenAddress,
        address to,
        uint256 tokenAmount
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (tokenAddress == _REWARDS_TOKEN || rewardDistributors[tokenAddress] != address(0)) {
            revert Errors.RescueNotAllowed();
        }
        emit Recovered(tokenAddress, tokenAmount);
        IERC20(tokenAddress).safeTransfer(to, tokenAmount);
    }

    /// @notice Sets the duration of the rewards period for a given staking token.
    /// @param stakingToken The address of the staking token to set the rewards duration for.
    /// @param rewardsDuration_ The new duration of the rewards period.
    function setRewardsDuration(address stakingToken, uint256 rewardsDuration_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // slither-disable-next-line timestamp
        if (block.timestamp <= periodFinish[stakingToken]) {
            revert Errors.PreviousRewardsPeriodNotCompleted();
        }
        rewardsDuration[stakingToken] = rewardsDuration_;
        emit RewardsDurationUpdated(stakingToken, rewardsDuration_);
    }

    /* ========== MODIFIERS ========== */

    /// @dev Updates reward state for a given user and staking token.
    /// @param account The address of the user to update rewards for.
    /// @param stakingToken The address of the staking token.
    function _updateReward(address account, address stakingToken) internal {
        rewardPerTokenStored[stakingToken] = rewardPerToken(stakingToken);
        lastUpdateTime[stakingToken] = lastTimeRewardApplicable(stakingToken);
        if (account != address(0)) {
            rewards[account][stakingToken] = earned(account, stakingToken);
            userRewardPerTokenPaid[account][stakingToken] = rewardPerTokenStored[stakingToken];
        }
    }

    /* ========== EVENTS ========== */

    event RewardAdded(address indexed stakingToken, uint256 reward);
    event StakingTokenAdded(address indexed stakingToken, address rewardDistributioner);
    event UserBalanceUpdated(address indexed user, address indexed stakingToken, uint256 amount);
    event RewardPaid(address indexed user, address indexed stakingToken, uint256 reward);
    event RewardsDurationUpdated(address indexed stakingToken, uint256 newDuration);
    event Recovered(address token, uint256 amount);
}

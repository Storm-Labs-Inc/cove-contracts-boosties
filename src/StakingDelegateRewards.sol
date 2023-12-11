// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IStakingDelegateRewards } from "src/interfaces/deps/yearn/veYFI/IStakingDelegateRewards.sol";

/**
 * @title Staking Delegate Rewards
 * @notice Contract for managing staking rewards with functionality to update balances, notify new rewards, and recover
 * tokens.
 * @dev Inherits from IStakingDelegateRewards, AccessControl, and ReentrancyGuard.
 */
contract StakingDelegateRewards is IStakingDelegateRewards, AccessControl, ReentrancyGuard {
    // Libraries
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant _DEFAULT_DURATION = 7 days;
    // slither-disable-start naming-convention
    address private immutable _REWARDS_TOKEN;
    address private immutable _STAKING_DELEGATE;
    // slither-disable-end naming-convention

    // State variables
    mapping(address => uint256) private _periodFinish;
    mapping(address => uint256) private _rewardRate;
    mapping(address => uint256) private _rewardsDuration;
    mapping(address => uint256) private _lastUpdateTime;
    mapping(address => uint256) private _rewardPerTokenStored;
    mapping(address => mapping(address => uint256)) private _userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) private _rewards;
    mapping(address => address) private _rewardDistributors;
    mapping(address => uint256) private _totalSupply;
    mapping(address => mapping(address => uint256)) private _balances;

    // Events
    event RewardAdded(address indexed stakingToken, uint256 reward);
    event StakingTokenAdded(address indexed stakingToken, address rewardDistributioner);
    event UserBalanceUpdated(address indexed user, address indexed stakingToken, uint256 amount);
    event RewardPaid(address indexed user, address indexed stakingToken, uint256 reward);
    event RewardsDurationUpdated(address indexed stakingToken, uint256 newDuration);
    event Recovered(address token, uint256 amount);

    /**
     * @notice Constructor that sets the rewards token and staking delegate addresses.
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

    /**
     * @notice Claims reward for a given staking token.
     * @param stakingToken The address of the staking token.
     */
    function getReward(address stakingToken) external nonReentrant {
        _getReward(msg.sender, stakingToken);
    }

    /**
     * @notice Claims reward for a given user and staking token.
     * @param user The address of the user to claim rewards for.
     * @param stakingToken The address of the staking token.
     */
    function getReward(address user, address stakingToken) external nonReentrant {
        _getReward(user, stakingToken);
    }

    /**
     * @notice Notifies a new reward amount for a given staking token.
     * @param stakingToken The address of the staking token to notify the reward for.
     * @param reward The amount of the new reward.
     */
    function notifyRewardAmount(address stakingToken, uint256 reward) external nonReentrant {
        if (msg.sender != _rewardDistributors[stakingToken]) {
            revert Errors.OnlyRewardDistributorCanNotifyRewardAmount();
        }
        _updateReward(address(0), stakingToken);

        uint256 storedPeriodFinish = _periodFinish[stakingToken];
        uint256 storedRewardDuration = _rewardsDuration[stakingToken];
        uint256 newRewardRate = 0;
        // slither-disable-next-line timestamp
        if (block.timestamp >= storedPeriodFinish) {
            newRewardRate = reward / storedRewardDuration;
        } else {
            uint256 remaining = storedPeriodFinish - block.timestamp;
            uint256 leftover = remaining * _rewardRate[stakingToken];
            newRewardRate = (reward + leftover) / storedRewardDuration;
        }
        // If reward < duration, newRewardRate will be 0, causing dust to be left in the contract
        // slither-disable-next-line incorrect-equality
        if (newRewardRate == 0) {
            revert Errors.RewardRateTooLow();
        }
        _rewardRate[stakingToken] = newRewardRate;
        _lastUpdateTime[stakingToken] = block.timestamp;
        _periodFinish[stakingToken] = block.timestamp + storedRewardDuration;
        IERC20(_REWARDS_TOKEN).safeTransferFrom(msg.sender, address(this), reward);
        emit RewardAdded(stakingToken, reward);
    }

    /**
     * @notice Updates the balance of a user for a given staking token.
     * @param user The address of the user to update the balance for.
     * @param stakingToken The address of the staking token.
     * @param totalAmount The new total amount to set for the user's balance.
     */
    function updateUserBalance(address user, address stakingToken, uint256 totalAmount) external {
        if (msg.sender != _STAKING_DELEGATE) {
            revert Errors.OnlyStakingDelegateCanUpdateUserBalance();
        }
        _updateReward(user, stakingToken);
        uint256 currentUserBalance = _balances[user][stakingToken];
        _balances[user][stakingToken] = totalAmount;
        _totalSupply[stakingToken] = _totalSupply[stakingToken] - currentUserBalance + totalAmount;
        emit UserBalanceUpdated(user, stakingToken, totalAmount);
    }

    /**
     * @notice Adds a new staking token to the contract.
     * @param stakingToken The address of the staking token to add.
     * @param rewardDistributioner The address allowed to notify new rewards for the staking token.
     */
    function addStakingToken(address stakingToken, address rewardDistributioner) external {
        if (msg.sender != _STAKING_DELEGATE) {
            revert Errors.OnlyStakingDelegateCanAddStakingToken();
        }
        if (_rewardDistributors[stakingToken] != address(0)) {
            revert Errors.StakingTokenAlreadyAdded();
        }
        _rewardDistributors[stakingToken] = rewardDistributioner;
        _rewardsDuration[stakingToken] = _DEFAULT_DURATION;
        emit StakingTokenAdded(stakingToken, rewardDistributioner);
        emit RewardsDurationUpdated(stakingToken, _DEFAULT_DURATION);
    }

    /**
     * @notice Sets the duration of the rewards period for a given staking token.
     * @param stakingToken The address of the staking token to set the rewards duration for.
     * @param newRewardsDuration The new duration of the rewards period.
     */
    function setRewardsDuration(
        address stakingToken,
        uint256 newRewardsDuration
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // slither-disable-next-line timestamp
        if (block.timestamp <= _periodFinish[stakingToken]) {
            revert Errors.PreviousRewardsPeriodNotCompleted();
        }
        _rewardsDuration[stakingToken] = newRewardsDuration;
        emit RewardsDurationUpdated(stakingToken, newRewardsDuration);
    }

    /**
     * @notice Allows recovery of ERC20 tokens other than the staking and rewards tokens.
     * @dev Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
     * @param tokenAddress The address of the token to recover.
     * @param to The address to send the recovered tokens to.
     * @param tokenAmount The amount of tokens to recover.
     */
    function recoverERC20(
        address tokenAddress,
        address to,
        uint256 tokenAmount
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (tokenAddress == _REWARDS_TOKEN || _rewardDistributors[tokenAddress] != address(0)) {
            revert Errors.RescueNotAllowed();
        }
        emit Recovered(tokenAddress, tokenAmount);
        IERC20(tokenAddress).safeTransfer(to, tokenAmount);
    }

    /**
     * @notice Get the timestamp of the end of the rewards period for a given staking token.
     * @param stakingToken The address of the staking token.
     * @return The timestamp of the end of the rewards period.
     */
    function periodFinish(address stakingToken) external view returns (uint256) {
        return _periodFinish[stakingToken];
    }

    /**
     * @notice Gets the reward rate for a given staking token.
     * @param stakingToken The address of the staking token.
     * @return The reward rate of the given staking token.
     */
    function rewardRate(address stakingToken) external view returns (uint256) {
        return _rewardRate[stakingToken];
    }

    /**
     * @notice Gets the rewards duration for a given staking token.
     * @param stakingToken The address of the staking token.
     * @return The rewards duration of the given staking token.
     */
    function rewardsDuration(address stakingToken) external view returns (uint256) {
        return _rewardsDuration[stakingToken];
    }

    /**
     * @notice Gets the last update time for a given staking token.
     * @param stakingToken The address of the staking token.
     * @return The last update time of the given staking token.
     */
    function lastUpdateTime(address stakingToken) external view returns (uint256) {
        return _lastUpdateTime[stakingToken];
    }

    /**
     * @notice Gets the stored reward per token for a given staking token.
     * @param stakingToken The address of the staking token.
     * @return The stored reward per token of the given staking token.
     */
    function rewardPerTokenStored(address stakingToken) external view returns (uint256) {
        return _rewardPerTokenStored[stakingToken];
    }

    /**
     * @notice Gets the user's reward per token paid for a given staking token.
     * @param user The address of the user.
     * @param stakingToken The address of the staking token.
     * @return The reward per token paid to the user for the given staking token.
     */
    function userRewardPerTokenPaid(address user, address stakingToken) external view returns (uint256) {
        return _userRewardPerTokenPaid[user][stakingToken];
    }

    /**
     * @notice Gets the stored pending rewards for a user for a given staking token.
     * @param user The address of the user.
     * @param stakingToken The address of the staking token.
     * @return The stored pending rewards of the user for the given staking token.
     */
    function rewards(address user, address stakingToken) external view returns (uint256) {
        return _rewards[user][stakingToken];
    }

    /**
     * @notice Gets the reward distributor for a given staking token.
     * @param stakingToken The address of the staking token.
     * @return The address of the reward distributor for the given staking token.
     */
    function rewardDistributors(address stakingToken) external view returns (address) {
        return _rewardDistributors[stakingToken];
    }

    /**
     * @notice Gets the total checkedpoint amount of the given staking token.
     * @param stakingToken The address of the staking token.
     * @return The total checkpointed amount of the given staking token.
     */
    function totalSupply(address stakingToken) external view returns (uint256) {
        return _totalSupply[stakingToken];
    }

    /**
     * @notice Gets the checkpointed balance of a user for a given staking token.
     * @param user The address of the user.
     * @param stakingToken The address of the staking token.
     * @return The checkpointed balance of the user for the given staking token.
     */
    function balanceOf(address user, address stakingToken) external view returns (uint256) {
        return _balances[user][stakingToken];
    }

    /**
     * @notice Calculates the total reward for a given duration for a staking token.
     * @param stakingToken The address of the staking token.
     * @return The total reward for the given duration.
     */
    function getRewardForDuration(address stakingToken) external view returns (uint256) {
        return _rewardRate[stakingToken] * _rewardsDuration[stakingToken];
    }

    /**
     * @notice Returns the address of the rewards token.
     * @return The address of the rewards token.
     */
    function rewardToken() external view returns (address) {
        return _REWARDS_TOKEN;
    }

    /**
     * @notice Returns the address of the staking delegate.
     * @return The address of the staking delegate.
     */
    function stakingDelegate() external view returns (address) {
        return _STAKING_DELEGATE;
    }

    /**
     * @notice Calculates the last time a reward was applicable for the given staking token.
     * @param stakingToken The address of the staking token.
     * @return The last applicable timestamp for rewards.
     */
    function lastTimeRewardApplicable(address stakingToken) public view returns (uint256) {
        uint256 finish = _periodFinish[stakingToken];
        // slither-disable-next-line timestamp
        return block.timestamp < finish ? block.timestamp : finish;
    }

    /**
     * @notice Calculates the accumulated reward per token stored.
     * @param stakingToken The address of the staking token.
     * @return The accumulated reward per token.
     */
    function rewardPerToken(address stakingToken) public view returns (uint256) {
        uint256 storedTotalSupply = _totalSupply[stakingToken];
        if (storedTotalSupply == 0) {
            return _rewardPerTokenStored[stakingToken];
        }
        return _rewardPerTokenStored[stakingToken]
            + (lastTimeRewardApplicable(stakingToken) - _lastUpdateTime[stakingToken]) * _rewardRate[stakingToken] * 1e18
                / storedTotalSupply;
    }

    /**
     * @notice Calculates the amount of reward earned by an account for a given staking token.
     * @param account The address of the user's account.
     * @param stakingToken The address of the staking token.
     * @return The amount of reward earned.
     */
    function earned(address account, address stakingToken) public view returns (uint256) {
        return _rewards[account][stakingToken]
            + (
                _balances[account][stakingToken]
                    * (rewardPerToken(stakingToken) - _userRewardPerTokenPaid[account][stakingToken]) / 1e18
            );
    }

    /**
     * @notice Updates the reward state for a given user and staking token.
     * @param user The address of the user to update rewards for.
     * @param stakingToken The address of the staking token.
     */
    function _getReward(address user, address stakingToken) internal {
        _updateReward(user, stakingToken);
        uint256 reward = _rewards[user][stakingToken];
        if (reward > 0) {
            _rewards[user][stakingToken] = 0;
            IERC20(_REWARDS_TOKEN).safeTransfer(user, reward);
            emit RewardPaid(user, stakingToken, reward);
        }
    }

    /**
     * @dev Updates reward state for a given user and staking token.
     * @param account The address of the user to update rewards for.
     * @param stakingToken The address of the staking token.
     */
    function _updateReward(address account, address stakingToken) internal {
        _rewardPerTokenStored[stakingToken] = rewardPerToken(stakingToken);
        _lastUpdateTime[stakingToken] = lastTimeRewardApplicable(stakingToken);
        if (account != address(0)) {
            _rewards[account][stakingToken] = earned(account, stakingToken);
            _userRewardPerTokenPaid[account][stakingToken] = _rewardPerTokenStored[stakingToken];
        }
    }
}

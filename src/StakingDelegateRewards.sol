// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IStakingDelegateRewards } from "src/interfaces/IStakingDelegateRewards.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";

/**
 * @title Staking Delegate Rewards
 * @notice Contract for managing staking rewards with functionality to update balances, notify new rewards, and recover
 * tokens.
 * @dev Inherits from IStakingDelegateRewards and AccessControlEnumerable.
 */
contract StakingDelegateRewards is IStakingDelegateRewards, AccessControlEnumerable {
    // Libraries
    using SafeERC20 for IERC20;

    // Constants
    /// @dev Default duration of rewards period in seconds (7 days).
    uint256 private constant _DEFAULT_DURATION = 7 days;
    /// @dev Role identifier used for protecting functions with timelock access.
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    // slither-disable-start naming-convention
    /// @dev Address of the token used for rewards, immutable.
    address private immutable _REWARDS_TOKEN;
    /// @dev Address of the staking delegate, immutable.
    address private immutable _STAKING_DELEGATE;
    // slither-disable-end naming-convention

    // State variables
    /// @dev Mapping of staking tokens to the period end timestamp.
    mapping(address => uint256) public periodFinish;
    /// @dev Mapping of staking tokens to their respective reward rate.
    mapping(address => uint256) public rewardRate;
    /// @dev Mapping of staking tokens to their rewards duration.
    mapping(address => uint256) public rewardsDuration;
    /// @dev Mapping of staking tokens to the last update time for rewards.
    mapping(address => uint256) public lastUpdateTime;
    /// @dev Mapping of staking tokens to the accumulated reward per token.
    mapping(address => uint256) public rewardPerTokenStored;
    /// @dev Mapping of staking tokens to the leftover rewards.
    mapping(address => uint256) public leftOver;
    /// @dev Mapping of staking tokens and users to the paid-out reward per token.
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;
    /// @dev Mapping of staking tokens and users to their respective rewards.
    mapping(address => mapping(address => uint256)) public rewards;
    /// @dev Mapping of staking tokens to their reward distributors.
    mapping(address => address) public rewardDistributors;
    /// @dev Mapping of users to their designated reward receivers.
    mapping(address => address) public rewardReceiver;

    // Events
    /**
     * @notice Emitted when rewards are added for a staking token.
     * @param stakingToken The staking token for which rewards are added.
     * @param rewardAmount The amount of rewards added.
     * @param rewardRate The rate at which rewards will be distributed.
     * @param start The start time of the reward period.
     * @param end The end time of the reward period.
     */
    event RewardAdded(
        address indexed stakingToken, uint256 rewardAmount, uint256 rewardRate, uint256 start, uint256 end
    );
    /**
     * @notice Emitted when a staking token is added to the rewards program.
     * @param stakingToken The staking token that was added.
     * @param rewardDistributioner The address authorized to distribute rewards for the staking token.
     */
    event StakingTokenAdded(address indexed stakingToken, address rewardDistributioner);
    /**
     * @notice Emitted when a user's balance is updated for a staking token.
     * @param user The user whose balance was updated.
     * @param stakingToken The staking token for which the balance was updated.
     */
    event UserBalanceUpdated(address indexed user, address indexed stakingToken);
    /**
     * @notice Emitted when rewards are paid out to a user for a staking token.
     * @param user The user who received the rewards.
     * @param stakingToken The staking token for which the rewards were paid.
     * @param reward The amount of rewards paid.
     * @param receiver The address that received the rewards.
     */
    event RewardPaid(address indexed user, address indexed stakingToken, uint256 reward, address receiver);
    /**
     * @notice Emitted when the rewards duration is updated for a staking token.
     * @param stakingToken The staking token for which the duration was updated.
     * @param newDuration The new duration for rewards.
     */
    event RewardsDurationUpdated(address indexed stakingToken, uint256 newDuration);
    /**
     * @notice Emitted when tokens are recovered from the contract.
     * @param token The address of the token that was recovered.
     * @param amount The amount of the token that was recovered.
     */
    event Recovered(address token, uint256 amount);
    /**
     * @notice Emitted when a user sets a reward receiver address.
     * @param user The user who set the reward receiver.
     * @param receiver The address set as the reward receiver.
     */
    event RewardReceiverSet(address indexed user, address receiver);

    /**
     * @notice Constructor that sets the rewards token and staking delegate addresses.
     * @param rewardsToken_ The ERC20 token to be used as the rewards token.
     * @param stakingDelegate_ The address of the staking delegate contract.
     */
    // slither-disable-next-line locked-ether
    constructor(address rewardsToken_, address stakingDelegate_, address admin, address timeLock) payable {
        // Checks
        // Check for zero addresses
        if (rewardsToken_ == address(0) || stakingDelegate_ == address(0)) {
            revert Errors.ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TIMELOCK_ROLE, timeLock); // This role must be revoked after granting it to the timelock
        _setRoleAdmin(TIMELOCK_ROLE, TIMELOCK_ROLE); // Only those with the timelock role can grant the timelock role
        _REWARDS_TOKEN = rewardsToken_;
        _STAKING_DELEGATE = stakingDelegate_;
    }

    /**
     * @notice Claims reward for a given staking token.
     * @param stakingToken The address of the staking token.
     */
    function getReward(address stakingToken) external {
        _getReward(msg.sender, stakingToken);
    }

    /**
     * @notice Claims reward for a given user and staking token.
     * @param user The address of the user to claim rewards for.
     * @param stakingToken The address of the staking token.
     */
    function getReward(address user, address stakingToken) external {
        _getReward(user, stakingToken);
    }

    /**
     * @notice Sets the reward receiver who will receive your rewards instead.
     * @dev This can be set to the zero address to receive rewards directly.
     * @param receiver The address of the reward receiver.
     */
    function setRewardReceiver(address receiver) external {
        rewardReceiver[msg.sender] = receiver;
        emit RewardReceiverSet(msg.sender, receiver);
    }

    /**
     * @notice Notifies a new reward amount for a given staking token.
     * @param stakingToken The address of the staking token to notify the reward for.
     * @param reward The amount of the new reward.
     */
    function notifyRewardAmount(address stakingToken, uint256 reward) external {
        if (msg.sender != rewardDistributors[stakingToken]) {
            revert Errors.OnlyRewardDistributorCanNotifyRewardAmount();
        }
        _updateReward(address(0), stakingToken);

        uint256 periodFinish_ = periodFinish[stakingToken];
        // slither-disable-next-line similar-names
        uint256 rewardDuration_ = rewardsDuration[stakingToken];
        uint256 leftOverRewards = leftOver[stakingToken];
        // slither-disable-next-line timestamp
        if (block.timestamp < periodFinish_) {
            uint256 remainingTime = periodFinish_ - block.timestamp;
            leftOverRewards = leftOverRewards + (remainingTime * rewardRate[stakingToken]);
        }
        uint256 newRewardAmount = reward + leftOverRewards;
        uint256 newRewardRate = newRewardAmount / rewardDuration_;
        // slither-disable-next-line incorrect-equality
        if (newRewardRate == 0) {
            revert Errors.RewardRateTooLow();
        }
        uint256 newPeriodFinish = block.timestamp + rewardDuration_;
        emit RewardAdded(stakingToken, reward, newRewardRate, block.timestamp, newPeriodFinish);
        rewardRate[stakingToken] = newRewardRate;
        lastUpdateTime[stakingToken] = block.timestamp;
        periodFinish[stakingToken] = newPeriodFinish;
        // slither-disable-next-line weak-prng
        leftOver[stakingToken] = newRewardAmount % rewardDuration_;
        IERC20(_REWARDS_TOKEN).safeTransferFrom(msg.sender, address(this), reward);
    }

    /**
     * @notice Updates the balance of a user for a given staking token.
     * @param user The address of the user to update the balance for.
     * @param stakingToken The address of the staking token.
     * @param currentUserBalance The current balance of staking token of the user.
     * @param currentTotalDeposited The current total deposited amount of the staking token.
     */
    function updateUserBalance(
        address user,
        address stakingToken,
        uint256 currentUserBalance,
        uint256 currentTotalDeposited
    )
        external
    {
        if (msg.sender != _STAKING_DELEGATE) {
            revert Errors.OnlyStakingDelegateCanUpdateUserBalance();
        }
        _updateReward(user, stakingToken, currentUserBalance, currentTotalDeposited);
        emit UserBalanceUpdated(user, stakingToken);
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
        if (rewardDistributors[stakingToken] != address(0)) {
            revert Errors.StakingTokenAlreadyAdded();
        }
        rewardDistributors[stakingToken] = rewardDistributioner;
        rewardsDuration[stakingToken] = _DEFAULT_DURATION;
        emit StakingTokenAdded(stakingToken, rewardDistributioner);
        emit RewardsDurationUpdated(stakingToken, _DEFAULT_DURATION);
    }

    /**
     * @notice Sets the duration of the rewards period for a given staking token.
     * @param stakingToken The address of the staking token to set the rewards duration for.
     * @param rewardsDuration_ The new duration of the rewards period.
     */
    function setRewardsDuration(address stakingToken, uint256 rewardsDuration_) external onlyRole(TIMELOCK_ROLE) {
        if (rewardsDuration_ == 0) {
            revert Errors.RewardDurationCannotBeZero();
        }
        if (rewardsDuration[stakingToken] == 0) {
            revert Errors.StakingTokenNotAdded();
        }
        // slither-disable-next-line timestamp
        if (block.timestamp <= periodFinish[stakingToken]) {
            revert Errors.PreviousRewardsPeriodNotCompleted();
        }
        rewardsDuration[stakingToken] = rewardsDuration_;
        emit RewardsDurationUpdated(stakingToken, rewardsDuration_);
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
        if (tokenAddress == _REWARDS_TOKEN || rewardDistributors[tokenAddress] != address(0)) {
            revert Errors.RescueNotAllowed();
        }
        emit Recovered(tokenAddress, tokenAmount);
        IERC20(tokenAddress).safeTransfer(to, tokenAmount);
    }

    /**
     * @notice Calculates the total reward for a given duration for a staking token.
     * @param stakingToken The address of the staking token.
     * @return The total reward for the given duration.
     */
    function getRewardForDuration(address stakingToken) external view returns (uint256) {
        return rewardRate[stakingToken] * rewardsDuration[stakingToken];
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
        uint256 finish = periodFinish[stakingToken];
        // slither-disable-next-line timestamp
        return block.timestamp < finish ? block.timestamp : finish;
    }

    /**
     * @notice Calculates the accumulated reward per token stored.
     * @param stakingToken The address of the staking token.
     * @return The accumulated reward per token.
     */
    function rewardPerToken(address stakingToken) external view returns (uint256) {
        return _rewardPerToken(stakingToken, IYearnStakingDelegate(_STAKING_DELEGATE).totalDeposited(stakingToken));
    }

    function _rewardPerToken(address stakingToken, uint256 currentTotalDeposited) internal view returns (uint256) {
        if (currentTotalDeposited == 0) {
            return rewardPerTokenStored[stakingToken];
        }
        return rewardPerTokenStored[stakingToken]
            + (lastTimeRewardApplicable(stakingToken) - lastUpdateTime[stakingToken]) * rewardRate[stakingToken] * 1e18
                / currentTotalDeposited;
    }

    /**
     * @notice Calculates the amount of reward earned by an account for a given staking token.
     * @param account The address of the user's account.
     * @param stakingToken The address of the staking token.
     * @return The amount of reward earned.
     */
    function earned(address account, address stakingToken) external view returns (uint256) {
        return _earned(
            account,
            stakingToken,
            IYearnStakingDelegate(_STAKING_DELEGATE).balanceOf(account, stakingToken),
            _rewardPerToken(stakingToken, IYearnStakingDelegate(_STAKING_DELEGATE).totalDeposited(stakingToken))
        );
    }

    function _earned(
        address account,
        address stakingToken,
        uint256 userBalance,
        uint256 rewardPerToken_
    )
        internal
        view
        returns (uint256)
    {
        return rewards[account][stakingToken]
            + (userBalance * (rewardPerToken_ - userRewardPerTokenPaid[account][stakingToken]) / 1e18);
    }

    /**
     * @notice Updates the reward state for a given user and staking token. If there are any rewards to be paid out,
     * they are sent to the receiver that was set by the user. (Defaults to the user's address if not set)
     * @param user The address of the user to update rewards for.
     * @param stakingToken The address of the staking token.
     */
    function _getReward(address user, address stakingToken) internal {
        _updateReward(user, stakingToken);
        uint256 reward = rewards[user][stakingToken];
        if (reward > 0) {
            rewards[user][stakingToken] = 0;
            address receiver = rewardReceiver[user];
            if (receiver == address(0)) {
                receiver = user;
            }
            emit RewardPaid(user, stakingToken, reward, receiver);
            IERC20(_REWARDS_TOKEN).safeTransfer(receiver, reward);
        }
    }

    function _updateReward(address account, address stakingToken) internal {
        _updateReward(
            account,
            stakingToken,
            IYearnStakingDelegate(_STAKING_DELEGATE).balanceOf(account, stakingToken),
            IYearnStakingDelegate(_STAKING_DELEGATE).totalDeposited(stakingToken)
        );
    }

    /**
     * @dev Updates reward state for a given user and staking token.
     * @param account The address of the user to update rewards for.
     * @param stakingToken The address of the staking token.
     */
    function _updateReward(
        address account,
        address stakingToken,
        uint256 currentUserBalance,
        uint256 currentTotalDeposited
    )
        internal
    {
        uint256 rewardPerToken_ = _rewardPerToken(stakingToken, currentTotalDeposited);
        rewardPerTokenStored[stakingToken] = rewardPerToken_;
        lastUpdateTime[stakingToken] = lastTimeRewardApplicable(stakingToken);
        if (account != address(0)) {
            rewards[account][stakingToken] = _earned(account, stakingToken, currentUserBalance, rewardPerToken_);
            userRewardPerTokenPaid[account][stakingToken] = rewardPerTokenStored[stakingToken];
        }
    }
}

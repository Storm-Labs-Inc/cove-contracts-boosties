// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IStakingDelegateRewards } from "src/interfaces/deps/yearn/veYFI/IStakingDelegateRewards.sol";

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

    function lastTimeRewardApplicable(address stakingToken) public view returns (uint256) {
        uint256 finish = periodFinish[stakingToken];
        // slither-disable-next-line timestamp
        return block.timestamp < finish ? block.timestamp : finish;
    }

    function rewardPerToken(address stakingToken) public view returns (uint256) {
        uint256 totalSupply_ = totalSupply[stakingToken];
        if (totalSupply_ == 0) {
            return rewardPerTokenStored[stakingToken];
        }
        return rewardPerTokenStored[stakingToken]
            + (lastTimeRewardApplicable(stakingToken) - lastUpdateTime[stakingToken]) * rewardRate[stakingToken] * 1e18
                / totalSupply_;
    }

    function earned(address account, address stakingToken) public view returns (uint256) {
        return rewards[account][stakingToken]
            + (
                balanceOf[account][stakingToken]
                    * (rewardPerToken(stakingToken) - userRewardPerTokenPaid[account][stakingToken]) / 1e18
            );
    }

    function getRewardForDuration(address stakingToken) external view returns (uint256) {
        return rewardRate[stakingToken] * rewardsDuration[stakingToken];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function getReward(address stakingToken) public nonReentrant {
        _updateReward(msg.sender, stakingToken);
        uint256 reward = rewards[msg.sender][stakingToken];
        if (reward > 0) {
            rewards[msg.sender][stakingToken] = 0;
            IERC20(_REWARDS_TOKEN).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, stakingToken, reward);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */
    function updateUserBalance(address stakingToken, address user, uint256 totalAmount) external nonReentrant {
        if (msg.sender != _STAKING_DELEGATE) {
            revert Errors.OnlyStakingDelegateCanUpdateUserBalance();
        }
        _updateReward(user, stakingToken);
        uint256 currentUserBalance = balanceOf[user][stakingToken];
        balanceOf[user][stakingToken] = totalAmount;
        totalSupply[stakingToken] = totalSupply[stakingToken] - currentUserBalance + totalAmount;
        emit UserBalanceUpdated(user, stakingToken, totalAmount);
    }

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

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(
        address tokenAddress,
        address to,
        uint256 tokenAmount
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (tokenAddress == _REWARDS_TOKEN || rewardDistributors[tokenAddress] != address(0)) {
            revert Errors.CannotWithdrawStakingToken();
        }
        emit Recovered(tokenAddress, tokenAmount);
        IERC20(tokenAddress).safeTransfer(to, tokenAmount);
    }

    function setRewardsDuration(address stakingToken, uint256 rewardsDuration_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // slither-disable-next-line timestamp
        if (block.timestamp <= periodFinish[stakingToken]) {
            revert Errors.PreviousRewardsPeriodNotCompleted();
        }
        rewardsDuration[stakingToken] = rewardsDuration_;
        emit RewardsDurationUpdated(stakingToken, rewardsDuration_);
    }

    /* ========== MODIFIERS ========== */

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

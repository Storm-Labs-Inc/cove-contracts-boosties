// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingDelegateRewards is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */
    bytes32 constant _STAKING_DELEGATE_ROLE = keccak256("STAKING_DELEGATE_ROLE");

    address immutable _REWARDS_TOKEN;
    address immutable _STAKING_DELEGATE;

    mapping(address => bool) public isStakingToken;
    mapping(address => uint256) public periodFinish;
    mapping(address => uint256) public rewardRate;
    mapping(address => uint256) public rewardsDuration;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public rewardPerTokenStored;
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public rewards;
    mapping(address => address) public rewardDistributioners;
    mapping(address => uint256) private _totalSupply;
    mapping(address => mapping(address => uint256)) private _balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _rewardsToken, address _stakingDelegate) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _REWARDS_TOKEN = _rewardsToken;
        _STAKING_DELEGATE = _stakingDelegate;
    }

    /* ========== VIEWS ========== */

    function totalSupply(address stakingToken) external view returns (uint256) {
        return _totalSupply[stakingToken];
    }

    function balanceOf(address account, address stakingToken) external view returns (uint256) {
        return _balances[account][stakingToken];
    }

    function lastTimeRewardApplicable(address stakingToken) public view returns (uint256) {
        uint256 finish = periodFinish[stakingToken];
        return block.timestamp < finish ? block.timestamp : finish;
    }

    function rewardPerToken(address stakingToken) public view returns (uint256) {
        if (_totalSupply[stakingToken] == 0) {
            return rewardPerTokenStored[stakingToken];
        }
        return rewardPerTokenStored[stakingToken]
            + (lastTimeRewardApplicable(stakingToken) - lastUpdateTime[stakingToken]) * rewardRate[stakingToken] * 1e18
                / _totalSupply[stakingToken];
    }

    function earned(address account, address stakingToken) public view returns (uint256) {
        return rewards[account][stakingToken]
            + (
                _balances[account][stakingToken]
                    * (rewardPerToken(stakingToken) - userRewardPerTokenPaid[account][stakingToken]) / 1e18
            );
    }

    function getRewardForDuration(address stakingToken) external view returns (uint256) {
        return rewardRate[stakingToken] * rewardsDuration[stakingToken];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function getReward(address stakingToken) public nonReentrant returns (uint256) {
        _updateReward(msg.sender, stakingToken);
        uint256 reward = rewards[msg.sender][stakingToken];
        if (reward > 0) {
            rewards[msg.sender][stakingToken] = 0;
            IERC20(_REWARDS_TOKEN).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, stakingToken, reward);
        }
        return reward;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */
    function updateUserBalance(address stakingToken, address user, uint256 totalAmount) external nonReentrant {
        if (msg.sender != _STAKING_DELEGATE) {
            revert("Only the staking delegate can update a user's balance");
        }
        _updateReward(user, stakingToken);
        uint256 currentUserBalance = _balances[user][stakingToken];
        _balances[user][stakingToken] = totalAmount;
        _totalSupply[stakingToken] = _totalSupply[stakingToken] - currentUserBalance + totalAmount;
        emit UserBalanceUpdated(user, stakingToken, totalAmount);
    }

    function addStakingToken(address stakingToken, address rewardDistributioner) external {
        if (msg.sender != _STAKING_DELEGATE) {
            revert("Only the staking delegate can add a staking token");
        }
        isStakingToken[stakingToken] = true;
        rewardDistributioners[stakingToken] = rewardDistributioner;
        rewardsDuration[stakingToken] = 7 days;
    }

    function notifyRewardAmount(address stakingToken, uint256 reward) external nonReentrant {
        if (msg.sender != rewardDistributioners[stakingToken]) {
            revert("Only the reward distributioner can notify the reward amount");
        }
        _updateReward(address(0), stakingToken);

        if (block.timestamp >= periodFinish[stakingToken]) {
            rewardRate[stakingToken] = reward / rewardsDuration[stakingToken];
        } else {
            uint256 remaining = periodFinish[stakingToken] - block.timestamp;
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
        require(tokenAddress != _REWARDS_TOKEN, "Cannot withdraw the staking token");
        require(!isStakingToken[tokenAddress], "Cannot withdraw a token that is a staking token");
        IERC20(tokenAddress).safeTransfer(to, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardsDuration(address stakingToken, uint256 _rewardsDuration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            block.timestamp > periodFinish[stakingToken],
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration[stakingToken] = _rewardsDuration;
        emit RewardsDurationUpdated(stakingToken, rewardsDuration[stakingToken]);
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
    event UserBalanceUpdated(address indexed user, address indexed stakingToken, uint256 amount);
    event RewardPaid(address indexed user, address indexed stakingToken, uint256 reward);
    event RewardsDurationUpdated(address indexed stakingToken, uint256 newDuration);
    event Recovered(address token, uint256 amount);
}

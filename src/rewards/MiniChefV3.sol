// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IMiniChefV3Rewarder } from "src/interfaces/rewards/IMiniChefV3Rewarder.sol";
import { SelfPermit } from "src/deps/uniswap/v3-periphery/base/SelfPermit.sol";
import { Rescuable } from "src/Rescuable.sol";
import { Errors } from "src/libraries/Errors.sol";

contract MiniChefV3 is Multicall, AccessControl, Rescuable, SelfPermit {
    using SafeERC20 for IERC20;

    /// @notice Info of each MCV3 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of REWARD_TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /// @notice Info of each MCV3 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of REWARD_TOKEN to distribute per block.
    struct PoolInfo {
        uint128 accRewardPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }

    /// @notice Address of REWARD_TOKEN contract.
    IERC20 public immutable REWARD_TOKEN;

    /// @notice Info of each MCV3 pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each MCV3 pool.
    IERC20[] public lpToken;
    /// @notice Total amount of LP token staked in each MCV3 pool.
    uint256[] public lpSupply;
    /// @notice Address of each `IRewarder` contract in MCV3.
    IMiniChefV3Rewarder[] public rewarder;

    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @dev PID of the LP token plus one.
    mapping(address => uint256) private _pidPlusOne;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    /// @notice The amount of REWARD_TOKEN distributed per second.
    uint256 public rewardPerSecond;
    /// @notice The amount of REWARD_TOKEN available in this contract for distribution.
    uint256 public availableReward;
    uint256 private constant _ACC_REWARD_TOKEN_PRECISION = 1e12;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(
        uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IMiniChefV3Rewarder indexed rewarder
    );
    event LogSetPool(uint256 indexed pid, uint256 allocPoint, IMiniChefV3Rewarder indexed rewarder, bool overwrite);
    event LogUpdatePool(uint256 indexed pid, uint64 lastRewardTime, uint256 lpSupply, uint256 accRewardPerShare);
    event LogRewardPerSecond(uint256 rewardPerSecond);

    /// @param rewardToken_ The reward token contract address.
    constructor(IERC20 rewardToken_, address admin) {
        REWARD_TOKEN = rewardToken_;
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Returns the number of MCV3 pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    function pidOfLPToken(IERC20 lpToken_) external view returns (uint256 pid) {
        uint256 pidPlusOne = _pidPlusOne[address(lpToken_)];
        if (pidPlusOne == 0) {
            revert Errors.InvalidLPToken();
        }
        unchecked {
            pid = pidPlusOne - 1;
        }
    }

    function isLPTokenAdded(IERC20 lpToken_) external view returns (bool added) {
        added = _pidPlusOne[address(lpToken_)] != 0;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    /// @param _rewarder Address of the rewarder delegate.
    function add(
        uint256 allocPoint,
        IERC20 _lpToken,
        IMiniChefV3Rewarder _rewarder
    )
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_pidPlusOne[address(_lpToken)] != 0) {
            revert Errors.LPTokenAlreadyAdded();
        }
        totalAllocPoint += allocPoint;
        lpToken.push(_lpToken);
        lpSupply.push(0);
        rewarder.push(_rewarder);
        poolInfo.push(
            PoolInfo({ allocPoint: uint64(allocPoint), lastRewardTime: uint64(block.timestamp), accRewardPerShare: 0 })
        );
        uint256 pid = poolInfo.length - 1;
        _pidPlusOne[address(_lpToken)] = pid + 1;
        emit LogPoolAddition(pid, allocPoint, _lpToken, _rewarder);
    }

    /// @notice Update the given pool's REWARD_TOKEN allocation point and `IRewarder` contract. Can only be called by
    /// the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    /// @param _rewarder Address of the rewarder delegate.
    /// @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        IMiniChefV3Rewarder _rewarder,
        bool overwrite
    )
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = uint64(_allocPoint);
        if (overwrite) {
            rewarder[_pid] = _rewarder;
        }
        emit LogSetPool(_pid, _allocPoint, overwrite ? _rewarder : rewarder[_pid], overwrite);
    }

    /// @notice Rescue ERC20 tokens from the contract.
    /// @param token The address of the ERC20 token to rescue.
    /// @param to The address to send the rescued tokens to.
    /// @param amount The amount of tokens to rescue.
    /// @dev Rescue is only allowed when there is a discrepancy between balanceOf this and lpSupply.
    function rescue(IERC20 token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 pidPlusOne = _pidPlusOne[address(token)];
        uint256 availableForRescue = token.balanceOf(address(this));
        if (pidPlusOne != 0) {
            availableForRescue -= lpSupply[pidPlusOne - 1];
        }
        // Consider the special case where token is the reward token.
        if (token == REWARD_TOKEN) {
            availableForRescue -= availableReward;
        }
        if (amount > availableForRescue) {
            revert Errors.InsufficientBalance();
        }
        if (amount != 0) {
            _rescue(token, to, amount);
        }
    }

    /// @notice Sets the reward per second to be distributed. Can only be called by the owner.
    /// @param rewardPerSecond_ The amount of reward token to be distributed per second.
    function setRewardPerSecond(uint256 rewardPerSecond_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        rewardPerSecond = rewardPerSecond_;
        emit LogRewardPerSecond(rewardPerSecond_);
    }

    /// @notice Commits REWARD_TOKEN to the contract for distribution.
    /// @param amount The amount of REWARD_TOKEN to commit.
    function commmitReward(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        availableReward += amount;
        REWARD_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice View function to see pending REWARD_TOKEN on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending REWARD_TOKEN reward for a given user.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply_ = lpSupply[_pid];
        uint256 totalAllocPoint_ = totalAllocPoint;
        if (block.timestamp > pool.lastRewardTime && lpSupply_ != 0 && totalAllocPoint_ != 0) {
            uint256 time = block.timestamp - pool.lastRewardTime;
            uint256 rewardAmount = time * rewardPerSecond * pool.allocPoint / totalAllocPoint_;
            accRewardPerShare += rewardAmount * _ACC_REWARD_TOKEN_PRECISION / lpSupply_;
        }
        pending = (user.amount * accRewardPerShare / _ACC_REWARD_TOKEN_PRECISION) - user.rewardDebt + user.unpaidRewards;
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardTime) {
            uint256 lpSupply_ = lpSupply[pid];
            uint256 totalAllocPoint_ = totalAllocPoint;
            if (lpSupply_ != 0 && totalAllocPoint_ != 0) {
                uint256 time = block.timestamp - pool.lastRewardTime;
                uint256 rewardAmount = time * rewardPerSecond * pool.allocPoint / totalAllocPoint_;
                pool.accRewardPerShare += uint128(rewardAmount * _ACC_REWARD_TOKEN_PRECISION / lpSupply_);
            }
            pool.lastRewardTime = uint64(block.timestamp);
            poolInfo[pid] = pool;
            emit LogUpdatePool(pid, pool.lastRewardTime, lpSupply_, pool.accRewardPerShare);
        }
    }

    /// @notice Deposit LP tokens to MCV3 for REWARD_TOKEN allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(uint256 pid, uint256 amount, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][to];

        // Effects
        user.amount += amount;
        user.rewardDebt += amount * pool.accRewardPerShare / _ACC_REWARD_TOKEN_PRECISION;
        lpSupply[pid] += amount;

        // Interactions
        lpToken[pid].safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, pid, amount, to);

        IMiniChefV3Rewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, to, to, 0, user.amount);
        }
    }

    /// @notice Withdraw LP tokens from MCV3.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(uint256 pid, uint256 amount, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        // Effects
        user.rewardDebt -= amount * pool.accRewardPerShare / _ACC_REWARD_TOKEN_PRECISION;
        user.amount -= amount;
        lpSupply[pid] -= amount;

        // Interactions
        lpToken[pid].safeTransfer(to, amount);
        emit Withdraw(msg.sender, pid, amount, to);

        IMiniChefV3Rewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, 0, user.amount);
        }
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of REWARD_TOKEN rewards.
    function harvest(uint256 pid, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 accumulatedReward = user.amount * pool.accRewardPerShare / _ACC_REWARD_TOKEN_PRECISION;
        uint256 pendingReward_ = accumulatedReward - user.rewardDebt + user.unpaidRewards;

        // Effects
        user.rewardDebt = accumulatedReward;

        // Interactions
        uint256 rewardAmount = 0;
        if (pendingReward_ != 0) {
            uint256 availableReward_ = availableReward;
            uint256 unpaidRewards_ = 0;
            rewardAmount = pendingReward_ > availableReward_ ? availableReward_ : pendingReward_;
            /// @dev unchecked is used as the subtraction is guaranteed to not underflow.
            unchecked {
                availableReward -= rewardAmount;
                unpaidRewards_ = pendingReward_ - rewardAmount;
            }
            if (unpaidRewards_ != 0) {
                user.unpaidRewards += unpaidRewards_;
            }
            if (rewardAmount != 0) {
                REWARD_TOKEN.safeTransfer(to, rewardAmount);
            }
        }

        emit Harvest(msg.sender, pid, rewardAmount);

        IMiniChefV3Rewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, pendingReward_, user.amount);
        }
    }

    /// @notice Withdraw LP tokens from MCV3 and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and REWARD_TOKEN rewards.
    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 accumulatedReward = user.amount * pool.accRewardPerShare / _ACC_REWARD_TOKEN_PRECISION;
        uint256 pendingReward_ = accumulatedReward - user.rewardDebt + user.unpaidRewards;

        // Effects
        user.rewardDebt = accumulatedReward - (amount * pool.accRewardPerShare / _ACC_REWARD_TOKEN_PRECISION);
        user.amount -= amount;
        lpSupply[pid] -= amount;

        // Interactions
        uint256 rewardAmount = 0;
        if (pendingReward_ != 0) {
            uint256 availableReward_ = availableReward;
            uint256 unpaidRewards_ = 0;
            rewardAmount = pendingReward_ > availableReward_ ? availableReward_ : pendingReward_;
            /// @dev unchecked is used as the subtraction is guaranteed to not underflow.
            unchecked {
                availableReward -= rewardAmount;
                unpaidRewards_ = pendingReward_ - rewardAmount;
            }
            if (unpaidRewards_ != 0) {
                user.unpaidRewards += unpaidRewards_;
            }
            if (rewardAmount != 0) {
                REWARD_TOKEN.safeTransfer(to, rewardAmount);
            }
        }
        emit Harvest(msg.sender, pid, rewardAmount);

        lpToken[pid].safeTransfer(to, amount);
        emit Withdraw(msg.sender, pid, amount, to);

        IMiniChefV3Rewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, pendingReward_, user.amount);
        }
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) public {
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amount = user.amount;

        // Effects
        user.amount = 0;
        user.rewardDebt = 0;
        user.unpaidRewards = 0;
        lpSupply[pid] -= amount;

        // Interactions
        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[pid].safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount, to);

        IMiniChefV3Rewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, 0, 0);
        }
    }
}
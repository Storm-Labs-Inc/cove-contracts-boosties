// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { IMiniChefV3Rewarder } from "src/interfaces/rewards/IMiniChefV3Rewarder.sol";
import { SelfPermit } from "src/deps/uniswap/v3-periphery/base/SelfPermit.sol";
import { Rescuable } from "src/Rescuable.sol";
import { Errors } from "src/libraries/Errors.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title MiniChefV3
 * @notice A contract for managing staking, rewards, and pool information for liquidity providers.
 * @dev This contract handles the logic for staking LP tokens, distributing rewards, and managing pool information.
 * It supports multiple reward tokens through external rewarder contracts and includes emergency withdrawal
 * functionality.  It does not support rebasing or fee on transfer tokens.
 */
contract MiniChefV3 is Multicall, AccessControlEnumerable, Rescuable, SelfPermit, Pausable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        /// @dev The amount of LP tokens the user has deposited into the pool.
        uint256 amount;
        /// @dev The reward debt indicates how much REWARD_TOKEN the user has already been accounted for.
        uint256 rewardDebt;
        /// @dev The amount of REWARD_TOKEN rewards that the user has earned but not yet claimed.
        uint256 unpaidRewards;
    }

    struct PoolInfo {
        /// @dev Accumulated REWARD_TOKENs per share, scaled to precision.
        uint160 accRewardPerShare;
        /// @dev The last timestamp when the pool's rewards were calculated.
        uint64 lastRewardTime;
        /// @dev The number of allocation points assigned to the pool, which determines the share of reward
        /// distribution.
        uint32 allocPoint;
    }

    /// @notice Address of REWARD_TOKEN contract.
    // slither-disable-next-line naming-convention,similar-names
    IERC20 public immutable REWARD_TOKEN;

    /// @notice Info of each MCV3 pool.
    PoolInfo[] private _poolInfo;
    /// @notice Address of the LP token for each MCV3 pool.
    IERC20[] public lpToken;
    /// @notice Total amount of LP token staked in each MCV3 pool.
    uint256[] public lpSupply;
    /// @notice Address of each `IRewarder` contract in MCV3.
    IMiniChefV3Rewarder[] public rewarder;

    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) private _userInfo;

    /// @dev PID of the LP token plus one.
    mapping(address => uint256) private _pidPlusOne;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    /// @notice The amount of REWARD_TOKEN distributed per second.
    uint256 public rewardPerSecond;
    /// @notice The amount of REWARD_TOKEN available in this contract for distribution.
    uint256 public availableReward;
    /// @notice The maximum amount of REWARD_TOKEN that can be distributed per second.
    uint256 public constant MAX_REWARD_TOKEN_PER_SECOND = 100_000_000 ether / uint256(1 weeks);
    /// @dev Precision factor to calculate accumulated reward tokens per share.
    uint256 private constant _ACC_REWARD_TOKEN_PRECISION = 1e12;
    /// @dev The timelock role for the contract.
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    /// @dev The pauser role for the contract.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @notice Emitted when a user deposits LP tokens into a pool.
     * @param user The address of the user making the deposit.
     * @param pid The pool ID into which the deposit is made.
     * @param amount The amount of LP tokens deposited.
     * @param to The address receiving the deposit.
     */
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    /**
     * @notice Emitted when a user withdraws LP tokens from a pool.
     * @param user The address of the user making the withdrawal.
     * @param pid The pool ID from which the withdrawal is made.
     * @param amount The amount of LP tokens withdrawn.
     * @param to The address receiving the withdrawn LP tokens.
     */
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    /**
     * @notice Emitted when a user performs an emergency withdrawal of LP tokens from a pool.
     * @param user The address of the user making the emergency withdrawal.
     * @param pid The pool ID from which the emergency withdrawal is made.
     * @param amount The amount of LP tokens emergency withdrawn.
     * @param to The address receiving the emergency withdrawn LP tokens.
     */
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    /**
     * @notice Emitted when a user harvests reward tokens from a pool.
     * @param user The address of the user performing the harvest.
     * @param pid The pool ID from which the harvest is performed.
     * @param amount The amount of reward tokens harvested.
     */
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    /**
     * @notice Emitted when a new pool is added to the MiniChef contract.
     * @param pid The pool ID of the newly added pool.
     * @param allocPoint The number of allocation points assigned to the new pool.
     * @param lpToken The address of the LP token for the new pool.
     * @param rewarder The address of the rewarder contract for the new pool.
     */
    event LogPoolAddition(
        uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IMiniChefV3Rewarder indexed rewarder
    );
    /**
     * @notice Emitted when a pool's configuration is updated.
     * @param pid The pool ID of the updated pool.
     * @param allocPoint The new number of allocation points assigned to the pool.
     * @param rewarder The address of the rewarder contract for the pool.
     * @param overwrite Indicates whether the update overwrites the existing rewarder contract.
     */
    event LogSetPool(uint256 indexed pid, uint256 allocPoint, IMiniChefV3Rewarder indexed rewarder, bool overwrite);
    /**
     * @notice Emitted when a pool's rewards are updated.
     * @param pid The pool ID of the updated pool.
     * @param lastRewardTime The last timestamp when the pool's rewards were calculated.
     * @param lpSupply The total amount of LP tokens staked in the pool.
     * @param accRewardPerShare The accumulated reward tokens per share, scaled to precision.
     */
    event LogUpdatePool(uint256 indexed pid, uint64 lastRewardTime, uint256 lpSupply, uint256 accRewardPerShare);
    /**
     * @notice Emitted when the reward per second is updated.
     * @param rewardPerSecond The new amount of reward tokens distributed per second.
     */
    event LogRewardPerSecond(uint256 rewardPerSecond);
    /**
     * @notice Emitted when a reward amount is committed for distribution.
     * @param amount The amount of reward tokens committed.
     */
    event LogRewardCommitted(uint256 amount);
    /**
     * @notice Emitted when an emergency withdrawal from a rewarder contract is faulty.
     * @param user The address of the user performing the emergency withdrawal.
     * @param pid The pool ID from which the emergency withdrawal is made.
     * @param amount The amount of tokens emergency withdrawn.
     * @param to The address receiving the emergency withdrawn tokens.
     */
    event LogRewarderEmergencyWithdrawFaulty(
        address indexed user, uint256 indexed pid, uint256 amount, address indexed to
    );

    /**
     * @dev Constructs the MiniChefV3 contract with a specified reward token and admin address.
     * @param rewardToken_ The ERC20 token to be used as the reward token.
     * @param admin The address that will be granted the default admin role.
     */
    constructor(IERC20 rewardToken_, address admin, address pauser) payable {
        if (address(rewardToken_) == address(0) || admin == address(0)) {
            revert Errors.ZeroAddress();
        }
        REWARD_TOKEN = rewardToken_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(TIMELOCK_ROLE, admin); // This role must be revoked after granting it to the timelock
        _setRoleAdmin(TIMELOCK_ROLE, TIMELOCK_ROLE); // Only those with the timelock role can grant the timelock role
    }

    /// @notice Returns the number of MCV3 pools.
    function poolLength() public view returns (uint256 pools) {
        pools = _poolInfo.length;
    }

    /**
     * @notice Retrieves the pool ID of a given LP token.
     * @dev Returns the pool ID by looking up the LP token address in the `_pidPlusOne` mapping.
     * @param lpToken_ The LP token to query the pool ID for.
     * @return pid The pool ID of the given LP token.
     */
    function pidOfLPToken(IERC20 lpToken_) external view returns (uint256 pid) {
        uint256 pidPlusOne = _pidPlusOne[address(lpToken_)];
        // slither-disable-next-line timestamp
        if (pidPlusOne <= 0) {
            revert Errors.InvalidLPToken();
        }
        /// @dev The unchecked block is used here because the subtraction is safe from underflow.
        /// The condition above ensures that `pidPlusOne` is greater than zero, so subtracting one will not underflow.
        unchecked {
            pid = pidPlusOne - 1;
        }
    }

    /**
     * @notice Checks if an LP token has been added to any pool.
     * @dev Returns true if the LP token exists in the `_pidPlusOne` mapping.
     * @param lpToken_ The LP token to check.
     * @return added True if the LP token has been added to a pool.
     */
    function isLPTokenAdded(IERC20 lpToken_) external view returns (bool added) {
        // slither-disable-next-line timestamp
        added = _pidPlusOne[address(lpToken_)] != 0;
    }

    /**
     * @notice Retrieves user information for a specific pool.
     * @dev Returns the user's staked amount, reward debt, and unpaid rewards for a given pool.
     * @param pid The pool ID to retrieve user information for.
     * @param user The user address to retrieve information for.
     * @return info The user's information for the specified pool.
     */
    function getUserInfo(uint256 pid, address user) external view returns (UserInfo memory info) {
        info = _userInfo[pid][user];
    }

    /**
     * @notice Retrieves pool information for a specific pool ID.
     * @dev Returns the pool's accumulated reward per share, last reward time, and allocation points.
     * @param pid The pool ID to retrieve information for.
     * @return info The pool's information.
     */
    function getPoolInfo(uint256 pid) external view returns (PoolInfo memory info) {
        info = _poolInfo[pid];
    }

    /**
     * @notice Add a new LP to the pool. Can only be called by the owner.
     * DO NOT add the same LP token more than once. Rewards will be messed up if you do.
     * @param allocPoint AP of the new pool.
     * @param lpToken_ Address of the LP ERC-20 token.
     * @param rewarder_ Address of the rewarder delegate.
     */
    function add(uint32 allocPoint, IERC20 lpToken_, IMiniChefV3Rewarder rewarder_) public onlyRole(TIMELOCK_ROLE) {
        if (address(lpToken_) == (address(0))) {
            revert Errors.ZeroAddress();
        }
        if (_pidPlusOne[address(lpToken_)] != 0) {
            revert Errors.LPTokenAlreadyAdded();
        }
        totalAllocPoint = totalAllocPoint + allocPoint;
        lpToken.push(lpToken_);
        lpSupply.push(0);
        rewarder.push(rewarder_);
        _poolInfo.push(
            PoolInfo({ allocPoint: allocPoint, lastRewardTime: uint64(block.timestamp), accRewardPerShare: 0 })
        );
        uint256 pid = _poolInfo.length - 1;
        _pidPlusOne[address(lpToken_)] = pid + 1;
        emit LogPoolAddition(pid, allocPoint, lpToken_, rewarder_);
    }

    /**
     * @notice Update the given pool's REWARD_TOKEN allocation point and `IRewarder` contract. Can only be called by
     * the owner.
     * @param pid The index of the pool. See `_poolInfo`.
     * @param allocPoint New AP of the pool.
     * @param lpToken_ Address of the LP ERC-20 token.
     * @param rewarder_ Address of the rewarder delegate.
     * @param overwrite True if rewarder_ should be `set`. Otherwise `rewarder_` is ignored.
     */
    function set(
        uint256 pid,
        uint32 allocPoint,
        IERC20 lpToken_,
        IMiniChefV3Rewarder rewarder_,
        bool overwrite
    )
        public
        onlyRole(TIMELOCK_ROLE)
    {
        uint256 pidPlusOne = _pidPlusOne[address(lpToken_)];
        if (pidPlusOne < 1) {
            revert Errors.LPTokenNotAdded();
        }
        if (pidPlusOne != pid + 1) {
            revert Errors.LPTokenDoesNotMatchPoolId();
        }
        totalAllocPoint = totalAllocPoint - _poolInfo[pid].allocPoint + allocPoint;
        _poolInfo[pid].allocPoint = allocPoint;
        if (overwrite) {
            rewarder[pid] = rewarder_;
        }
        emit LogSetPool(pid, allocPoint, overwrite ? rewarder_ : rewarder[pid], overwrite);
    }

    /*
    * @notice Rescue ERC20 tokens from the contract.
    * @param token The address of the ERC20 token to rescue.
    * @param to The address to send the rescued tokens to.
    * @param amount The amount of tokens to rescue.
    * @dev Rescue is only allowed when there is a discrepancy between balanceOf this and lpSupply.
    */
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

    /**
     * @notice Sets the reward per second to be distributed. Can only be called by the owner.
     * @param rewardPerSecond_ The amount of reward token to be distributed per second.
     */
    function setRewardPerSecond(uint256 rewardPerSecond_) public onlyRole(TIMELOCK_ROLE) {
        if (rewardPerSecond_ > MAX_REWARD_TOKEN_PER_SECOND) {
            revert Errors.RewardRateTooHigh();
        }
        rewardPerSecond = rewardPerSecond_;
        emit LogRewardPerSecond(rewardPerSecond_);
    }

    /**
     * @notice Commits REWARD_TOKEN to the contract for distribution.
     * @param amount The amount of REWARD_TOKEN to commit.
     */
    function commitReward(uint256 amount) external {
        availableReward = availableReward + amount;
        emit LogRewardCommitted(amount);
        REWARD_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice View function to see pending REWARD_TOKEN on frontend.
     * @param pid The index of the pool. See `_poolInfo`.
     * @param user_ Address of user.
     * @return pending REWARD_TOKEN reward for a given user.
     */
    function pendingReward(uint256 pid, address user_) external view returns (uint256 pending) {
        PoolInfo memory pool = _poolInfo[pid];
        UserInfo storage user = _userInfo[pid][user_];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply_ = lpSupply[pid];
        uint256 totalAllocPoint_ = totalAllocPoint;
        // slither-disable-next-line timestamp
        if (block.timestamp > pool.lastRewardTime) {
            if (lpSupply_ != 0) {
                if (totalAllocPoint_ != 0) {
                    // @dev unchecked is used as the subtraction is guaranteed to not underflow because
                    // `block.timestamp` is always greater than `pool.lastRewardTime`.
                    uint256 time;
                    unchecked {
                        time = block.timestamp - pool.lastRewardTime;
                    }
                    // Explicitly round down when calculating the reward
                    // slither-disable-start divide-before-multiply
                    uint256 rewardAmount = time * rewardPerSecond * pool.allocPoint / totalAllocPoint_;
                    accRewardPerShare += rewardAmount * _ACC_REWARD_TOKEN_PRECISION / lpSupply_;
                    // slither-disable-end divide-before-multiply
                }
            }
        }
        pending = (user.amount * accRewardPerShare / _ACC_REWARD_TOKEN_PRECISION) - user.rewardDebt + user.unpaidRewards;
    }

    /**
     * @notice Update reward variables of the given pool.
     * @param pid The index of the pool. See `_poolInfo`.
     * @return pool Returns the pool that was updated.
     */
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = _poolInfo[pid];
        // slither-disable-next-line timestamp
        if (block.timestamp > pool.lastRewardTime) {
            uint256 lpSupply_ = lpSupply[pid];
            uint256 totalAllocPoint_ = totalAllocPoint;
            if (lpSupply_ != 0) {
                if (totalAllocPoint_ != 0) {
                    // @dev unchecked is used as the subtraction is guaranteed to not underflow because
                    // `block.timestamp` is always greater than `pool.lastRewardTime`.
                    uint256 time;
                    unchecked {
                        time = block.timestamp - pool.lastRewardTime;
                    }
                    // Explicitly round down when calculating the reward
                    // slither-disable-start divide-before-multiply
                    uint256 rewardAmount = time * rewardPerSecond * pool.allocPoint / totalAllocPoint_;
                    pool.accRewardPerShare += SafeCast.toUint160(rewardAmount * _ACC_REWARD_TOKEN_PRECISION / lpSupply_);
                    // slither-disable-end divide-before-multiply
                }
            }
            pool.lastRewardTime = uint64(block.timestamp);
            _poolInfo[pid] = pool;
            emit LogUpdatePool(pid, pool.lastRewardTime, lpSupply_, pool.accRewardPerShare);
        }
    }

    /**
     * @notice Deposit LP tokens to MCV3 for REWARD_TOKEN allocation.
     * @dev Deposits can be paused in case of emergencies by the admin or pauser roles.
     * @param pid The index of the pool. See `_poolInfo`.
     * @param amount LP token amount to deposit.
     * @param to The receiver of `amount` deposit benefit.
     */
    function deposit(uint256 pid, uint256 amount, address to) public whenNotPaused {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = _userInfo[pid][to];

        // Effects
        user.amount += amount;
        user.rewardDebt += amount * pool.accRewardPerShare / _ACC_REWARD_TOKEN_PRECISION;
        /// @dev += is slightly more gas efficient (5300) than the alternative (5365) using solidity 0.8.18.
        /// The rule only applies to non-mapping storage variables.
        // nosemgrep: inefficient-state-variable-increment
        lpSupply[pid] += amount;

        emit Deposit(msg.sender, pid, amount, to);

        // Interactions
        lpToken[pid].safeTransferFrom(msg.sender, address(this), amount);

        IMiniChefV3Rewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, to, to, 0, user.amount);
        }
    }

    /**
     * @notice Withdraw LP tokens from MCV3.
     * @param pid The index of the pool. See `_poolInfo`.
     * @param amount LP token amount to withdraw.
     * @param to Receiver of the LP tokens.
     */
    function harvestAndWithdraw(uint256 pid, uint256 amount, address to) public {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = _userInfo[pid][msg.sender];

        uint256 accumulatedReward = user.amount * pool.accRewardPerShare / _ACC_REWARD_TOKEN_PRECISION;
        uint256 pendingReward_ = accumulatedReward + user.unpaidRewards - user.rewardDebt;

        // Effects
        user.rewardDebt = accumulatedReward - amount * pool.accRewardPerShare / _ACC_REWARD_TOKEN_PRECISION;
        user.amount -= amount;
        lpSupply[pid] -= amount;

        uint256 rewardAmount = 0;
        if (pendingReward_ != 0) {
            uint256 availableReward_ = availableReward;
            uint256 unpaidRewards_ = 0;
            rewardAmount = pendingReward_ > availableReward_ ? availableReward_ : pendingReward_;
            /// @dev unchecked is used as the subtraction is guaranteed to not underflow because
            /// `rewardAmount` is always less than or equal to `availableReward_`.
            unchecked {
                availableReward -= rewardAmount;
                unpaidRewards_ = pendingReward_ - rewardAmount;
            }
            user.unpaidRewards = unpaidRewards_;
            // Interactions
            if (rewardAmount != 0) {
                emit Harvest(msg.sender, pid, rewardAmount);
                // slither-disable-next-line reentrancy-events
                REWARD_TOKEN.safeTransfer(to, rewardAmount);
            }
        }

        // Interactions
        emit Withdraw(msg.sender, pid, amount, to);
        lpToken[pid].safeTransfer(to, amount);

        IMiniChefV3Rewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, rewardAmount, user.amount);
        }
    }

    /**
     * @notice Harvest proceeds for transaction sender to `to`.
     * @param pid The index of the pool. See `_poolInfo`.
     * @param to Receiver of REWARD_TOKEN rewards.
     */
    function harvest(uint256 pid, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = _userInfo[pid][msg.sender];
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
            /// @dev unchecked is used as the subtraction is guaranteed to not underflow because
            /// `rewardAmount` is always less than or equal to `availableReward_`.
            unchecked {
                availableReward -= rewardAmount;
                unpaidRewards_ = pendingReward_ - rewardAmount;
            }
            user.unpaidRewards = unpaidRewards_;
        }

        emit Harvest(msg.sender, pid, rewardAmount);

        if (pendingReward_ != 0) {
            if (rewardAmount != 0) {
                REWARD_TOKEN.safeTransfer(to, rewardAmount);
            }
        }

        IMiniChefV3Rewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, rewardAmount, user.amount);
        }
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY.
     * @param pid The index of the pool. See `_poolInfo`.
     * @param to Receiver of the LP tokens.
     */
    function emergencyWithdraw(uint256 pid, address to) public {
        UserInfo storage user = _userInfo[pid][msg.sender];
        uint256 amount = user.amount;

        emit EmergencyWithdraw(msg.sender, pid, amount, to);

        // Effects
        user.amount = 0;
        user.rewardDebt = 0;
        user.unpaidRewards = 0;
        lpSupply[pid] -= amount;

        // Interactions
        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[pid].safeTransfer(to, amount);

        IMiniChefV3Rewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            uint256 gasBefore = gasleft();
            // slither-disable-next-line missing-zero-check
            (bool success,) = address(_rewarder).call{ gas: gasBefore }(
                abi.encodeWithSignature("onReward(uint256,address,address,uint256,uint256)", pid, msg.sender, to, 0, 0)
            );
            if (!success) {
                emit LogRewarderEmergencyWithdrawFaulty(msg.sender, pid, amount, to);
            }
            require(gasleft() > gasBefore / 63);
        }
    }

    /**
     * @dev Pauses the contract. Only callable by PAUSER_ROLE or DEFAULT_ADMIN_ROLE.
     */
    function pause() external {
        if (!(hasRole(PAUSER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender))) {
            revert Errors.Unauthorized();
        }
        _pause();
    }

    /**
     * @dev Unpauses the contract. Only callable by DEFAULT_ADMIN_ROLE.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";
import { IDYfiRewardPool } from "src/interfaces/deps/yearn/veYFI/IDYfiRewardPool.sol";
import { IYfiRewardPool } from "src/interfaces/deps/yearn/veYFI/IYfiRewardPool.sol";
import { ISnapshotDelegateRegistry } from "src/interfaces/deps/snapshot/ISnapshotDelegateRegistry.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { Errors } from "src/libraries/Errors.sol";
import { Rescuable } from "src/Rescuable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { GaugeRewardReceiver } from "src/GaugeRewardReceiver.sol";
import { StakingDelegateRewards } from "src/StakingDelegateRewards.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";

/**
 * @title YearnStakingDelegate
 * @notice Contract for staking yearn gauge tokens, managing rewards, and delegating voting power.
 * @dev Inherits from IYearnStakingDelegate, AccessControlEnumerable, ReentrancyGuard, Rescuable, and Pausable.
 */
contract YearnStakingDelegate is
    IYearnStakingDelegate,
    AccessControlEnumerable,
    ReentrancyGuard,
    Rescuable,
    Pausable
{
    // Libraries
    using SafeERC20 for IERC20;
    using ClonesWithImmutableArgs for address;

    // Constants
    /// @dev Role identifier for pausers, capable of pausing contract functions.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @dev Role identifier for timelock, capable of performing time-sensitive administrative functions.
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    /// @dev Role identifier for depositors, capable of depositing gauge tokens.
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    // slither-disable-start naming-convention
    /// @dev Address of the Yearn Finance YFI reward pool.
    address private constant _YFI_REWARD_POOL = 0xb287a1964AEE422911c7b8409f5E5A273c1412fA;
    /// @dev Address of the Yearn Finance D_YFI reward pool.
    address private constant _DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;
    /// @dev Address of the Yearn Finance YFI token.
    address private constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    /// @dev Address of the Yearn Finance D_YFI token.
    address private constant _D_YFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    /// @dev Address of the Yearn Finance veYFI token.
    address private constant _VE_YFI = 0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5;
    /// @dev Address of the Snapshot delegate registry.
    address private constant _SNAPSHOT_DELEGATE_REGISTRY = 0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;
    /// @dev Maximum percentage of the treasury in basis points.
    uint256 private constant _MAX_TREASURY_PCT = 0.2e18;

    // Immutables
    /// @dev Address of the GaugeRewardReceiver implementation, set at contract deployment and immutable thereafter.
    address private immutable _GAUGE_REWARD_RECEIVER_IMPL;
    // slither-disable-end naming-convention

    // Mappings
    /// @notice Mapping of gauge addresses to their corresponding staking rewards contract addresses.
    mapping(address => address) public gaugeStakingRewards;
    /// @notice Mapping of gauge addresses to their corresponding GaugeRewardReceiver contract addresses.
    mapping(address => address) public gaugeRewardReceivers;
    /// @notice Mapping of user addresses to a nested mapping of token addresses to the user's balance of that token.
    mapping(address => mapping(address => uint256)) public balanceOf;
    /// @notice Mapping of gauge token address to the total amount deposited in this contract.
    mapping(address => uint256) public totalDeposited;
    /// @notice Mapping of gauge token addresses to their corresponding deposit limits. Note that this is the ideal
    /// limit, which should be enforced by the depositing contracts
    mapping(address => uint256) public depositLimit;
    /// @notice Mapping of target addresses to a boolean indicating whether the target is blocked.
    mapping(address => bool) public blockedTargets;
    /// @dev Mapping of vault addresses to their corresponding RewardSplit configuration.
    mapping(address => RewardSplit) private _gaugeRewardSplit;

    // Variables
    /// @dev Address of the treasury where funds are managed.
    address private _treasury;
    /// @dev Flag indicating whether to lock rewards perpetually.
    bool private _shouldPerpetuallyLock;
    /// @dev Address of the contract that swaps and locks tokens.
    address private _swapAndLock;
    /// @dev Address of the contract that forwards YFI rewards to CoveYFI.
    address private _coveYfiRewardForwarder;
    /// @dev Configuration for how rewards are split in the boost phase.
    BoostRewardSplit private _boostRewardSplit;
    /// @dev Configuration for how rewards are split upon exit.
    ExitRewardSplit private _exitRewardSplit;

    /**
     * @notice Emitted when YFI tokens are locked.
     * @param sender The address of the sender who locked YFI tokens.
     * @param amount The amount of YFI tokens locked.
     */
    event LockYfi(address indexed sender, uint256 amount);
    /**
     * @notice Emitted when gauge rewards are set.
     * @param gauge The address of the gauge for which rewards are set.
     * @param stakingRewardsContract The address of the staking rewards contract.
     * @param receiver The address of the rewards receiver.
     */
    event GaugeRewardsSet(address indexed gauge, address stakingRewardsContract, address receiver);
    /**
     * @notice Emitted when the perpetual lock setting is updated.
     * @param shouldLock The status of the perpetual lock setting.
     */
    event PerpetualLockSet(bool shouldLock);
    /**
     * @notice Emitted when the reward split configuration for a gauge is set.
     * @param gauge The address of the gauge for which the reward split is set.
     * @param split The reward split configuration.
     */
    event GaugeRewardSplitSet(address indexed gauge, RewardSplit split);
    /**
     * @notice Emitted when the boost reward split configuration is set.
     * @param treasuryPct The percentage of the boost reward allocated to the treasury.
     * @param coveYfiPct The percentage of the boost reward allocated to CoveYFI.
     */
    event BoostRewardSplitSet(uint128 treasuryPct, uint128 coveYfiPct);
    /**
     * @notice Emitted when the exit reward split configuration is set.
     * @param treasuryPct The percentage of the exit reward allocated to the treasury.
     * @param coveYfiPct The percentage of the exit reward allocated to CoveYFI.
     */
    event ExitRewardSplitSet(uint128 treasuryPct, uint128 coveYfiPct);
    /**
     * @notice Emitted when a deposit limit is set.
     * @param gaugeToken The address of the gauge token for which the deposit limit is set.
     * @param limit The deposit limit.
     */
    event DepositLimitSet(address indexed gaugeToken, uint256 limit);
    /**
     * @notice Emitted when the swap and lock contract address is set.
     * @param swapAndLockContract The address of the swap and lock contract.
     */
    event SwapAndLockSet(address swapAndLockContract);
    /**
     * @notice Emitted when the treasury address is updated.
     * @param newTreasury The new address of the treasury.
     */
    event TreasurySet(address newTreasury);
    /**
     * @notice Emitted when the CoveYFI reward forwarder address is set.
     * @param forwarder The address of the CoveYFI reward forwarder.
     */
    event CoveYfiRewardForwarderSet(address forwarder);
    /**
     * @notice Emitted when a gauge token is deposited
     * @param sender The address of the sender who made the deposit.
     * @param gauge The address of the gauge token deposited.
     * @param amount The amount of tokens deposited.
     * @param newTotalDeposited The new total amount of the gauge tokens deposited across all users.
     */
    event Deposit(address indexed sender, address indexed gauge, uint256 amount, uint256 newTotalDeposited);
    /**
     * @notice Emitted when a gauge token is withdrawn
     * @param sender The address of the sender who made the withdrawal.
     * @param gauge The address of the gauge token withdrawn.
     * @param amount The amount of tokens withdrawn.
     * @param newTotalDeposited The new total amount of the gauge tokens deposited across all users.
     */
    event Withdraw(address indexed sender, address indexed gauge, uint256 amount, uint256 newTotalDeposited);
    /**
     * @notice Emitted when the checkpointing of a user's balance fails
     * @param stakingDelegateRewards The address of the StakingDelegateRewards contract.
     * @param user The address of the user whose balance failed to checkpoint.
     * @param gauge The address of the gauge token.
     * @param currentUserBalance The current balance of gauge tokens deposited by the user.
     * @param currentTotalDeposited The current total amount of the gauge tokens deposited across all users.
     */
    event StakingDelegateRewardsFaulty(
        address stakingDelegateRewards,
        address user,
        address gauge,
        uint256 currentUserBalance,
        uint256 currentTotalDeposited
    );

    /**
     * @dev Initializes the contract by setting up roles and initializing state variables.
     * @param gaugeRewardReceiverImpl Address of the GaugeRewardReceiver implementation.
     * @param treasury_ Address of the treasury.
     * @param admin Address of the admin.
     * @param pauser Address of the pauser.
     * @param timelock Address of the timelock.
     */
    // slither-disable-next-line locked-ether
    constructor(
        address gaugeRewardReceiverImpl,
        address treasury_,
        address admin,
        address pauser,
        address timelock
    )
        payable
    {
        // Checks
        // Check for zero addresses
        if (
            gaugeRewardReceiverImpl == address(0) || treasury_ == address(0) || admin == address(0)
                || pauser == address(0) || timelock == address(0)
        ) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // Set storage variables
        _setTreasury(treasury_);
        _setPerpetualLock(true);
        _setBoostRewardSplit(0, 1e18); // 100% to CoveYFI by default
        _setExitRewardSplit(0, 1e18); // 100% to CoveYFI by default
        _GAUGE_REWARD_RECEIVER_IMPL = gaugeRewardReceiverImpl;
        blockedTargets[_YFI] = true;
        blockedTargets[_D_YFI] = true;
        blockedTargets[_VE_YFI] = true;
        blockedTargets[_YFI_REWARD_POOL] = true;
        blockedTargets[_DYFI_REWARD_POOL] = true;
        blockedTargets[_SNAPSHOT_DELEGATE_REGISTRY] = true;
        blockedTargets[_GAUGE_REWARD_RECEIVER_IMPL] = true;
        _setRoleAdmin(TIMELOCK_ROLE, TIMELOCK_ROLE);
        _setRoleAdmin(DEPOSITOR_ROLE, TIMELOCK_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TIMELOCK_ROLE, timelock);
        _grantRole(PAUSER_ROLE, pauser);

        // Interactions
        // Max approve YFI to veYFI so we can lock it later
        IERC20(_YFI).forceApprove(_VE_YFI, type(uint256).max);
    }

    /**
     * @notice Deposits a specified amount of gauge tokens into this staking delegate.
     * @dev Deposits can be paused in case of emergencies by the admin or pauser roles.
     * @param gauge The address of the gauge token to deposit.
     * @param amount The amount of tokens to deposit.
     */
    function deposit(address gauge, uint256 amount) external onlyRole(DEPOSITOR_ROLE) whenNotPaused {
        // Checks
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        address stakingDelegateReward = gaugeStakingRewards[gauge];
        if (stakingDelegateReward == address(0)) {
            revert Errors.GaugeRewardsNotYetAdded();
        }
        // Effects
        uint256 currentTotalDeposited = totalDeposited[gauge];
        uint256 currentUserBalance = balanceOf[msg.sender][gauge];
        uint256 newTotalDeposited = currentTotalDeposited + amount;
        balanceOf[msg.sender][gauge] = currentUserBalance + amount;
        totalDeposited[gauge] = newTotalDeposited;
        // Interactions
        emit Deposit(msg.sender, gauge, amount, newTotalDeposited);
        _checkpointUserBalance(stakingDelegateReward, gauge, msg.sender, currentUserBalance, currentTotalDeposited);
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Withdraws a specified amount of gauge tokens from this staking delegate.
     * @param gauge The address of the gauge token to withdraw.
     * @param amount The amount of tokens to withdraw.
     */
    function withdraw(address gauge, uint256 amount, address receiver) external {
        _withdraw(gauge, amount, receiver);
    }

    /**
     * @notice Withdraws a specified amount of gauge tokens from this staking delegate.
     * @param gauge The address of the gauge token to withdraw.
     * @param amount The amount of tokens to withdraw.
     */
    function withdraw(address gauge, uint256 amount) external {
        _withdraw(gauge, amount, msg.sender);
    }

    function _withdraw(address gauge, uint256 amount, address receiver) internal {
        // Checks
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        // Effects
        uint256 currentUserBalance = balanceOf[msg.sender][gauge];
        uint256 currentTotalDeposited = totalDeposited[gauge];
        uint256 newTotalDeposited = currentTotalDeposited - amount;
        balanceOf[msg.sender][gauge] = currentUserBalance - amount;
        totalDeposited[gauge] = newTotalDeposited;
        // Interactions
        emit Withdraw(msg.sender, gauge, amount, newTotalDeposited);
        _checkpointUserBalance(gaugeStakingRewards[gauge], gauge, msg.sender, currentUserBalance, currentTotalDeposited);
        IERC20(gauge).safeTransfer(receiver, amount);
    }

    /**
     * @notice Harvests rewards from a gauge and distributes them.
     * @param gauge Address of the gauge to harvest from.
     * @return The amount of rewards harvested.
     */
    function harvest(address gauge) external returns (uint256) {
        // Checks
        address swapAndLockContract = _swapAndLock;
        if (swapAndLockContract == address(0)) {
            revert Errors.SwapAndLockNotSet();
        }
        address gaugeRewardReceiver = gaugeRewardReceivers[gauge];
        if (gaugeRewardReceiver == address(0)) {
            revert Errors.GaugeRewardsNotYetAdded();
        }
        address rewardForwarder = _coveYfiRewardForwarder;
        if (rewardForwarder == address(0)) {
            revert Errors.CoveYfiRewardForwarderNotSet();
        }
        // Interactions
        return GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            swapAndLockContract, _treasury, rewardForwarder, _gaugeRewardSplit[gauge]
        );
    }

    /**
     * @notice Claim dYFI rewards from the reward pool and transfer them to the CoveYFI Reward Forwarder
     */
    function claimBoostRewards() external {
        // Checks
        address rewardForwarder = _coveYfiRewardForwarder;
        if (rewardForwarder == address(0)) {
            revert Errors.CoveYfiRewardForwarderNotSet();
        }
        // Interactions
        // Ignore the returned amount and use the balance instead to ensure we capture
        // any rewards claimed for this contract by other addresses
        // https://etherscan.io/address/0x2391Fc8f5E417526338F5aa3968b1851C16D894E#code
        // slither-disable-next-line unused-return
        IDYfiRewardPool(_DYFI_REWARD_POOL).claim();
        uint256 balance = IERC20(_D_YFI).balanceOf(address(this));
        uint256 coveYfiAmount = (balance * _boostRewardSplit.coveYfi) / 1e18;
        IERC20(_D_YFI).safeTransfer(rewardForwarder, coveYfiAmount);
        IERC20(_D_YFI).safeTransfer(_treasury, balance - coveYfiAmount);
    }

    /**
     * @notice Claim YFI rewards from the reward pool and transfer them to the CoveYFI Reward Forwarder
     */
    function claimExitRewards() external {
        // Checks
        address rewardForwarder = _coveYfiRewardForwarder;
        if (rewardForwarder == address(0)) {
            revert Errors.CoveYfiRewardForwarderNotSet();
        }
        // Interactions
        // Ignore the returned amount and use the balance instead to ensure we capture
        // any rewards claimed for this contract by other addresses
        // https://etherscan.io/address/0xb287a1964AEE422911c7b8409f5E5A273c1412fA#code
        // slither-disable-next-line unused-return
        IYfiRewardPool(_YFI_REWARD_POOL).claim();
        uint256 balance = IERC20(_YFI).balanceOf(address(this));
        uint256 coveYfiAmount = (balance * _exitRewardSplit.coveYfi) / 1e18;
        IERC20(_YFI).safeTransfer(rewardForwarder, coveYfiAmount);
        IERC20(_YFI).safeTransfer(_treasury, balance - coveYfiAmount);
    }

    /**
     * @notice Locks YFI tokens in the veYFI contract.
     * @dev Locking YFI can be paused in case of emergencies by the admin or pauser roles.
     * @param amount Amount of YFI tokens to lock.
     * @return The locked balance information.
     */
    function lockYfi(uint256 amount) external whenNotPaused returns (IVotingYFI.LockedBalance memory) {
        // Checks
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        if (!_shouldPerpetuallyLock) {
            revert Errors.PerpetualLockDisabled();
        }
        // Interactions
        emit LockYfi(msg.sender, amount);
        IERC20(_YFI).safeTransferFrom(msg.sender, address(this), amount);
        return IVotingYFI(_VE_YFI).modify_lock(amount, block.timestamp + 4 * 365 days + 4 weeks, address(this));
    }

    /**
     * @notice Sets the address for the CoveYFI Reward Forwarder.
     * @dev Can only be called by an address with the TIMELOCK_ROLE. Emits CoveYfiRewardForwarderSet event.
     * @param forwarder The address of the new CoveYFI Reward Forwarder.
     */
    function setCoveYfiRewardForwarder(address forwarder) external onlyRole(TIMELOCK_ROLE) {
        // Checks
        if (forwarder == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        _setCoveYfiRewardForwarder(forwarder);
    }

    /**
     * @notice Set treasury address. This address will receive a portion of the rewards
     * @param treasury_ address to receive rewards
     */
    function setTreasury(address treasury_) external onlyRole(TIMELOCK_ROLE) {
        // Checks
        if (treasury_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        _setTreasury(treasury_);
    }

    /**
     * @notice Sets the address for the SwapAndLock contract.
     * @param newSwapAndLock Address of the SwapAndLock contract.
     */
    function setSwapAndLock(address newSwapAndLock) external onlyRole(TIMELOCK_ROLE) {
        // Checks
        if (newSwapAndLock == address(0)) {
            revert Errors.ZeroAddress();
        }
        _swapAndLock = newSwapAndLock;
        emit SwapAndLockSet(newSwapAndLock);
    }

    /**
     * @notice Set the reward split percentages
     * @param gauge address of the gauge token
     * @param treasuryPct percentage of rewards to treasury
     * @param coveYfiPct percentage of rewards to coveYFI Reward Forwarder
     * @param userPct percentage of rewards to user
     * @param veYfiPct percentage of rewards to veYFI
     * @dev Sum of percentages must equal to 1e18
     */
    function setGaugeRewardSplit(
        address gauge,
        uint64 treasuryPct,
        uint64 coveYfiPct,
        uint64 userPct,
        uint64 veYfiPct
    )
        external
        onlyRole(TIMELOCK_ROLE)
    {
        _setGaugeRewardSplit(gauge, treasuryPct, coveYfiPct, userPct, veYfiPct);
    }

    /**
     * @notice Set the reward split percentages for dYFI boost rewards
     * @dev Sum of percentages must equal to 1e18
     * @param treasuryPct percentage of rewards to treasury
     * @param coveYfiPct percentage of rewards to CoveYFI Reward Forwarder
     */
    function setBoostRewardSplit(uint128 treasuryPct, uint128 coveYfiPct) external onlyRole(TIMELOCK_ROLE) {
        _setBoostRewardSplit(treasuryPct, coveYfiPct);
    }

    /**
     * @notice Set the reward split percentages for YFI exit rewards
     * @dev Sum of percentages must equal to 1e18
     * @param treasuryPct percentage of rewards to treasury
     * @param coveYfiPct percentage of rewards to CoveYFI Reward Forwarder
     */
    function setExitRewardSplit(uint128 treasuryPct, uint128 coveYfiPct) external onlyRole(TIMELOCK_ROLE) {
        _setExitRewardSplit(treasuryPct, coveYfiPct);
    }

    /**
     * @notice Set the deposit limit for a gauge token. This is the ideal limit, which should be enforced by the
     * depositing contracts.
     * @param gaugeToken address of the gauge token
     * @param limit maximum amount of tokens that can be deposited
     */
    function setDepositLimit(address gaugeToken, uint256 limit) external onlyRole(TIMELOCK_ROLE) {
        // Effects
        emit DepositLimitSet(gaugeToken, limit);
        depositLimit[gaugeToken] = limit;
    }

    /**
     * @notice Delegates voting power to a given address
     * @param id name of the space in snapshot to apply delegation. For yearn it is "veyfi.eth"
     * @param delegate address to delegate voting power to
     */
    function setSnapshotDelegate(bytes32 id, address delegate) external onlyRole(TIMELOCK_ROLE) {
        // Checks
        if (delegate == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Interactions
        ISnapshotDelegateRegistry(_SNAPSHOT_DELEGATE_REGISTRY).setDelegate(id, delegate);
    }

    /**
     * @notice Adds gauge rewards configuration.
     * @param gauge Address of the gauge.
     * @param stakingDelegateRewards Address of the StakingDelegateRewards contract.
     */
    function addGaugeRewards(
        address gauge,
        address stakingDelegateRewards
    )
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // Checks
        if (gauge == address(0) || stakingDelegateRewards == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (gaugeStakingRewards[gauge] != address(0)) {
            revert Errors.GaugeRewardsAlreadyAdded();
        }
        // Effects
        // 0% to treasury, 0% to coveYfi, 100% to user, 0% to SwapAndLock for increasing veYFI lock
        _setGaugeRewardSplit(gauge, 0, 0, 1e18, 0);
        // Effects & Interactions
        _setGaugeRewards(gauge, stakingDelegateRewards);
    }

    /**
     * @notice Updates gauge rewards configuration.
     * @param gauge Address of the gauge.
     * @param stakingDelegateRewards Address of the new StakingDelegateRewards contract.
     */
    function updateGaugeRewards(
        address gauge,
        address stakingDelegateRewards
    )
        external
        nonReentrant
        onlyRole(TIMELOCK_ROLE)
    {
        // Checks
        if (gauge == address(0) || stakingDelegateRewards == address(0)) {
            revert Errors.ZeroAddress();
        }
        address previousStakingDelegateRewards = gaugeStakingRewards[gauge];
        if (previousStakingDelegateRewards == address(0)) {
            revert Errors.GaugeRewardsNotYetAdded();
        }
        if (previousStakingDelegateRewards == stakingDelegateRewards) {
            revert Errors.GaugeRewardsAlreadyAdded();
        }
        // Effects & Interactions
        _setGaugeRewards(gauge, stakingDelegateRewards);
    }

    /**
     * @notice Set perpetual lock status
     * @param lock if true, lock YFI for 4 years after each harvest
     */
    function setPerpetualLock(bool lock) external onlyRole(TIMELOCK_ROLE) {
        _setPerpetualLock(lock);
    }

    /**
     * @notice early unlock veYFI and send YFI to treasury
     */
    function earlyUnlock() external onlyRole(TIMELOCK_ROLE) {
        // Checks
        if (_shouldPerpetuallyLock) {
            revert Errors.PerpetualLockEnabled();
        }
        // Interactions
        IVotingYFI.Withdrawn memory withdrawn = IVotingYFI(_VE_YFI).withdraw();
        IERC20(_YFI).safeTransfer(_treasury, withdrawn.amount);
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

    /**
     * @notice Execute arbitrary calls from the staking delegate. This function is callable
     * by the admin role for future proofing. Target must not be YFI, dYFI, veYFI, or a known
     * gauge token.
     * @param target contract to call
     * @param data calldata to execute the call with
     * @param value call value
     * @return result of the call
     */
    function execute(
        address target,
        bytes calldata data,
        uint256 value
    )
        external
        payable
        onlyRole(TIMELOCK_ROLE)
        returns (bytes memory)
    {
        // Checks
        if (blockedTargets[target]) {
            revert Errors.ExecutionNotAllowed();
        }
        // Interactions
        // slither-disable-start arbitrary-send-eth
        // slither-disable-start low-level-calls
        // solhint-disable-next-line avoid-low-level-calls
        // nosemgrep: solidity.security.arbitrary-low-level-call.arbitrary-low-level-call
        (bool success, bytes memory result) = target.call{ value: value }(data);
        // slither-disable-end arbitrary-send-eth
        // slither-disable-end low-level-calls
        if (!success) {
            revert Errors.ExecutionFailed();
        }
        return result;
    }

    /**
     * @notice Get the available deposit limit for a gauge token
     * @param gaugeToken The address of the gauge token
     * @return Available deposit limit
     */
    function availableDepositLimit(address gaugeToken) external view returns (uint256) {
        uint256 currentTotalDeposited = totalDeposited[gaugeToken];
        uint256 currentDepositLimit = depositLimit[gaugeToken];
        if (currentTotalDeposited >= currentDepositLimit) {
            return 0;
        }
        // Return the difference between the max total assets and the current total assets, an underflow is not possible
        // due to the above check
        unchecked {
            return currentDepositLimit - currentTotalDeposited;
        }
    }

    /**
     * @notice Get the dYFI boost reward split
     * @return BoostRewardSplit struct containing the treasury and coveYFI split.
     */
    function getBoostRewardSplit() external view returns (BoostRewardSplit memory) {
        return _boostRewardSplit;
    }

    /**
     * @notice Get the YFI exit reward split
     * @return ExitRewardSplit struct containing the treasury and coveYFI split.
     */
    function getExitRewardSplit() external view returns (ExitRewardSplit memory) {
        return _exitRewardSplit;
    }

    /**
     * @notice Get the dYFI reward split for a gauge
     * @param gauge Address of the gauge
     * @return RewardSplit struct containing the treasury, coveYFI, user, and lock splits for the gauge
     */
    function getGaugeRewardSplit(address gauge) external view returns (RewardSplit memory) {
        return _gaugeRewardSplit[gauge];
    }

    /**
     * @notice Get the address of the treasury
     * @return The address of the treasury
     */
    function treasury() external view returns (address) {
        return _treasury;
    }

    /**
     * @notice Get the address of the stored CoveYFI Reward Forwarder
     * @return The address of the CoveYFI Reward Forwarder
     */
    function coveYfiRewardForwarder() external view returns (address) {
        return _coveYfiRewardForwarder;
    }

    /**
     * @notice Get the address of the SwapAndLock contract
     * @return The address of the SwapAndLock contract
     */
    function swapAndLock() external view returns (address) {
        return _swapAndLock;
    }

    /**
     * @notice Get the perpetual lock status
     * @return True if perpetual lock is enabled
     */
    function shouldPerpetuallyLock() external view returns (bool) {
        return _shouldPerpetuallyLock;
    }

    /**
     * @notice Get the address of the YFI token
     * @return The address of the YFI token
     */
    function yfi() external pure returns (address) {
        return _YFI;
    }

    /**
     * @notice Get the address of the dYFI token
     * @return The address of the dYFI token
     */
    function dYfi() external pure returns (address) {
        return _D_YFI;
    }

    /**
     * @notice Get the address of the veYFI token
     * @return The address of the veYFI token
     */
    function veYfi() external pure returns (address) {
        return _VE_YFI;
    }

    /**
     * @dev Internal function to set the treasury address.
     * @param treasury_ The address of the new treasury.
     */
    function _setTreasury(address treasury_) internal {
        _treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    /**
     * @dev Internal function to set the CoveYFI Reward Forwarder address.
     * @param forwarder The address of the CoveYFI Reward Forwarder.
     */
    function _setCoveYfiRewardForwarder(address forwarder) internal {
        _coveYfiRewardForwarder = forwarder;
        emit CoveYfiRewardForwarderSet(forwarder);
    }

    /**
     * @dev Internal function to set gauge rewards and reward receiver.
     * @param gauge Address of the gauge.
     * @param stakingDelegateRewards Address of the StakingDelegateRewards contract.
     */
    function _setGaugeRewards(address gauge, address stakingDelegateRewards) internal {
        gaugeStakingRewards[gauge] = stakingDelegateRewards;
        blockedTargets[gauge] = true;
        blockedTargets[stakingDelegateRewards] = true;
        address receiver =
            _GAUGE_REWARD_RECEIVER_IMPL.clone(abi.encodePacked(address(this), gauge, _D_YFI, stakingDelegateRewards));
        gaugeRewardReceivers[gauge] = receiver;
        blockedTargets[receiver] = true;
        // Interactions
        emit GaugeRewardsSet(gauge, stakingDelegateRewards, receiver);
        GaugeRewardReceiver(receiver).initialize(msg.sender);
        IGauge(gauge).setRecipient(receiver);
        StakingDelegateRewards(stakingDelegateRewards).addStakingToken(gauge, receiver);
    }

    /**
     * @dev Internal function to set the perpetual lock status.
     * @param lock True for max lock.
     */
    function _setPerpetualLock(bool lock) internal {
        _shouldPerpetuallyLock = lock;
        emit PerpetualLockSet(lock);
    }

    /**
     * @dev Internal function to set the reward split for a gauge.
     * @param gauge Address of the gauge.
     * @param treasuryPct Percentage of rewards to the treasury.
     * @param userPct Percentage of rewards to the user.
     * @param lockPct Percentage of rewards to lock in veYFI.
     */
    function _setGaugeRewardSplit(
        address gauge,
        uint64 treasuryPct,
        uint64 coveYfiPct,
        uint64 userPct,
        uint64 lockPct
    )
        internal
    {
        if (uint256(treasuryPct) + coveYfiPct + userPct + lockPct != 1e18) {
            revert Errors.InvalidRewardSplit();
        }
        if (treasuryPct > _MAX_TREASURY_PCT) {
            revert Errors.TreasuryPctTooHigh();
        }
        RewardSplit memory newRewardSplit =
            RewardSplit({ treasury: treasuryPct, coveYfi: coveYfiPct, user: userPct, lock: lockPct });
        _gaugeRewardSplit[gauge] = newRewardSplit;
        emit GaugeRewardSplitSet(gauge, newRewardSplit);
    }

    /**
     * @dev Internal function to set the reward split for the dYFI boost rewards
     * @param treasuryPct Percentage of rewards to the treasury.
     * @param coveYfiPct Percentage of rewards to the CoveYFI Reward Forwarder.
     */
    function _setBoostRewardSplit(uint128 treasuryPct, uint128 coveYfiPct) internal {
        if (uint256(treasuryPct) + coveYfiPct != 1e18) {
            revert Errors.InvalidRewardSplit();
        }
        if (treasuryPct > _MAX_TREASURY_PCT) {
            revert Errors.TreasuryPctTooHigh();
        }
        _boostRewardSplit = BoostRewardSplit({ treasury: treasuryPct, coveYfi: coveYfiPct });
        emit BoostRewardSplitSet(treasuryPct, coveYfiPct);
    }

    /**
     * @dev Internal function to set the reward split for the YFI exit rewards (when veYFI holders early unlock their
     * YFI, a portion of their YFI is distributed to other veYFI holders).
     * @param treasuryPct Percentage of rewards to the treasury.
     * @param coveYfiPct Percentage of rewards to the CoveYFI Reward Forwarder.
     */
    function _setExitRewardSplit(uint128 treasuryPct, uint128 coveYfiPct) internal {
        if (uint256(treasuryPct) + coveYfiPct != 1e18) {
            revert Errors.InvalidRewardSplit();
        }
        if (treasuryPct > _MAX_TREASURY_PCT) {
            revert Errors.TreasuryPctTooHigh();
        }
        _exitRewardSplit = ExitRewardSplit({ treasury: treasuryPct, coveYfi: coveYfiPct });
        emit ExitRewardSplitSet(treasuryPct, coveYfiPct);
    }

    /**
     * @dev Internal function to checkpoint a user's balance for a gauge.
     * @param stakingDelegateReward Address of the StakingDelegateRewards contract.
     * @param gauge Address of the gauge.
     * @param user Address of the user.
     * @param userBalance New balance of the user for the gauge.
     */
    function _checkpointUserBalance(
        address stakingDelegateReward,
        address gauge,
        address user,
        uint256 userBalance,
        uint256 currentTotalDeposited
    )
        internal
    {
        // In case of error, we don't want to block the entire tx so we try-catch
        bytes memory data =
            abi.encodeCall(StakingDelegateRewards.updateUserBalance, (user, gauge, userBalance, currentTotalDeposited));
        uint256 gasBefore = gasleft();
        // slither-disable-next-line missing-zero-check,return-bomb,low-level-calls
        (bool success,) = address(stakingDelegateReward).call{ gas: gasBefore }(data);
        // Protect against griefing via specifying low gas to trigger a revert in the callee
        // https://ronan.eth.limo/blog/ethereum-gas-dangers/
        // https://www.rareskills.io/post/eip-150-and-the-63-64-rule-for-gas
        if (gasleft() <= gasBefore / 63) {
            revert Errors.InsufficientGas();
        }
        if (!success) {
            // slither-disable-next-line reentrancy-events
            emit StakingDelegateRewardsFaulty(stakingDelegateReward, user, gauge, userBalance, currentTotalDeposited);
        }
    }
}

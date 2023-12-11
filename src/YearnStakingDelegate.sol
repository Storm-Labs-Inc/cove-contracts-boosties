// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";
import { IDYfiRewardPool } from "src/interfaces/deps/yearn/veYFI/IDYfiRewardPool.sol";
import { IYfiRewardPool } from "src/interfaces/deps/yearn/veYFI/IYfiRewardPool.sol";
import { ISnapshotDelegateRegistry } from "src/interfaces/deps/snapshot/ISnapshotDelegateRegistry.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Errors } from "src/libraries/Errors.sol";
import { Rescuable } from "src/Rescuable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { GaugeRewardReceiver } from "src/GaugeRewardReceiver.sol";
import { StakingDelegateRewards } from "src/StakingDelegateRewards.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";

/**
 * @title YearnStakingDelegate
 * @notice Contract for staking yearn gauge tokens, managing rewards, and delegating voting power.
 * @dev Inherits from IYearnStakingDelegate, AccessControl, ReentrancyGuard, and Rescuable.
 */
contract YearnStakingDelegate is IYearnStakingDelegate, AccessControl, ReentrancyGuard, Rescuable {
    // Libraries
    using SafeERC20 for IERC20;
    using ClonesWithImmutableArgs for address;

    // Constants
    // slither-disable-start naming-convention
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    address private constant _YFI_REWARD_POOL = 0xb287a1964AEE422911c7b8409f5E5A273c1412fA;
    address private constant _DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;
    address private constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address private constant _D_YFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address private constant _VE_YFI = 0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5;
    address private constant _SNAPSHOT_DELEGATE_REGISTRY = 0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;

    // Immutables
    address private immutable _GAUGE_REWARD_RECEIVER_IMPL;
    // slither-disable-end naming-convention

    // Mappings
    /// @notice Mapping of vault to gauge
    mapping(address gauge => address) public gaugeStakingRewards;
    mapping(address gauge => address) public gaugeRewardReceivers;
    mapping(address vault => RewardSplit) public gaugeRewardSplit;
    mapping(address user => mapping(address token => uint256)) public balanceOf;
    mapping(address target => bool) private _blockedTargets;

    // Variables
    address public treasury;
    bool public shouldPerpetuallyLock;
    address public swapAndLock;

    /**
     * @dev Initializes the contract by setting up roles and initializing state variables.
     * @param gaugeRewardReceiverImpl Address of the GaugeRewardReceiver implementation.
     * @param _treasury Address of the treasury.
     * @param admin Address of the admin.
     * @param manager Address of the manager.
     */
    constructor(address gaugeRewardReceiverImpl, address _treasury, address admin, address manager) {
        // Checks
        // Check for zero addresses
        if (
            gaugeRewardReceiverImpl == address(0) || _treasury == address(0) || admin == address(0)
                || manager == address(0)
        ) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // Set storage variables
        _setTreasury(_treasury);
        _setPerpetualLock(true);
        _GAUGE_REWARD_RECEIVER_IMPL = gaugeRewardReceiverImpl;
        _blockedTargets[_YFI] = true;
        _blockedTargets[_D_YFI] = true;
        _blockedTargets[_VE_YFI] = true;
        _blockedTargets[_YFI_REWARD_POOL] = true;
        _blockedTargets[_DYFI_REWARD_POOL] = true;
        _blockedTargets[_SNAPSHOT_DELEGATE_REGISTRY] = true;
        _blockedTargets[_GAUGE_REWARD_RECEIVER_IMPL] = true;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);

        // Interactions
        // Max approve YFI to veYFI so we can lock it later
        IERC20(_YFI).forceApprove(_VE_YFI, type(uint256).max);
    }

    /**
     * @notice Deposits tokens into a gauge.
     * @param gauge Address of the gauge to deposit into.
     * @param amount Amount of tokens to deposit.
     */
    function deposit(address gauge, uint256 amount) external {
        // Checks
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        address stakingDelegateReward = gaugeStakingRewards[gauge];
        if (stakingDelegateReward == address(0)) {
            revert Errors.GaugeRewardsNotYetAdded();
        }
        // Effects
        uint256 newBalance = balanceOf[msg.sender][gauge] + amount;
        balanceOf[msg.sender][gauge] = newBalance;
        // Interactions
        emit Deposit(msg.sender, gauge, amount);
        _checkpointUserBalance(stakingDelegateReward, gauge, msg.sender, newBalance);
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Withdraws tokens from a gauge.
     * @param gauge Address of the gauge to withdraw from.
     * @param amount Amount of tokens to withdraw.
     */
    function withdraw(address gauge, uint256 amount) external {
        // Checks
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        // Effects
        uint256 newBalance = balanceOf[msg.sender][gauge] - amount;
        balanceOf[msg.sender][gauge] = newBalance;
        // Interactions
        emit Withdraw(msg.sender, gauge, amount);
        _checkpointUserBalance(gaugeStakingRewards[gauge], gauge, msg.sender, newBalance);
        IERC20(gauge).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Harvests rewards from a gauge and distributes them.
     * @param gauge Address of the gauge to harvest from.
     * @return The amount of rewards harvested.
     */
    function harvest(address gauge) external returns (uint256) {
        // Checks
        address swapAndLock_ = swapAndLock;
        if (swapAndLock_ == address(0)) {
            revert Errors.SwapAndLockNotSet();
        }
        address gaugeRewardReceiver = gaugeRewardReceivers[gauge];
        if (gaugeRewardReceiver == address(0)) {
            revert Errors.GaugeRewardsNotYetAdded();
        }
        // Interactions
        return GaugeRewardReceiver(gaugeRewardReceiver).harvest(swapAndLock_, treasury, gaugeRewardSplit[gauge]);
    }

    /**
     * @notice Claim dYFI rewards from the reward pool and transfer them to the treasury
     */
    function claimBoostRewards() external {
        // Interactions
        // Ignore the returned amount and use the balance instead to ensure we capture
        // any rewards claimed for this contract by other addresses
        // https://etherscan.io/address/0xb287a1964AEE422911c7b8409f5E5A273c1412fA#code
        // slither-disable-next-line unused-return
        IDYfiRewardPool(_DYFI_REWARD_POOL).claim();
        IERC20(_D_YFI).safeTransfer(treasury, IERC20(_D_YFI).balanceOf(address(this)));
    }

    /**
     * @notice Claim YFI rewards from the reward pool and transfer them to the treasury
     */
    function claimExitRewards() external {
        // Interactions
        // Ignore the returned amount and use the balance instead to ensure we capture
        // any rewards claimed for this contract by other addresses
        // https://etherscan.io/address/0xb287a1964AEE422911c7b8409f5E5A273c1412fA#code
        // slither-disable-next-line unused-return
        IYfiRewardPool(_YFI_REWARD_POOL).claim();
        IERC20(_YFI).safeTransfer(treasury, IERC20(_YFI).balanceOf(address(this)));
    }

    /**
     * @notice Locks YFI tokens in the veYFI contract.
     * @param amount Amount of YFI tokens to lock.
     * @return The locked balance information.
     */
    function lockYfi(uint256 amount) external returns (IVotingYFI.LockedBalance memory) {
        // Checks
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        if (!shouldPerpetuallyLock) {
            revert Errors.PerpetualLockDisabled();
        }
        // Interactions
        emit LockYfi(msg.sender, amount);
        IERC20(_YFI).safeTransferFrom(msg.sender, address(this), amount);
        return IVotingYFI(_VE_YFI).modify_lock(amount, block.timestamp + 4 * 365 days + 4 weeks, address(this));
    }

    /**
     * @notice Set treasury address. This address will receive a portion of the rewards
     * @param treasury_ address to receive rewards
     */
    function setTreasury(address treasury_) external onlyRole(MANAGER_ROLE) {
        // Checks
        if (treasury_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        _setTreasury(treasury_);
    }

    /**
     * @notice Sets the address for the SwapAndLock contract.
     * @param swapAndLock_ Address of the SwapAndLock contract.
     */
    function setSwapAndLock(address swapAndLock_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Checks
        if (swapAndLock_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        swapAndLock = swapAndLock_;
        emit SwapAndLockSet(swapAndLock_);
    }

    /**
     * @notice Set the reward split percentages
     * @param gauge address of the gauge token
     * @param treasuryPct percentage of rewards to treasury
     * @param userPct percentage of rewards to user
     * @param veYfiPct percentage of rewards to veYFI
     * @dev Sum of percentages must equal to 1e18
     */
    function setRewardSplit(
        address gauge,
        uint80 treasuryPct,
        uint80 userPct,
        uint80 veYfiPct
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setRewardSplit(gauge, treasuryPct, userPct, veYfiPct);
    }

    /**
     * @notice Delegates voting power to a given address
     * @param id name of the space in snapshot to apply delegation. For yearn it is "veyfi.eth"
     * @param delegate address to delegate voting power to
     */
    function setSnapshotDelegate(bytes32 id, address delegate) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
        _setRewardSplit(gauge, 0, 1e18, 0); // 0% to treasury, 100% to user, 0% to veYFI for relocking
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
        onlyRole(DEFAULT_ADMIN_ROLE)
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
     * @param shouldPerpetuallyLock_ if true, lock YFI for 4 years after each harvest
     */
    function setPerpetualLock(bool shouldPerpetuallyLock_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setPerpetualLock(shouldPerpetuallyLock_);
    }

    /**
     * @notice early unlock veYFI
     * @param to address to receive the unlocked YFI
     */
    function earlyUnlock(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Checks
        if (shouldPerpetuallyLock) {
            revert Errors.PerpetualLockEnabled();
        }
        // Interactions
        IVotingYFI.Withdrawn memory withdrawn = IVotingYFI(_VE_YFI).withdraw();
        IERC20(_YFI).safeTransfer(to, withdrawn.amount);
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
        bytes memory data,
        uint256 value
    )
        external
        payable
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bytes memory)
    {
        // Checks
        if (_blockedTargets[target]) {
            revert Errors.ExecutionNotAllowed();
        }
        // Interactions
        // slither-disable-start arbitrary-send-eth
        // slither-disable-start low-level-calls
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = target.call{ value: value }(data);
        // slither-disable-end arbitrary-send-eth
        // slither-disable-end low-level-calls
        if (!success) {
            revert Errors.ExecutionFailed();
        }
        return result;
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

    function _setTreasury(address treasury_) internal {
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    /**
     * @dev Internal function to set gauge rewards and reward receiver.
     * @param gauge Address of the gauge.
     * @param stakingDelegateRewards Address of the StakingDelegateRewards contract.
     */
    function _setGaugeRewards(address gauge, address stakingDelegateRewards) internal {
        gaugeStakingRewards[gauge] = stakingDelegateRewards;
        _blockedTargets[gauge] = true;
        _blockedTargets[stakingDelegateRewards] = true;
        address receiver =
            _GAUGE_REWARD_RECEIVER_IMPL.clone(abi.encodePacked(address(this), gauge, _D_YFI, stakingDelegateRewards));
        gaugeRewardReceivers[gauge] = receiver;
        _blockedTargets[receiver] = true;
        // Interactions
        emit GaugeRewardsSet(gauge, stakingDelegateRewards, receiver);
        GaugeRewardReceiver(receiver).initialize(msg.sender);
        IGauge(gauge).setRecipient(receiver);
        StakingDelegateRewards(stakingDelegateRewards).addStakingToken(gauge, receiver);
    }

    /**
     * @dev Internal function to set the perpetual lock status.
     * @param shouldPerpetuallyLock_ True for max lock.
     */
    function _setPerpetualLock(bool shouldPerpetuallyLock_) internal {
        shouldPerpetuallyLock = shouldPerpetuallyLock_;
        emit PerpetualLockSet(shouldPerpetuallyLock_);
    }

    /**
     * @dev Internal function to set the reward split for a gauge.
     * @param gauge Address of the gauge.
     * @param treasuryPct Percentage of rewards to the treasury.
     * @param userPct Percentage of rewards to the user.
     * @param lockPct Percentage of rewards to lock in veYFI.
     */
    function _setRewardSplit(address gauge, uint80 treasuryPct, uint80 userPct, uint80 lockPct) internal {
        if (uint256(treasuryPct) + userPct + lockPct != 1e18) {
            revert Errors.InvalidRewardSplit();
        }
        RewardSplit memory newRewardSplit = RewardSplit({ treasury: treasuryPct, user: userPct, lock: lockPct });
        gaugeRewardSplit[gauge] = newRewardSplit;
        emit GaugeRewardSplitSet(gauge, newRewardSplit);
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
        uint256 userBalance
    )
        internal
    {
        // In case of error, we don't want to block the entire tx so we try-catch
        // solhint-disable-next-line no-empty-blocks
        try StakingDelegateRewards(stakingDelegateReward).updateUserBalance(user, gauge, userBalance) { } catch { }
    }
}

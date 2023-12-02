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

contract YearnStakingDelegate is AccessControl, ReentrancyGuard, Rescuable {
    // Libraries
    using SafeERC20 for IERC20;
    using ClonesWithImmutableArgs for address;

    // Struct definitions
    struct RewardSplit {
        uint80 treasury;
        uint80 strategy;
        uint80 lock;
    }

    // Constants
    // slither-disable naming-convention
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    address private constant _YFI_REWARD_POOL = 0xb287a1964AEE422911c7b8409f5E5A273c1412fA;
    address private constant _DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;
    address private constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address private constant _D_YFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address private constant _VE_YFI = 0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5;
    address private constant _SNAPSHOT_DELEGATE_REGISTRY = 0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;

    // Immutables
    address private immutable _GAUGE_REWARD_RECEIVER_IMPL;
    // slither-enable naming-convention

    // Mappings
    /// @notice Mapping of vault to gauge
    mapping(address gauge => address) public gaugeStakingRewards;
    mapping(address gauge => address) public gaugeRewardReceivers;
    mapping(address vault => RewardSplit) public gaugeRewardSplit;
    mapping(address strategy => mapping(address => uint256)) public balances;

    // Variables
    address public treasury;
    bool public shouldPerpetuallyLock;
    address public swapAndLock;

    /* ========== CONSTRUCTOR ========== */
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
        treasury = _treasury;
        shouldPerpetuallyLock = true;
        _GAUGE_REWARD_RECEIVER_IMPL = gaugeRewardReceiverImpl;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);

        // Interactions
        // Max approve YFI to veYFI so we can lock it later
        IERC20(_YFI).forceApprove(_VE_YFI, type(uint256).max);
    }

    /* ========== VIEWS ========== */
    function yfi() external pure returns (address) {
        return _YFI;
    }

    function dYfi() external pure returns (address) {
        return _D_YFI;
    }

    function veYfi() external pure returns (address) {
        return _VE_YFI;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function deposit(address gauge, uint256 amount) external {
        // Effects
        uint256 newBalance = balances[gauge][msg.sender] + amount;
        balances[gauge][msg.sender] = newBalance;
        // Interactions
        _checkpointUserBalance(gauge, msg.sender, newBalance);
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(address gauge, uint256 amount) external {
        // Effects
        uint256 newBalance = balances[gauge][msg.sender] - amount;
        balances[gauge][msg.sender] = newBalance;
        // Interactions
        _checkpointUserBalance(gauge, msg.sender, newBalance);
        IERC20(gauge).safeTransfer(msg.sender, amount);
    }

    function _checkpointUserBalance(address gauge, address user, uint256 userBalance) internal {
        address stakingDelegateReward = gaugeStakingRewards[gauge];
        if (stakingDelegateReward != address(0)) {
            StakingDelegateRewards(stakingDelegateReward).updateUserBalance(gauge, user, userBalance);
        }
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

    function harvest(address gauge) external returns (uint256) {
        address _swapAndLock = swapAndLock;
        if (_swapAndLock == address(0)) {
            revert Errors.ZeroAddress();
        }
        address gaugeRewardReceiver = gaugeRewardReceivers[gauge];
        return GaugeRewardReceiver(gaugeRewardReceiver).harvest(_swapAndLock, treasury, gaugeRewardSplit[gauge]);
    }

    function _lockYfi(uint256 amount) internal returns (IVotingYFI.LockedBalance memory) {
        return IVotingYFI(_VE_YFI).modify_lock(amount, block.timestamp + 4 * 365 days + 4 weeks, address(this));
    }

    // Transfer amount of YFI from msg.sender and locks
    function lockYfi(uint256 amount) external returns (IVotingYFI.LockedBalance memory) {
        // Checks
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        if (!shouldPerpetuallyLock) {
            revert Errors.PerpetualLockDisabled();
        }
        // Interactions
        IERC20(_YFI).safeTransferFrom(msg.sender, address(this), amount);
        return _lockYfi(amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice Set perpetual lock status
    /// @param _shouldPerpetuallyLock if true, lock YFI for 4 years after each harvest
    // slither-disable-next-line naming-convention
    function setPerpetualLock(bool _shouldPerpetuallyLock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        shouldPerpetuallyLock = _shouldPerpetuallyLock;
    }

    /// @notice Set treasury address. This address will receive a portion of the rewards
    /// @param _treasury address to receive rewards
    // slither-disable-next-line naming-convention
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Checks
        if (_treasury == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        treasury = _treasury;
    }

    // slither-disable-next-line naming-convention
    function setSwapAndLock(address _swapAndLock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Checks
        if (_swapAndLock == address(0)) {
            revert Errors.ZeroAddress();
        }
        swapAndLock = _swapAndLock;
    }

    function addGaugeRewards(
        address gauge,
        address stakingDelegateRewards
    )
        external
        nonReentrant
        onlyRole(MANAGER_ROLE)
    {
        // Checks
        if (gauge == address(0) || stakingDelegateRewards == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        _setRewardSplit(gauge, 0, 1e18, 0); // 0% to treasury, 100% to user, 0% to veYFI for relocking
        address receiver =
            _GAUGE_REWARD_RECEIVER_IMPL.clone(abi.encodePacked(address(this), gauge, _D_YFI, stakingDelegateRewards));
        gaugeRewardReceivers[gauge] = receiver;
        gaugeStakingRewards[gauge] = stakingDelegateRewards;
        // Interactions
        GaugeRewardReceiver(receiver).initialize();
        IGauge(gauge).setRecipient(receiver);
        StakingDelegateRewards(stakingDelegateRewards).addStakingToken(gauge, receiver);
    }

    /// Delegates voting power to a given address
    /// @param id name of the space in snapshot to apply delegation. For yearn it is "veyfi.eth"
    /// @param delegate address to delegate voting power to
    function setSnapshotDelegate(bytes32 id, address delegate) external onlyRole(MANAGER_ROLE) {
        // Checks
        if (delegate == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Interactions
        ISnapshotDelegateRegistry(_SNAPSHOT_DELEGATE_REGISTRY).setDelegate(id, delegate);
    }

    function _setRewardSplit(address gauge, uint80 treasuryPct, uint80 compoundPct, uint80 veYfiPct) internal {
        if (uint256(treasuryPct) + compoundPct + veYfiPct != 1e18) {
            revert Errors.InvalidRewardSplit();
        }
        gaugeRewardSplit[gauge] = RewardSplit(treasuryPct, compoundPct, veYfiPct);
    }

    /// @notice Set the reward split percentages
    /// @param treasuryPct percentage of rewards to treasury
    /// @param compoundPct percentage of rewards to compound
    /// @param veYfiPct percentage of rewards to veYFI
    /// @dev Sum of percentages must equal to 1e18
    function setRewardSplit(
        address gauge,
        uint80 treasuryPct,
        uint80 compoundPct,
        uint80 veYfiPct
    )
        external
        onlyRole(MANAGER_ROLE)
    {
        _setRewardSplit(gauge, treasuryPct, compoundPct, veYfiPct);
    }

    /// @notice early unlock veYFI
    function earlyUnlock(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Checks
        if (shouldPerpetuallyLock) {
            revert Errors.PerpetualLockEnabled();
        }
        // Interactions
        IVotingYFI.Withdrawn memory withdrawn = IVotingYFI(_VE_YFI).withdraw();
        IERC20(_YFI).safeTransfer(to, withdrawn.amount);
    }

    function rescue(IERC20 token, address to, uint256 balance) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _rescue(token, to, balance);
    }
}

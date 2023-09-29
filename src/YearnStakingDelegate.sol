// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { SafeERC20, IERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";
import { ISnapshotDelegateRegistry } from "src/interfaces/deps/snapshot/ISnapshotDelegateRegistry.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { AccessControl } from "@openzeppelin-5.0/contracts/access/AccessControl.sol";
import { Errors } from "src/libraries/Errors.sol";
import { Math } from "@openzeppelin-5.0/contracts/utils/math/Math.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

contract YearnStakingDelegate is AccessControl, CurveRouterSwapper {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct RewardSplit {
        uint80 treasury;
        uint80 strategy;
        uint80 veYfi;
    }

    struct VaultRewards {
        uint128 accRewardsPerShare;
        uint128 lastRewardBlock;
    }

    struct UserInfo {
        uint128 balance;
        uint128 rewardDebt;
    }

    struct RouterParam {
        address[11] route;
        uint256[5][5] swapParams;
        address[5] pools;
    }

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");

    /// @notice Mapping of vault to gauge
    // slither-disable-next-line uninitialized-state
    mapping(address vault => address) public associatedGauge;
    // slither-disable-next-line uninitialized-state
    mapping(address user => mapping(address vault => UserInfo)) public userInfo;
    mapping(address vault => VaultRewards) public vaultRewardsInfo;

    RewardSplit public rewardSplit;
    // Curve router params for dYFI -> YFI swap
    RouterParam internal _routerParam;
    bool public shouldPerpetuallyLock;

    using SafeERC20 for IERC20;

    // solhint-disable-next-line var-name-mixedcase
    address private immutable _SNAPSHOT_DELEGATE_REGISTRY;
    address public immutable veYfi;
    address public immutable yfi;
    address public immutable dYfi;
    address public treasury;

    event LogUpdatePool(address indexed vault, uint128 lastRewardBlock, uint256 lpSupply, uint256 accRewardsPerShare);

    constructor(
        address _yfi,
        address _dYfi,
        address _veYfi,
        address _snapshotDelegateRegistry,
        address _curveRouter,
        address _treasury,
        address admin,
        address manager
    )
        CurveRouterSwapper(_curveRouter)
    {
        // Checks
        // check for zero addresses
        if (
            _yfi == address(0) || _dYfi == address(0) || _veYfi == address(0) || _curveRouter == address(0)
                || admin == address(0) || manager == address(0) || _treasury == address(0)
        ) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // set storage variables
        yfi = _yfi;
        dYfi = _dYfi;
        veYfi = _veYfi;
        treasury = _treasury;
        _SNAPSHOT_DELEGATE_REGISTRY = _snapshotDelegateRegistry;
        shouldPerpetuallyLock = true;
        _setRewardSplit(0, 1e18, 0); // 0% to treasury, 100% to compound, 0% to veYFI for relocking
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);

        // Interactions
        // max approve YFI to veYFI so we can lock it later
        IERC20(yfi).approve(veYfi, type(uint256).max);
        _approveTokenForSwap(dYfi);
    }

    /// @notice Harvest rewards from the gauge and distribute to treasury, compound, and veYFI
    /// @return userRewardsAmount amount of rewards harvested for the msg.sender
    function harvest(address vault) external returns (uint256) {
        VaultRewards memory vaultRewards = vaultRewardsInfo[vault];
        UserInfo storage user = userInfo[msg.sender][vault];
        uint256 totalRewardsAmount = 0;
        uint256 userRewardsAmount = 0;

        // if this is after lastRewardBlock, harvest and update vaultRewards
        if (block.number > vaultRewards.lastRewardBlock) {
            address gauge = associatedGauge[vault];
            if (gauge == address(0)) {
                revert Errors.NoAssociatedGauge();
            }
            uint256 lpSupply = IERC20(gauge).balanceOf(address(this));
            // get rewards from the gauge
            totalRewardsAmount = IERC20(dYfi).balanceOf(address(this));
            IGauge(gauge).getReward(address(this));
            totalRewardsAmount = IERC20(dYfi).balanceOf(address(this)) - totalRewardsAmount;
            // update accRewardsPerShare if there are tokens in the gauge
            if (lpSupply > 0) {
                vaultRewards.accRewardsPerShare += uint128(totalRewardsAmount * rewardSplit.strategy / lpSupply);
            }
            vaultRewards.lastRewardBlock = uint128(block.number);
            vaultRewardsInfo[vault] = vaultRewards;

            emit LogUpdatePool(vault, vaultRewards.lastRewardBlock, lpSupply, vaultRewards.accRewardsPerShare);

            // calculate pending rewards for the user
            uint128 accumulatedRewards = uint128(uint256(user.balance) * vaultRewards.accRewardsPerShare / 1e18);
            userRewardsAmount = accumulatedRewards - user.rewardDebt;
            user.rewardDebt = accumulatedRewards;

            // transfer pending rewards to the user
            if (userRewardsAmount != 0) {
                IERC20(dYfi).safeTransfer(msg.sender, userRewardsAmount);
            }

            // Do other actions based on configured parameters
            IERC20(dYfi).safeTransfer(treasury, totalRewardsAmount * uint256(rewardSplit.treasury) / 1e18);
            uint256 dYfiToSwapAndLock = totalRewardsAmount * uint256(rewardSplit.veYfi) / 1e18;
            if (dYfiToSwapAndLock != 0) {
                uint256 yfiAmount = _swapDYfiToYfi(dYfiToSwapAndLock);
                _lockYfi(yfiAmount);
            }
        }
        return userRewardsAmount;
    }

    function depositToGauge(address vault, uint256 amount) external {
        // Checks
        address gauge = associatedGauge[vault];
        if (gauge == address(0)) {
            revert Errors.NoAssociatedGauge();
        }
        // Effects
        UserInfo storage user = userInfo[msg.sender][vault];
        user.balance += uint128(amount);
        user.rewardDebt += uint128(amount * vaultRewardsInfo[vault].accRewardsPerShare / 1e18);
        // Interactions
        IERC20(vault).transferFrom(msg.sender, address(this), amount);
        IGauge(gauge).deposit(amount, address(this));
    }

    function withdrawFromGauge(address vault, uint256 amount) external {
        // Checks
        address gauge = associatedGauge[vault];
        if (gauge == address(0)) {
            revert Errors.NoAssociatedGauge();
        }
        // Effects
        UserInfo storage user = userInfo[msg.sender][vault];
        user.balance -= uint128(amount);
        user.rewardDebt -= uint128(amount * vaultRewardsInfo[vault].accRewardsPerShare / 1e18);
        // Interactions
        IGauge(gauge).withdraw(amount, address(msg.sender), address(this));
    }

    function _swapDYfiToYfi(uint256 swapAmount) internal returns (uint256) {
        return _swap(_routerParam.route, _routerParam.swapParams, swapAmount, 0, _routerParam.pools, address(this));
    }

    function _lockYfi(uint256 amount) internal {
        if (shouldPerpetuallyLock) {
            IVotingYFI(veYfi).modify_lock(amount, block.timestamp + 4 * 365 days + 4 weeks, address(this));
        }
    }

    // Transfer amount of YFI from msg.sender and locks
    function lockYfi(uint256 amount) external {
        // Checks
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        // Interactions
        IERC20(yfi).safeTransferFrom(msg.sender, address(this), amount);
        _lockYfi(amount);
    }

    function setRouterParams(RouterParam calldata routerParam) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _routerParam = routerParam;
    }

    /// @notice Set perpetual lock status
    /// @param _shouldPerpetuallyLock if true, lock YFI for 4 years after each harvest
    function setPerpetualLock(bool _shouldPerpetuallyLock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        shouldPerpetuallyLock = _shouldPerpetuallyLock;
    }

    /// @notice Set treasury address. This address will receive a portion of the rewards
    /// @param _treasury address to receive rewards
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Checks
        if (_treasury == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        treasury = _treasury;
    }

    function setAssociatedGauge(address vault, address gauge) external onlyRole(MANAGER_ROLE) {
        // Checks
        if (gauge == address(0) || vault == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        associatedGauge[vault] = gauge;
        // Interactions
        IERC20(vault).approve(gauge, type(uint256).max);
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

    function _setRewardSplit(uint80 treasuryPct, uint80 compoundPct, uint80 veYfiPct) internal {
        if (uint256(treasuryPct) + compoundPct + veYfiPct != 1e18) {
            revert Errors.InvalidRewardSplit();
        }
        rewardSplit = RewardSplit(treasuryPct, compoundPct, veYfiPct);
    }

    /// @notice Set the reward split percentages
    /// @param treasuryPct percentage of rewards to treasury
    /// @param compoundPct percentage of rewards to compound
    /// @param veYfiPct percentage of rewards to veYFI
    /// @dev Sum of percentages must equal to 1e18
    function setRewardSplit(uint80 treasuryPct, uint80 compoundPct, uint80 veYfiPct) external onlyRole(MANAGER_ROLE) {
        _setRewardSplit(treasuryPct, compoundPct, veYfiPct);
    }

    /// @notice early unlock veYFI
    function earlyUnlock(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Checks
        if (shouldPerpetuallyLock) {
            revert Errors.PerpetualLockEnabled();
        }
        // Interactions
        IVotingYFI.Withdrawn memory withdrawn = IVotingYFI(veYfi).withdraw();
        IERC20(yfi).transfer(to, withdrawn.amount);
    }

    /// @notice Rescue any ERC20 tokens that are stuck in this contract
    /// @dev Only callable by owner
    /// @param token address of the ERC20 token to rescue. Use zero address for ETH
    /// @param to address to send the tokens to
    /// @param balance amount of tokens to rescue. Use zero to rescue all
    function rescue(IERC20 token, address to, uint256 balance) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(token) == address(0)) {
            // for Ether
            uint256 totalBalance = address(this).balance;
            balance = balance == 0 ? totalBalance : Math.min(totalBalance, balance);
            require(balance > 0, "trying to send 0 ETH");
            // slither-disable-next-line arbitrary-send
            (bool success,) = to.call{ value: balance }("");
            require(success, "ETH transfer failed");
        } else {
            // any other erc20
            uint256 totalBalance = token.balanceOf(address(this));
            balance = balance == 0 ? totalBalance : Math.min(totalBalance, balance);
            require(balance > 0, "trying to send 0 balance");
            token.safeTransfer(to, balance);
        }
    }
}

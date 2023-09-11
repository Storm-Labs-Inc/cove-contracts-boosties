// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/IVotingYFI.sol";
import { IGauge } from "src/interfaces/IGauge.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Errors } from "src/libraries/Errors.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract YearnStakingDelegate is AccessControl {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct RewardSplit {
        uint80 treasury;
        uint80 compound;
        uint80 veYfi;
    }

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Mapping of vault to gauge
    // slither-disable-next-line uninitialized-state
    mapping(address vault => address gauge) public associatedGauge;
    // slither-disable-next-line uninitialized-state
    mapping(address user => mapping(address vault => uint256 balance)) public balances;

    RewardSplit public rewardSplit;
    bool public shouldPerpetuallyLock;

    using SafeERC20 for IERC20;

    address public immutable veYfi;
    address public immutable yfi;
    address public immutable oYfi;

    constructor(address _yfi, address _oYfi, address _veYfi, address admin, address manager) {
        // Checks
        // check for zero addresses
        if (
            _yfi == address(0) || _oYfi == address(0) || _veYfi == address(0) || admin == address(0)
                || manager == address(0)
        ) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // set storage variables
        yfi = _yfi;
        oYfi = _oYfi;
        veYfi = _veYfi;
        shouldPerpetuallyLock = true;
        _setRewardSplit(0, 0, 1e18);
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(MANAGER_ROLE, admin);
        _setupRole(MANAGER_ROLE, manager);

        // Interactions
        // max approve YFI to veYFI so we can lock it later
        IERC20(yfi).approve(veYfi, type(uint256).max);
    }

    function harvest(address vault) external {
        // TODO: implement harvest
        address strategy = msg.sender;
        address treasury = address(0);
        IGauge(associatedGauge[vault]).getReward(address(this));
        uint256 rewardAmount = IERC20(oYfi).balanceOf(address(this));
        // Do actions based on configured parameters
        IERC20(oYfi).transfer(treasury, rewardAmount * uint256(rewardSplit.treasury) / 1e18);
        IERC20(oYfi).transfer(strategy, rewardAmount * uint256(rewardSplit.compound) / 1e18);
        uint256 yfiAmount = _swapOYfiToYfi(rewardAmount * uint256(rewardSplit.veYfi) / 1e18);
        _lockYfi(yfiAmount);
    }

    function depositToGauge(address vault, uint256 amount) external {
        balances[msg.sender][vault] += amount;
        IERC20(vault).transferFrom(msg.sender, address(this), amount);
        IERC20(vault).approve(associatedGauge[vault], amount);
        IGauge(associatedGauge[vault]).deposit(amount, address(this));
    }

    function withdrawFromGauge(address vault, uint256 amount) external {
        balances[msg.sender][vault] -= amount;
        IGauge(associatedGauge[vault]).withdraw(amount, address(msg.sender), address(this));
    }

    // Swaps any held oYFI to YFI using oYFI/YFI path on Curve
    function swapOYFIToYFI() external onlyRole(MANAGER_ROLE) {
        _swapOYfiToYfi(0);
    }

    function _swapOYfiToYfi(uint256 oYfiAmount) internal returns (uint256) {
        return 0;
    }

    function _lockYfi(uint256 amount) internal {
        if (shouldPerpetuallyLock) {
            IVotingYFI(veYfi).modify_lock(amount, block.timestamp + 4 * 365 days + 1 weeks, address(this));
        }
    }

    // Lock all YFI and increase lock time
    function lockYfi() external onlyRole(MANAGER_ROLE) {
        _lockYfi(IERC20(yfi).balanceOf(address(this)));
    }

    // Transfer amount of YFI from msg.sender and locks
    function lockYfi(uint256 amount) public {
        IERC20(yfi).safeTransferFrom(msg.sender, address(this), amount);
        _lockYfi(amount);
    }

    /// @notice Set perpetual lock status
    /// @param _shouldPerpetuallyLock if true, lock YFI for 4 years after each harvest
    function setPerpetualLock(bool _shouldPerpetuallyLock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        shouldPerpetuallyLock = _shouldPerpetuallyLock;
    }

    function _setRewardSplit(uint80 treasuryPct, uint80 compoundPct, uint80 veYfiPct) internal {
        require(treasuryPct + compoundPct + veYfiPct == 1e18, "Split must add up to 100%");
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
        IVotingYFI(veYfi).withdraw();
        IERC20(yfi).transfer(to, IERC20(yfi).balanceOf(address(this)));
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

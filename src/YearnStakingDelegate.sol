// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/IVotingYFI.sol";
import { IGauge } from "src/interfaces/IGauge.sol";

contract YearnStakingDelegate {
    /// @notice Mapping of vault to gauge
    mapping(address vault => address gauge) public associatedGauge;
    mapping(address user => mapping(address vault => uint256 balance)) public balances;
    address public manager;
    address public oYFI;

    struct RewardSplit {
        uint256 treasury;
        uint256 compound;
        uint256 veYfi;
    }

    RewardSplit public rewardSplit;
    bool public shouldPerpetuallyLock = true;

    using SafeERC20 for IERC20;

    address public immutable veYfi;
    address public immutable yfi;
    address public immutable oYfi;

    constructor(address _yfi, address _oYfi, address _veYfi) {
        yfi = _yfi;
        oYfi = _oYfi;
        veYfi = _veYfi;

        _setRewardSplit(0, 0, 1e18);
        // Max approve YFI to veYFI so we can lock it later
        IERC20(yfi).approve(veYfi, type(uint256).max);
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager can call this function.");
        _;
    }

    function harvest(address vault) external {
        // TODO: implement harvest
        address strategy = msg.sender;
        address treasury = address(0);
        IGauge(associatedGauge[vault]).getReward(address(this));
        uint256 rewardAmount = IERC20(oYfi).balanceOf(address(this));
        // Do actions based on configured parameters
        IERC20(oYFI).transfer(treasury, rewardAmount * rewardSplit.treasury / 1e18);
        IERC20(oYFI).transfer(strategy, rewardAmount * rewardSplit.compound / 1e18);
        _swapOYfiToYfi(rewardAmount * rewardSplit.veYfi / 1e18);
        _lockYfi();
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
    function swapOYFIToYFI() external onlyManager {
        _swapOYfiToYfi(0);
    }

    function _swapOYfiToYfi(uint256 oYfiAmount) internal { }

    function _lockYfi() internal {
        if (shouldPerpetuallyLock) {
            IVotingYFI(veYfi).modify_lock(
                IERC20(yfi).balanceOf(address(this)), block.timestamp + 365 * 4 days, address(this)
            );
        }
    }

    // Lock all YFI and increase lock time
    function lockYFI() external onlyManager {
        _lockYfi();
    }

    /// @notice Set perpetual lock status
    /// @param _shouldPerpetuallyLock if true, lock YFI for 4 years after each harvest
    function setPerpetualLock(bool _shouldPerpetuallyLock) external onlyManager {
        shouldPerpetuallyLock = _shouldPerpetuallyLock;
    }

    function _setRewardSplit(uint256 treasuryPct, uint256 compoundPct, uint256 veYfiPct) internal {
        require(treasuryPct + compoundPct + veYfiPct == 1e18, "Split must add up to 100%");
        rewardSplit = RewardSplit(treasuryPct, compoundPct, veYfiPct);
    }

    /// @notice Set the reward split percentages
    /// @param treasuryPct percentage of rewards to treasury
    /// @param compoundPct percentage of rewards to compound
    /// @param veYfiPct percentage of rewards to veYFI
    /// @dev Sum of percentages must equal to 1e18
    function setRewardSplit(uint256 treasuryPct, uint256 compoundPct, uint256 veYfiPct) external onlyManager {
        _setRewardSplit(treasuryPct, compoundPct, veYfiPct);
    }
}

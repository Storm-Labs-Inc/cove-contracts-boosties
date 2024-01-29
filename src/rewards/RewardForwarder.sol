// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { AccessControlUpgradeable } from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBaseRewardsGauge } from "../interfaces/rewards/IBaseRewardsGauge.sol";

contract RewardForwarder is AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    uint256 private constant _MAX_BPS = 10_000;

    address public rewardDestination;
    address public treasury;
    mapping(address => uint256) public treasuryBps;

    error ZeroAddress();
    error InvalidTreasuryBps();

    event TreasurySet(address treasury);
    event TreasuryBpsSet(address rewardToken, uint256 treasuryBps);

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin_, address treasury_, address destination_) external initializer {
        if (destination_ == address(0)) revert ZeroAddress();
        rewardDestination = destination_;
        _setTreasury(treasury_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    function approveRewardToken(address rewardToken) external {
        IERC20(rewardToken).forceApprove(rewardDestination, type(uint256).max);
    }

    function forwardRewardToken(address rewardToken) external {
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        uint256 treasuryAmount = balance * treasuryBps[rewardToken] / _MAX_BPS;
        if (balance > 0) {
            if (treasuryAmount > 0) {
                IERC20(rewardToken).safeTransfer(treasury, treasuryAmount);
            }
            IBaseRewardsGauge(rewardDestination).depositRewardToken(rewardToken, balance - treasuryAmount);
        }
    }

    // function rescue(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    //     _rescue(token, to, amount);
    // }

    function setTreasury(address treasury_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTreasury(treasury_);
    }

    function setTreasuryBps(address rewardToken, uint256 treasuryBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTreasuryBps(rewardToken, treasuryBps_);
    }

    function _setTreasury(address treasury_) internal {
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    function _setTreasuryBps(address rewardToken, uint256 treasuryBps_) internal {
        if (treasuryBps_ > _MAX_BPS) {
            revert InvalidTreasuryBps();
        }
        treasuryBps[rewardToken] = treasuryBps_;
        emit TreasuryBpsSet(rewardToken, treasuryBps_);
    }
}

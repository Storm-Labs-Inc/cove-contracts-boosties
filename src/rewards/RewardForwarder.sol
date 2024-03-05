// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { AccessControlEnumerableUpgradeable } from
    "@openzeppelin-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBaseRewardsGauge } from "../interfaces/rewards/IBaseRewardsGauge.sol";

/**
 * @title Reward Forwarder
 * @notice Forwards reward tokens from the contract to a designated destination and treasury with specified basis
 * points.
 * @dev This contract is responsible for forwarding reward tokens to a rewards gauge and optionally to a treasury.
 * It allows for a portion of the rewards to be redirected to a treasury address.
 */
contract RewardForwarder is AccessControlEnumerableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 private constant _MAX_BPS = 10_000;

    address public rewardDestination;
    address public treasury;
    mapping(address => uint256) public treasuryBps;

    error ZeroAddress();
    error InvalidTreasuryBps();

    event TreasurySet(address treasury);
    event TreasuryBpsSet(address rewardToken, uint256 treasuryBps);

    constructor() payable {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract, setting up roles and the initial configuration for the reward destination and
     * treasury.
     * @param admin_ The address that will be granted the default admin role.
     * @param treasury_ The address of the treasury to which a portion of rewards may be sent.
     * @param destination_ The destination address where the majority of rewards will be forwarded.
     */
    function initialize(address admin_, address treasury_, address destination_) external initializer {
        if (destination_ == address(0)) revert ZeroAddress();
        rewardDestination = destination_;
        _setTreasury(treasury_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /**
     * @notice Approves the reward destination to spend the specified reward token.
     * @dev Grants unlimited approval to the reward destination for the specified reward token.
     * @param rewardToken The address of the reward token to approve.
     */
    function approveRewardToken(address rewardToken) external {
        IERC20(rewardToken).forceApprove(rewardDestination, type(uint256).max);
    }

    /**
     * @notice Forwards the specified reward token to the reward destination and treasury.
     * @dev Forwards all balance of the specified reward token to the reward destination, minus the portion for the
     * treasury.
     * @param rewardToken The address of the reward token to forward.
     */
    function forwardRewardToken(address rewardToken) public {
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        uint256 treasuryAmount = balance * treasuryBps[rewardToken] / _MAX_BPS;
        if (balance > 0) {
            if (treasuryAmount > 0) {
                IERC20(rewardToken).safeTransfer(treasury, treasuryAmount);
            }
            IBaseRewardsGauge(rewardDestination).depositRewardToken(rewardToken, balance - treasuryAmount);
        }
    }

    /**
     * @notice Sets the treasury address.
     * @dev Can only be called by an address with the default admin role.
     * @param treasury_ The new treasury address.
     */
    function setTreasury(address treasury_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTreasury(treasury_);
    }

    /**
     * @notice Sets the basis points for the treasury for a specific reward token.
     * @dev This function first calls forwardRewardToken before setting the new rate to ensure that it only applies to
     *      future rewards. Can only be called by an address with the default admin role.
     * @param rewardToken The address of the reward token for which to set the basis points.
     * @param treasuryBps_ The number of basis points to allocate to the treasury.
     */
    function setTreasuryBps(address rewardToken, uint256 treasuryBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // slither-disable-next-line reentrancy-benign,reentrancy-events
        this.forwardRewardToken(rewardToken);
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
        emit TreasuryBpsSet(rewardToken, treasuryBps_);
        treasuryBps[rewardToken] = treasuryBps_;
    }
}

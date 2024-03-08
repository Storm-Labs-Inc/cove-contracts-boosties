// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBaseRewardsGauge } from "../interfaces/rewards/IBaseRewardsGauge.sol";
import { Errors } from "src/libraries/Errors.sol";
import { Initializable } from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";

/**
 * @title Reward Forwarder
 * @notice Forwards reward tokens from the contract to a designated destination and treasury with specified basis
 * points.
 * @dev This contract is responsible for forwarding reward tokens to a rewards gauge and optionally to a treasury.
 * It allows for a portion of the rewards to be redirected to a treasury address.
 */
contract RewardForwarder is Initializable {
    using SafeERC20 for IERC20;

    /// @dev Maximum basis points used for calculating treasury share of rewards.
    uint256 private constant _MAX_BPS = 10_000;

    /// @notice Address where the majority of rewards will be forwarded.
    address public rewardDestination;
    /// @notice Address of the treasury to which a portion of rewards may be sent.
    address public treasury;
    /// @notice Mapping of reward token addresses to their respective basis points for treasury share.
    /// @dev Basis points are calculated out of _MAX_BPS.
    mapping(address => uint256) public treasuryBps;

    /// @notice Error indicating that a zero address was provided where it is not allowed.
    error ZeroAddress();
    /// @notice Error indicating that the provided basis points for the treasury share are invalid.
    error InvalidTreasuryBps();

    /*
     * @notice Event emitted when the treasury address is set.
     * @param treasury The new treasury address.
     */
    event TreasurySet(address indexed treasury);
    /*
     * @notice Event emitted when the basis points for the treasury share of a reward token are set.
     * @param rewardToken The address of the reward token.
     * @param treasuryBps The new basis points for the treasury share.
     */
    event TreasuryBpsSet(address indexed rewardToken, uint256 treasuryBps);

    /// @dev Constructor that disables initializers to prevent further initialization.
    constructor() payable {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the specified reward destination.
     * @param destination_ The destination address where the rewards will be forwarded.
     */
    function initialize(address destination_) external initializer {
        if (destination_ == address(0)) revert Errors.ZeroAddress();
        rewardDestination = destination_;
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
     * @notice Forwards the specified reward token to the reward destination.
     * @dev Forwards all balance of the specified reward token to the reward destination
     * @param rewardToken The address of the reward token to forward.
     */
    function forwardRewardToken(address rewardToken) public {
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        if (balance > 0) {
            IBaseRewardsGauge(rewardDestination).depositRewardToken(rewardToken, balance);
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBaseRewardsGauge } from "../interfaces/rewards/IBaseRewardsGauge.sol";
import { Errors } from "src/libraries/Errors.sol";
import { Initializable } from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";

/**
 * @title Reward Forwarder Contract
 * @notice This contract is responsible for forwarding rewards from various sources to a specified destination.
 * It allows for the approval and forwarding of reward tokens to a designated address, which can be a contract
 * that further distributes or processes the rewards. The contract is initialized with the address of the
 * reward destination and includes functionality to approve reward tokens for spending and to forward them.
 * @dev The contract uses the OpenZeppelin SafeERC20 library to interact with ERC20 tokens safely. It inherits
 * from OpenZeppelin's Initializable contract to ensure that initialization logic is executed only once.
 */
contract RewardForwarder is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Constant role for the manager of the contract, who can forward rewards.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @notice Address where the majority of rewards will be forwarded.
    address public rewardDestination;

    /// @dev Constructor that disables initializers to prevent further initialization.
    constructor() payable {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the specified reward destination.
     * @param destination_ The destination address where the rewards will be forwarded.
     */
    function initialize(address destination_, address admin, address manager) external initializer {
        if (destination_ == address(0) || admin == address(0) || manager == address(0)) revert Errors.ZeroAddress();
        rewardDestination = destination_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
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
    function forwardRewardToken(address rewardToken) public onlyRole(MANAGER_ROLE) {
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        if (balance > 0) {
            IBaseRewardsGauge(rewardDestination).depositRewardToken(rewardToken, balance);
        }
    }
}

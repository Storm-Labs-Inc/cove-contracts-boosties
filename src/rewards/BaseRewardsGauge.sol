// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {
    ERC4626Upgradeable,
    ERC20Upgradeable,
    IERC20Upgradeable as IERC20,
    IERC20MetadataUpgradeable as IERC20Metadata,
    SafeERC20Upgradeable as SafeERC20
} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IBaseRewardsGauge } from "../interfaces/rewards/IBaseRewardsGauge.sol";

/**
 * @title Base Rewards Gauge
 * @notice Gauge contract for managing and distributing reward tokens to stakers.
 * @dev This contract handles the accounting of reward tokens, allowing users to claim their accrued rewards.
 * It supports multiple reward tokens and allows for the addition of new rewards by authorized distributors.
 */
abstract contract BaseRewardsGauge is
    IBaseRewardsGauge,
    ERC4626Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    struct Reward {
        address distributor;
        uint256 periodFinish;
        uint256 rate;
        uint256 lastUpdate;
        uint256 integral;
        uint256 leftOver;
    }

    uint256 public constant MAX_REWARDS = 8;
    uint256 internal constant _WEEK = 1 weeks;
    uint256 internal constant _PRECISION = 1e18;
    bytes32 internal constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // For tracking external rewards
    address[] public rewardTokens;
    mapping(address => Reward) internal _rewardData;
    // claimant -> default reward receiver
    mapping(address => address) public rewardsReceiver;
    // reward token -> claiming address -> integral
    mapping(address => mapping(address => uint256)) public rewardIntegralFor;
    // user -> token -> [uint128 claimable amount][uint128 claimed amount]
    mapping(address => mapping(address => uint256)) public claimData;

    error CannotRedirectForAnotherUser();
    error MaxRewardsReached();
    error RewardTokenAlreadyAdded();
    error Unauthorized();
    error DistributorNotSet();
    error InvalidDistributorAddress();
    error RewardAmountTooLow();
    error ZeroAddress();
    error RewardCannotBeAsset();

    constructor() payable {
        _disableInitializers();
    }

    // slither-disable-next-line naming-convention
    function __BaseRewardsGauge_init(address asset_) internal onlyInitializing {
        if (asset_ == address(0)) {
            revert ZeroAddress();
        }
        string memory name_ = string.concat(IERC20Metadata(asset_).name(), " Cove Rewards Gauge");
        string memory symbol_ = string.concat(IERC20Metadata(asset_).symbol(), "-gauge");

        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __ERC4626_init(IERC20(asset_));
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(_MANAGER_ROLE, msg.sender);
    }

    /**
     * @notice Get the number of decimals for this token.
     * @return uint8 Number of decimals
     */
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }

    /**
     * @notice Get the number of already-claimed reward tokens for a user
     * @param addr Account to get reward amount for
     * @param token Token to get reward amount for
     * @return uint256 Total amount of `_token` already claimed by `_addr`
     */
    function claimedReward(address addr, address token) external view returns (uint256) {
        return claimData[addr][token] % (2 ** 128);
    }

    /**
     * @notice Get the number of claimable reward tokens for a user
     * @param user Account to get reward amount for
     * @param rewardToken Token to get reward amount for
     * @return uint256 Claimable reward token amount
     */
    function claimableReward(address user, address rewardToken) external view returns (uint256) {
        Reward storage reward = _rewardData[rewardToken];
        uint256 integral = reward.integral;
        uint256 currentTotalSupply = totalSupply();
        if (currentTotalSupply != 0) {
            uint256 lastUpdate = Math.min(block.timestamp, reward.periodFinish);
            uint256 duration = lastUpdate - reward.lastUpdate;
            integral = integral + ((duration * reward.rate * _PRECISION) / currentTotalSupply);
        }

        uint256 integralFor = rewardIntegralFor[rewardToken][user];
        uint256 newClaimable = balanceOf(user) * (integral - integralFor) / _PRECISION;

        return (claimData[user][rewardToken] >> 128) + newClaimable;
    }

    /**
     * @notice Get the reward data for a reward token
     * @param rewardToken token address to get reward data for
     * @return Reward struct for the reward token
     */
    function getRewardData(address rewardToken) external view returns (Reward memory) {
        return _rewardData[rewardToken];
    }

    /**
     * @notice Set the default reward receiver for the caller.
     * @dev When set to address(0), rewards are sent to the caller
     * @param receiver Receiver address for any rewards claimed via `claimRewards`
     */
    function setRewardsReceiver(address receiver) external {
        rewardsReceiver[msg.sender] = receiver;
    }

    /**
     * @notice Claim available reward tokens for `addr`
     * @param addr Address to claim for
     * @param receiver Address to transfer rewards to - if set to
     *                 address(0), uses the default reward receiver
     *                 for the caller
     */
    function claimRewards(address addr, address receiver) external nonReentrant {
        if (receiver != address(0)) {
            if (addr != msg.sender) {
                revert CannotRedirectForAnotherUser();
            }
        }
        _checkpointRewards(addr, totalSupply(), true, receiver);
    }

    /**
     * @notice Adds a new reward token to be distributed by this contract.
     * @dev Adds a new reward token to the contract, enabling it to be claimed by users.
     * Can only be called by an address with the manager role.
     * @param rewardToken The address of the reward token to add.
     * @param distributor The address of the distributor for the reward token.
     */
    function addReward(address rewardToken, address distributor) external {
        _checkRole(_MANAGER_ROLE);
        if (rewardToken == address(0) || distributor == address(0)) {
            revert ZeroAddress();
        }
        if (rewardToken == asset()) {
            revert RewardCannotBeAsset();
        }

        uint256 rewardCount = rewardTokens.length;
        if (rewardCount >= MAX_REWARDS) {
            revert MaxRewardsReached();
        }

        Reward storage reward = _rewardData[rewardToken];
        if (reward.distributor != address(0)) {
            revert RewardTokenAlreadyAdded();
        }

        reward.distributor = distributor;
        rewardTokens.push(rewardToken);
    }

    /**
     * @notice Set the reward distributor for a reward token. Only the current distributor or an address with the
     * manager role can call this.
     * @param rewardToken address of the reward token
     * @param distributor address of the distributor contract
     */
    function setRewardDistributor(address rewardToken, address distributor) external {
        Reward storage reward = _rewardData[rewardToken];
        address currentDistributor = reward.distributor;

        if (!(msg.sender == currentDistributor || hasRole(_MANAGER_ROLE, msg.sender))) {
            revert Unauthorized();
        }
        if (currentDistributor == address(0)) {
            revert DistributorNotSet();
        }
        if (distributor == address(0)) {
            revert InvalidDistributorAddress();
        }

        reward.distributor = distributor;
    }

    /**
     * @notice Deposit reward tokens into the gauge. Only the distributor or an address with the manager role can call
     * this.
     * @param rewardToken address of the reward token
     * @param amount amount of reward tokens to deposit
     */
    function depositRewardToken(address rewardToken, uint256 amount) external nonReentrant {
        Reward storage reward = _rewardData[rewardToken];
        if (!(msg.sender == reward.distributor || hasRole(_MANAGER_ROLE, msg.sender))) {
            revert Unauthorized();
        }

        _checkpointRewards(address(0), totalSupply(), false, address(0));
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 periodFinish = reward.periodFinish;
        uint256 newRate = 0;
        // slither-disable-next-line timestamp
        uint256 leftOver = _rewardData[rewardToken].leftOver;
        if (block.timestamp < periodFinish) {
            uint256 remaining = periodFinish - block.timestamp;
            leftOver = leftOver + remaining * _rewardData[rewardToken].rate;
        }
        amount = amount + leftOver;
        newRate = amount / _WEEK;
        // slither-disable-next-line timestamp,incorrect-equality
        if (newRate == 0) {
            revert RewardAmountTooLow();
        }
        reward.rate = newRate;
        reward.lastUpdate = block.timestamp;
        reward.periodFinish = block.timestamp + _WEEK;
        // slither-disable-next-line weak-prng
        reward.leftOver = amount % _WEEK;
    }

    /**
     * @notice Returns the total amount of the underlying asset that the gauge has.
     * @dev Provides the total assets managed by the gauge, which is the same as the total supply of the gauge's shares.
     *      This is used to calculate the value of each share.
     * @return The total assets held by the gauge.
     */
    function totalAssets() public view virtual override(ERC4626Upgradeable) returns (uint256) {
        return totalSupply();
    }

    /**
     * @dev Internal function to claim pending rewards and update reward accounting for a user.
     *      This function is called during any claim operation and when rewards are deposited.
     *      It iterates through all reward tokens to update user rewards and optionally claims them.
     * @param user The user address to checkpoint rewards for. If set to address(0), only updates the global state.
     * @param totalSupply_ The current total supply of the staking token.
     * @param claim If true, rewards will be transferred to the user or their designated receiver.
     * @param receiver The address to send claimed rewards to. If set to address(0), sends to the user or their default
     * receiver.
     */
    function _checkpointRewards(address user, uint256 totalSupply_, bool claim, address receiver) internal {
        uint256 userBalance = 0;
        if (user != address(0)) {
            userBalance = balanceOf(user);
            if (claim) {
                if (receiver == address(0)) {
                    // if receiver is not explicitly declared, check if a default receiver is set
                    receiver = rewardsReceiver[user];
                    receiver = receiver == address(0) ? user : receiver;
                }
            }
        }
        uint256 rewardCount = rewardTokens.length;
        address[] memory tokens = rewardTokens;
        for (uint256 i = 0; i < rewardCount;) {
            address token = tokens[i];
            _updateReward(token, totalSupply_);
            if (user != address(0)) {
                _processUserReward(token, user, userBalance, claim, receiver);
            }

            /// @dev The unchecked block is used here because the loop index `i` is simply incremented in each
            /// iteration, ensuring that `i` will not exceed the length of the array and cause an overflow. Underflow is
            /// not a concern as `i` is initialized to 0 and only incremented.
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Internal function to update the reward accounting for a given token.
     *      This updates the accumulated reward per token and the timestamp of the last reward update.
     *      It is called by `_checkpointRewards` to ensure the reward state is up to date before any interactions.
     * @param token The address of the reward token to update accounting for.
     * @param totalSupply_ The current total supply of the staking token, used to calculate the rewards per token.
     */
    function _updateReward(address token, uint256 totalSupply_) internal {
        Reward storage reward = _rewardData[token];
        uint256 lastUpdate = Math.min(block.timestamp, reward.periodFinish);
        uint256 duration = lastUpdate - reward.lastUpdate;
        // slither-disable-next-line timestamp
        if (duration > 0) {
            if (totalSupply_ > 0) {
                reward.integral = reward.integral + (duration * reward.rate * _PRECISION / totalSupply_);
                reward.lastUpdate = lastUpdate;
            }
        }
    }

    /**
     * @dev Internal function to process user rewards, updating the claimable and claimed amounts.
     * @param token The address of the reward token to process.
     * @param user The user address to process rewards for.
     * @param userBalance The current balance of the user.
     * @param claim Whether to claim the rewards (transfer them to the user).
     * @param receiver The address to send claimed rewards to.
     */
    function _processUserReward(
        address token,
        address user,
        uint256 userBalance,
        bool claim,
        address receiver
    )
        internal
    {
        uint256 integral = _rewardData[token].integral;
        uint256 integralFor = rewardIntegralFor[token][user];
        uint256 newClaimable = 0;
        // slither-disable-next-line timestamp
        if (integral > integralFor) {
            newClaimable = userBalance * (integral - integralFor) / _PRECISION;
            rewardIntegralFor[token][user] = integral;
        }

        uint256 data = claimData[user][token];
        uint256 totalClaimable = (data >> 128) + newClaimable;
        uint256 totalClaimed = data % (2 ** 128);

        if (totalClaimable > 0) {
            claimData[user][token] = claim ? totalClaimed + totalClaimable : totalClaimed + (totalClaimable << 128);

            if (claim) {
                IERC20(token).safeTransfer(receiver, totalClaimable);
            }
        }
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes minting and burning.
     * @param from The address which is transferring tokens.
     * @param to The address which is receiving tokens.
     * @param amount The amount of tokens being transferred.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable) {
        uint256 totalSupply_ = totalSupply();
        _checkpointRewards(from, totalSupply_, false, address(0));
        _checkpointRewards(to, totalSupply_, false, address(0));
        super._beforeTokenTransfer(from, to, amount);
    }
}

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
 * @title BaseRewardsGauge
 * @notice Solidity implementation of a tokenized liquidity gauge with support for multi rewards distribution
 */
contract BaseRewardsGauge is
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
    }

    uint256 public constant MAX_REWARDS = 8;
    uint256 private constant _WEEK = 1 weeks;
    uint256 private constant _PRECISION = 1e18;
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // For tracking external rewards
    address[] public rewardTokens;
    mapping(address => Reward) public rewardData;
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

    event LogString(string);

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param asset_ Address of the asset token that will be deposited
     */
    function initialize(address asset_) public virtual initializer {
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
        uint256 integral = rewardData[rewardToken].integral;
        uint256 currentTotalSupply = totalSupply();
        if (currentTotalSupply != 0) {
            uint256 lastUpdate = Math.min(block.timestamp, rewardData[rewardToken].periodFinish);
            uint256 duration = lastUpdate - rewardData[rewardToken].lastUpdate;
            integral += (duration * rewardData[rewardToken].rate * _PRECISION) / currentTotalSupply;
        }

        uint256 integralFor = rewardIntegralFor[rewardToken][user];
        uint256 newClaimable = balanceOf(user) * (integral - integralFor) / _PRECISION;

        return (claimData[user][rewardToken] >> 128) + newClaimable;
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
        if (receiver != address(0) && addr != msg.sender) {
            revert CannotRedirectForAnotherUser();
        }
        _checkpointRewards(addr, totalSupply(), true, receiver);
    }

    /**
     * @notice Set the active reward contract
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
        if (rewardData[rewardToken].distributor != address(0)) {
            revert RewardTokenAlreadyAdded();
        }

        rewardData[rewardToken].distributor = distributor;
        rewardTokens.push(rewardToken);
    }

    /**
     * @notice Set the reward distributor for a reward token. Only the current distributor or an address with the
     * manager role can call this.
     * @param rewardToken address of the reward token
     * @param distributor address of the distributor contract
     */
    function setRewardDistributor(address rewardToken, address distributor) external {
        address currentDistributor = rewardData[rewardToken].distributor;
        if (!(msg.sender == currentDistributor || hasRole(_MANAGER_ROLE, msg.sender))) {
            revert Unauthorized();
        }
        if (currentDistributor == address(0)) {
            revert DistributorNotSet();
        }
        if (distributor == address(0)) {
            revert InvalidDistributorAddress();
        }

        rewardData[rewardToken].distributor = distributor;
    }

    /**
     * @notice Deposit reward tokens into the gauge. Only the distributor or an address with the manager role can call
     * this.
     * @param rewardToken address of the reward token
     * @param amount amount of reward tokens to deposit
     */
    function depositRewardToken(address rewardToken, uint256 amount) external nonReentrant {
        if (msg.sender != rewardData[rewardToken].distributor) {
            revert Unauthorized();
        }

        _checkpointRewards(address(0), totalSupply(), false, address(0));
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 periodFinish = rewardData[rewardToken].periodFinish;
        uint256 newRate = 0;
        // slither-disable-next-line timestamp
        if (block.timestamp >= periodFinish) {
            newRate = amount / _WEEK;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardData[rewardToken].rate;
            newRate = (amount + leftover) / _WEEK;
        }
        // slither-disable-next-line timestamp
        if (newRate <= 0) {
            revert RewardAmountTooLow();
        }
        rewardData[rewardToken].rate = newRate;
        rewardData[rewardToken].lastUpdate = block.timestamp;
        rewardData[rewardToken].periodFinish = block.timestamp + _WEEK;
    }

    /**
     * @notice Claim pending rewards and checkpoint rewards for a user
     */
    function _checkpointRewards(address user, uint256 totalSupply_, bool claim, address receiver) internal {
        uint256 userBalance = 0;
        if (user != address(0)) {
            userBalance = balanceOf(user);
            if (claim && receiver == address(0)) {
                // if receiver is not explicitly declared, check if a default receiver is set
                receiver = rewardsReceiver[user];
                receiver = receiver == address(0) ? user : receiver;
            }
        }
        uint256 rewardCount = rewardTokens.length;
        for (uint256 i = 0; i < rewardCount; i++) {
            address token = rewardTokens[i];
            _updateReward(token, _totalSupply);
            if (_user != address(0)) {
                _processUserReward(token, _user, userBalance, _claim, receiver);
            }
        }
    }

    function _updateReward(address token, uint256 totalSupply_) internal {
        uint256 lastUpdate = Math.min(block.timestamp, rewardData[token].periodFinish);
        uint256 duration = lastUpdate - rewardData[token].lastUpdate;
        // slither-disable-next-line timestamp
        if (duration > 0 && totalSupply_ > 0) {
            rewardData[token].integral += duration * rewardData[token].rate * _PRECISION / totalSupply_;
            rewardData[token].lastUpdate = lastUpdate;
        }
    }

    function totalAssets() public view virtual override returns (uint256) {
        return totalSupply();
    }

    function _processUserReward(
        address token,
        address user,
        uint256 userBalance,
        bool claim,
        address receiver
    )
        internal
    {
        uint256 integral = rewardData[token].integral;
        uint256 integralFor = rewardIntegralFor[token][user];
        uint256 newClaimable = 0;
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

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        uint256 totalSupply_ = totalSupply();
        _checkpointRewards(from, totalSupply_, false, address(0));
        _checkpointRewards(to, totalSupply_, false, address(0));
        super._beforeTokenTransfer(from, to, amount);
    }
}

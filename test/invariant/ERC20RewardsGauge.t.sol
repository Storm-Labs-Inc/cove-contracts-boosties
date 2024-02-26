// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "@crytic/properties/contracts/util/Hevm.sol";
import { CryticERC4626PropertyTests } from "@crytic/properties/contracts/ERC4626/ERC4626PropertyTests.sol";
// this token _must_ be the vault's underlying asset
import { TestERC20Token } from "@crytic/properties/contracts/ERC4626/util/TestERC20Token.sol";
import { ERC20RewardsGauge, BaseRewardsGauge } from "src/rewards/ERC20RewardsGauge.sol";
import { Clones } from "@crytic/properties/lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/// @title ERC20RewardsGauge_EchidnaTest
/// @notice Echidna test contract for ERC20RewardsGauge
/// @dev This contract is used to test the additional properties of ERC20RewardsGauge
///     along with CryticERC4626PropertyTests.
contract ERC20RewardsGauge_EchidnaTest is CryticERC4626PropertyTests {
    BaseRewardsGauge internal _rewardsGauge;
    TestERC20Token[8] internal _rewards;

    mapping(address => mapping(address => uint256)) internal _claimed;

    uint256 internal constant _MAX_REWARDS = 8;

    constructor() {
        TestERC20Token _asset = new TestERC20Token("Test Token", "TT", 18);
        ERC20RewardsGauge gaugeImpl = new ERC20RewardsGauge();
        // Initialize the gauge with the asset token
        _rewardsGauge = ERC20RewardsGauge(Clones.clone(address(gaugeImpl)));
        ERC20RewardsGauge(address(_rewardsGauge)).initialize(address(_asset));
        // Initialize the rewards
        for (uint256 i = 0; i < _MAX_REWARDS; i++) {
            _rewards[i] = new TestERC20Token(
                string.concat("Reward Token ", Strings.toString(i)), string.concat("RT", Strings.toString(i)), 18
            );
            _rewardsGauge.addReward(address(_rewards[i]), address(this));
            _rewards[i].forceApproval(address(this), address(_rewardsGauge), type(uint256).max);
        }
        // Initialize CryticERC4626PropertyTests
        initialize(address(_rewardsGauge), address(_asset), false);
    }

    /// @notice Verify that the reward tokens are deposited and credited correctly
    function verify_depositRewardToken_TransfersCorrectAmount(uint256 rewardIndex, uint256 tokens) public {
        rewardIndex = clampBetween(rewardIndex, 0, 7);
        tokens = clampBetween(tokens, 1, type(uint104).max);
        TestERC20Token reward = _rewards[rewardIndex];
        reward.mint(address(this), tokens);
        uint256 balanceBefore = reward.balanceOf(address(_rewardsGauge));
        try _rewardsGauge.depositRewardToken(address(reward), tokens) {
            assertEq(
                reward.balanceOf(address(_rewardsGauge)),
                balanceBefore + tokens,
                "depositRewardToken() must credit the correct number of reward tokens to the gauge"
            );
        } catch (bytes memory reason) {
            // Ignore the case where the reward amount is too low
            if (abi.decode(reason, (bytes4)) == BaseRewardsGauge.RewardAmountTooLow.selector) {
                revert();
            }
            assertWithMsg(false, "depositRewardToken() must not revert");
        }
    }

    function verify_claimRewards_UsersCanClaimAllRewards() public {
        // Ensure that the gauge has some deposits to claim rewards
        if (_rewardsGauge.totalSupply() == 0) {
            revert();
        }
        hevm.warp(block.timestamp + 2 weeks);
        for (uint256 i = 0; i < 3; ++i) {
            address user = restrictAddressToThirdParties(i);
            _rewardsGauge.claimRewards(user, address(0));
        }
        for (uint256 i = 0; i < _MAX_REWARDS; ++i) {
            uint256 dust = _rewards[i].balanceOf(address(_rewardsGauge));
            emit LogUint256("reward token index", i);
            emit LogUint256("dust remaining in gauge", dust);
            assertLt(dust, 1e10, "All rewards must be claimed with some dust left");
        }
    }

    /// @notice Verify that the reward tokens are claimed correctly to the user
    function verify_claimRewardsProperties(uint256 userIndex) public {
        address user = restrictAddressToThirdParties(userIndex);
        uint256[_MAX_REWARDS] memory balancesBefore;
        uint256[_MAX_REWARDS] memory claimableRewards;
        for (uint256 i = 0; i < _MAX_REWARDS; i++) {
            balancesBefore[i] = _rewards[i].balanceOf(user);
            claimableRewards[i] = _rewardsGauge.claimableReward(user, address(_rewards[i]));
        }
        try _rewardsGauge.claimRewards(user, address(0)) {
            for (uint256 i = 0; i < _MAX_REWARDS; i++) {
                assertEq(
                    _rewards[i].balanceOf(user),
                    balancesBefore[i] + claimableRewards[i],
                    "claimRewards() must credit the correct number of reward tokens to the user"
                );
                _claimed[user][address(_rewards[i])] += claimableRewards[i];
            }
        } catch {
            assertWithMsg(false, "claimRewards() must not revert");
        }
    }

    function verify_claimedRewardProperties(uint256 userIndex) public {
        address user = restrictAddressToThirdParties(userIndex);
        for (uint256 i = 0; i < _MAX_REWARDS; i++) {
            assertEq(
                _rewardsGauge.claimedReward(user, address(_rewards[i])),
                _claimed[user][address(_rewards[i])],
                "claimedReward() must return the correct amount of claimed reward tokens"
            );
        }
    }
}

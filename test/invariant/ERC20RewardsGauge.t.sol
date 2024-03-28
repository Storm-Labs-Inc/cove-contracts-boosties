// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

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
    uint256 internal constant _MAX_REWARDS = 8;
    BaseRewardsGauge internal _rewardsGauge;
    TestERC20Token[_MAX_REWARDS] internal _rewards;
    uint256[_MAX_REWARDS] internal _committedRewards;

    mapping(address => mapping(address => uint256)) internal _claimed;

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
            _committedRewards[rewardIndex] += tokens;
        } catch (bytes memory reason) {
            // Ignore the case where the reward amount is too low
            if (abi.decode(reason, (bytes4)) == BaseRewardsGauge.RewardAmountTooLow.selector) {
                revert();
            }
            assertWithMsg(false, "depositRewardToken() must not revert");
        }
    }

    /// @notice Verify that claimableReward() always returns less than or equal to the remaining amount of reward tokens
    function verify_claimableReward_LteRemaining(uint256 rewardIndex) public {
        rewardIndex = clampBetween(rewardIndex, 0, 7);
        TestERC20Token reward = _rewards[rewardIndex];
        uint256 totalClaimable = 0;
        for (uint256 i = 0; i < 3; ++i) {
            address user = restrictAddressToThirdParties(i);
            totalClaimable += _rewardsGauge.claimableReward(user, address(reward));
        }
        uint256 totalRemaining = _rewards[rewardIndex].balanceOf(address(_rewardsGauge));
        assertGte(
            totalRemaining,
            totalClaimable,
            "Sum of claimableReward() must be less than or equal to the remaining amount of reward tokens"
        );
    }

    /// @notice Verify claimRewards() transfers same amount of tokens as claimableReward()
    function verify_claimRewards_EqClaimableRewards(uint256 userIndex) public {
        address user = restrictAddressToThirdParties(userIndex);
        uint256[_MAX_REWARDS] memory balancesBefore;
        uint256[_MAX_REWARDS] memory claimableRewards;
        for (uint256 i = 0; i < _MAX_REWARDS; i++) {
            balancesBefore[i] = _rewards[i].balanceOf(user);
            claimableRewards[i] = _rewardsGauge.claimableReward(user, address(_rewards[i]));
        }
        try _rewardsGauge.claimRewards(user, address(0)) {
            for (uint256 i = 0; i < _MAX_REWARDS; i++) {
                uint256 received = _rewards[i].balanceOf(user) - balancesBefore[i];
                assertEq(received, claimableRewards[i], "claimRewards() must claim amounts equal to claimableReward()");
                _claimed[user][address(_rewards[i])] += received;
            }
        } catch {
            assertWithMsg(false, "claimRewards() must not revert");
        }
    }

    /// @notice Verify that claimedReward() returns the correct amount of claimed reward tokens
    function verify_claimedReward(uint256 userIndex) public {
        address user = restrictAddressToThirdParties(userIndex);
        for (uint256 i = 0; i < _MAX_REWARDS; i++) {
            assertEq(
                _rewardsGauge.claimedReward(user, address(_rewards[i])),
                _claimed[user][address(_rewards[i])],
                "claimedReward() must return the correct amount of claimed reward tokens"
            );
        }
    }

    /// @notice Verify that pausing works correctly
    function verify_pause() public {
        require(!_rewardsGauge.paused(), "require the gauge to be unpaused for this test to run");
        try _rewardsGauge.pause() {
            assertWithMsg(_rewardsGauge.paused(), "pause() must pause the gauge");
        } catch {
            assertWithMsg(false, "pause() must not revert");
        }
    }

    /// @notice Verify that unpausing works correctly
    function verify_unpause() public {
        require(_rewardsGauge.paused(), "require the gauge to be paused for this test to run");
        try _rewardsGauge.unpause() {
            assertWithMsg(!_rewardsGauge.paused(), "unpause() must unpause the gauge");
        } catch {
            assertWithMsg(false, "unpause() must not revert");
        }
    }

    /// @notice Verify that maxDeposit() returns 0 when the gauge is paused
    function verify_maxDeposit_whenPaused(address depositor) public {
        require(_rewardsGauge.paused(), "require the gauge to be paused for this test to run");
        assertEq(_rewardsGauge.maxDeposit(depositor), 0, "maxDeposit() must return 0 when the gauge is paused");
    }

    /// @notice Verify that maxDeposit() returns max uint256 when the gauge is unpaused
    function verify_maxDeposit_whenUnpaused(address depositor) public virtual {
        require(!_rewardsGauge.paused(), "require the gauge to be unpaused for this test to run");
        assertEq(
            _rewardsGauge.maxDeposit(depositor),
            type(uint256).max,
            "maxDeposit() must return max uint256 when the gauge is unpaused"
        );
    }

    /// @notice Verify that maxMint() returns 0 when the gauge is paused
    function verify_maxMint_whenPaused(address depositor) public {
        require(_rewardsGauge.paused(), "require the gauge to be paused for this test to run");
        assertEq(_rewardsGauge.maxMint(depositor), 0, "maxMint() must return 0 when the gauge is paused");
    }

    /// @notice Verify that maxMint() returns max uint256 when the gauge is unpaused
    function verify_maxMint_whenUnpaused(address depositor) public virtual {
        require(!_rewardsGauge.paused(), "require the gauge to be unpaused for this test to run");
        assertEq(
            _rewardsGauge.maxMint(depositor),
            type(uint256).max,
            "maxMint() must return max uint256 when the gauge is unpaused"
        );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { CryticERC4626PropertyTests } from "@crytic/properties/contracts/ERC4626/ERC4626PropertyTests.sol";
// this token _must_ be the vault's underlying asset
import { TestERC20Token } from "@crytic/properties/contracts/ERC4626/util/TestERC20Token.sol";
import { BaseRewardsGauge } from "src/rewards/BaseRewardsGauge.sol";
import { Clones } from "@crytic/properties/lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/// @title BaseRewardsGauge_EchidnaTest
/// @notice Echidna test contract for BaseRewardsGauge
/// @dev This contract is used to test the aditional properties of BaseRewardsGauge
///     along with CryticERC4626PropertyTests.
contract BaseRewardsGauge_EchidnaTest is CryticERC4626PropertyTests {
    BaseRewardsGauge private _rewardsGauge;
    TestERC20Token[8] private _rewards;

    constructor() {
        TestERC20Token _asset = new TestERC20Token("Test Token", "TT", 18);
        BaseRewardsGauge gaugeImpl = new BaseRewardsGauge();
        // Initialize the gauge with the asset token
        _rewardsGauge = BaseRewardsGauge(Clones.clone(address(gaugeImpl)));
        _rewardsGauge.initialize(address(_asset), "");
        // Initialize the rewards
        for (uint256 i = 0; i < 8; i++) {
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
    function verify_depositRewardTokenProperties(uint256 rewardIndex, uint256 tokens) public {
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

    /// @notice Verify that the reward tokens are claimed correctly to the user
    function verify_claimRewardsProperties(uint256 userIndex) public {
        address user = restrictAddressToThirdParties(userIndex);
        uint256[8] memory balancesBefore;
        uint256[8] memory claimableRewards;
        for (uint256 i = 0; i < 8; i++) {
            balancesBefore[i] = _rewards[i].balanceOf(user);
            claimableRewards[i] = _rewardsGauge.claimableReward(user, address(_rewards[i]));
        }
        try _rewardsGauge.claimRewards(user, address(0)) {
            for (uint256 i = 0; i < 8; i++) {
                assertEq(
                    _rewards[i].balanceOf(user),
                    balancesBefore[i] + claimableRewards[i],
                    "claimRewards() must credit the correct number of reward tokens to the user"
                );
            }
        } catch (bytes memory reason) {
            assertWithMsg(false, "claimRewards() must not revert");
        }
    }
}

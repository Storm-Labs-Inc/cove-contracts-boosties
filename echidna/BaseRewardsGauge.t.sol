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
    BaseRewardsGauge public rewardsGauge;
    TestERC20Token[8] public rewards;

    constructor() {
        TestERC20Token _asset = new TestERC20Token("Test Token", "TT", 18);
        BaseRewardsGauge gaugeImpl = new BaseRewardsGauge();
        // Initialize the gauge with the asset token
        rewardsGauge = BaseRewardsGauge(Clones.clone(address(gaugeImpl)));
        rewardsGauge.initialize(address(_asset), "");
        // Initialize the rewards
        for (uint256 i = 0; i < 8; i++) {
            rewards[i] = new TestERC20Token(
                string.concat("Reward Token ", Strings.toString(i)), string.concat("RT", Strings.toString(i)), 18
            );
            rewardsGauge.addReward(address(rewards[i]), address(this));
            rewards[i].forceApproval(address(this), address(rewardsGauge), type(uint256).max);
        }
        // Initialize CryticERC4626PropertyTests
        initialize(address(rewardsGauge), address(_asset), false);
    }

    /// @notice Verify that the reward tokens are deposited and credited correctly
    function verify_depositRewardTokenProperties(uint256 rewardIndex, uint256 tokens) public {
        rewardIndex = clampBetween(rewardIndex, 0, 7);
        tokens = clampBetween(tokens, 1, type(uint104).max);
        TestERC20Token reward = rewards[rewardIndex];
        reward.mint(address(this), tokens);
        uint256 balanceBefore = reward.balanceOf(address(rewardsGauge));
        try rewardsGauge.depositRewardToken(address(reward), tokens) {
            assertEq(
                reward.balanceOf(address(rewardsGauge)),
                balanceBefore + tokens,
                "depositRewardToken() must credit the correct number of reward tokens to the gauge"
            );
        } catch Error(string memory) {
            assertWithMsg(false, "depositRewardToken() must not revert");
        }
    }

    /// @notice Verify that the reward tokens are claimed correctly to the user
    function verify_claimRewardsProperties(uint256 userIndex) public {
        address user = restrictAddressToThirdParties(userIndex);
        uint256[8] memory balancesBefore;
        uint256[8] memory claimableRewards;
        for (uint256 i = 0; i < 8; i++) {
            balancesBefore[i] = rewards[i].balanceOf(user);
            claimableRewards[i] = rewardsGauge.claimableReward(user, address(rewards[i]));
        }
        try rewardsGauge.claimRewards(user, address(0)) {
            for (uint256 i = 0; i < 8; i++) {
                assertEq(
                    rewards[i].balanceOf(user),
                    balancesBefore[i] + claimableRewards[i],
                    "claimRewards() must credit the correct number of reward tokens to the user"
                );
            }
        } catch Error(string memory) {
            assertWithMsg(false, "claimRewards() must not revert");
        }
    }
}

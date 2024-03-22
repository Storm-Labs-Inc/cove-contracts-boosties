// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

// this token _must_ be the vault's underlying asset
import { TestERC20Token } from "@crytic/properties/contracts/ERC4626/util/TestERC20Token.sol";
import { YSDRewardsGauge } from "src/rewards/YSDRewardsGauge.sol";
import { Clones } from "@crytic/properties/lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { MockYearnGaugeStrategy } from "test/mocks/MockYearnGaugeStrategy.sol";
import { ERC20RewardsGauge_EchidnaTest } from "test/invariant/ERC20RewardsGauge_EchidnaTest.sol";

/// @title YSDRewardsGauge_EchidnaTest
/// @notice Echidna test contract for YSDRewardsGauge
/// @dev This contract is used to test the additional properties of ERC20RewardsGauge
///     along with CryticERC4626PropertyTests.
contract YSDRewardsGauge_EchidnaTest is ERC20RewardsGauge_EchidnaTest {
    MockYearnStakingDelegate internal _stakingDelegate;
    MockYearnGaugeStrategy internal _gaugeStrategy;

    constructor() {
        TestERC20Token _asset = new TestERC20Token("Test Token", "TT", 18);
        _stakingDelegate = new MockYearnStakingDelegate();
        _gaugeStrategy = new MockYearnGaugeStrategy();
        YSDRewardsGauge gaugeImpl = new YSDRewardsGauge();
        // Initialize the gauge with the asset token
        _rewardsGauge = YSDRewardsGauge(Clones.clone(address(gaugeImpl)));
        YSDRewardsGauge(address(_rewardsGauge)).initialize(
            address(_asset), address(_stakingDelegate), address(_gaugeStrategy)
        );
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

    /// @notice Verify that maxTotalAssets() always returns associated strategy's maxTotalAssets() minus totalAssets()
    function verify_maxTotalAssetsProperties() public {
        uint256 globalMaxAssets = _gaugeStrategy.maxTotalAssets();
        uint256 totalAssetsInStrategy = _gaugeStrategy.totalAssets();
        uint256 expectedMaxTotalAssets =
            totalAssetsInStrategy >= globalMaxAssets ? 0 : globalMaxAssets - totalAssetsInStrategy;
        uint256 maxTotalAssets = YSDRewardsGauge(address(_rewardsGauge)).maxTotalAssets();
        emit LogUint256("maxTotalAssets", maxTotalAssets);
        emit LogUint256("expectedMaxTotalAssets", expectedMaxTotalAssets);

        assertEq(maxTotalAssets, expectedMaxTotalAssets, "maxTotalAssets() must return the correct value");
    }

    /// @notice Handler for setting the total assets in the strategy. This mimics the result of depositing or
    /// withdrawing from the associated strategy
    function setStrategyTotalAssets(uint256 assets) public {
        _gaugeStrategy.setTotalAssets(assets);
    }

    /// @notice Handler for setting the max total assets in the strategy.
    function setStrategyMaxTotalAssets(uint256 assets) public {
        _gaugeStrategy.setMaxTotalAssets(assets);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

// this token _must_ be the vault's underlying asset
import { TestERC20Token } from "@crytic/properties/contracts/ERC4626/util/TestERC20Token.sol";
import { YSDRewardsGauge } from "src/rewards/YSDRewardsGauge.sol";
import { Clones } from "@crytic/properties/lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { MockYearnGaugeStrategy } from "test/mocks/MockYearnGaugeStrategy.sol";
import { ERC20RewardsGauge_EchidnaTest } from "test/invariant/ERC20RewardsGauge.t.sol";

/// @title YSDRewardsGauge_EchidnaTest
/// @notice Echidna test contract for YSDRewardsGauge
/// @dev This contract is used to test the additional properties of ERC20RewardsGauge
///     along with CryticERC4626PropertyTests.
contract YSDRewardsGauge_EchidnaTest is ERC20RewardsGauge_EchidnaTest {
    TestERC20Token internal _asset;
    MockYearnStakingDelegate internal _stakingDelegate;
    MockYearnGaugeStrategy internal _gaugeStrategy;

    constructor() {
        _asset = new TestERC20Token("Test Token", "TT", 18);
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

    function setMaxDeposit(uint256 maxDeposit) public {
        try _stakingDelegate.setDepositLimit(address(_asset), maxDeposit) { }
        catch {
            assertWithMsg(false, "setDepositLimit() must not revert");
        }
        try _stakingDelegate.depositLimit(address(_asset)) returns (uint256 depositLimit) {
            assertEq(depositLimit, maxDeposit, "depositLimit() must return the set value");
        } catch {
            assertWithMsg(false, "depositLimit() must not revert");
        }
    }

    function verify_maxDeposit_whenUnpaused(address depositor) public override {
        require(!_rewardsGauge.paused(), "require gauge to be not paused for this test");
        assertEq(
            _rewardsGauge.maxDeposit(depositor),
            _stakingDelegate.availableDepositLimit(address(_asset)),
            "maxDeposit() must return the same value as availableDepositLimit()"
        );
    }

    function verify_maxMint_whenUnpaused(address depositor) public override {
        require(!_rewardsGauge.paused(), "require gauge to be not paused for this test");
        assertEq(
            _rewardsGauge.maxMint(depositor),
            _stakingDelegate.availableDepositLimit(address(_asset)),
            "maxMint() must return the same value as availableDepositLimit()"
        );
    }
}

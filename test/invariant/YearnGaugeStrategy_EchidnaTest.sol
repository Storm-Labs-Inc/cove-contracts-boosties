// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { CryticERC4626PropertyTests } from "@crytic/properties/contracts/ERC4626/ERC4626PropertyTests.sol";
// this token _must_ be the vault's underlying asset
import { TestERC20Token } from "@crytic/properties/contracts/ERC4626/util/TestERC20Token.sol";
import { YearnGaugeStrategy } from "src/strategies/YearnGaugeStrategy.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { MockCurveRouter } from "test/mocks/MockCurveRouter.sol";
import { MockStakingDelegateRewards } from "test/mocks/MockStakingDelegateRewards.sol";
import { Constants } from "test/utils/Constants.sol";
import { ERC4626Mock } from "@openzeppelin/contracts/mocks/ERC4626Mock.sol";
import "@crytic/properties/contracts/util/Hevm.sol";

/// @title ERC20RewardsGauge_EchidnaTest
/// @notice Echidna test contract for ERC20RewardsGauge
/// @dev This contract is used to test the additional properties of ERC20RewardsGauge
///     along with CryticERC4626PropertyTests.
contract YearnGaugeStrategy_EchidnaTest is CryticERC4626PropertyTests {
    YearnGaugeStrategy internal _strategy;
    MockYearnStakingDelegate internal _ysd;
    MockStakingDelegateRewards internal _stakingDelegateRewards;
    MockCurveRouter internal _router;

    constructor() {
        hevm.roll(18_748_116); // sets the correct block number
        hevm.warp(1_698_267_539); // sets the expected timestamp for the block number
        Constants constants = new Constants();
        TestERC20Token _yearnVaultAsset = new TestERC20Token("Asset Token", "AT", 18);
        _yearnVaultAsset.mint(address(this), type(uint256).max);
        ERC4626Mock _yearnVault = new ERC4626Mock(address(_yearnVaultAsset));
        _yearnVault.mint(address(this), type(uint256).max);
        ERC4626Mock _yearnGauge = new ERC4626Mock(address(_yearnVault));
        TestERC20Token _reward = new TestERC20Token("Reward Token", "RT", 18);
        _ysd = new MockYearnStakingDelegate();
        _stakingDelegateRewards = new MockStakingDelegateRewards(address(_reward));
        _ysd.setGaugeStakingRewards(address(_stakingDelegateRewards));
        _strategy =
            new YearnGaugeStrategy(address(_yearnGauge), address(_ysd), address(constants.MAINNET_CURVE_ROUTER()));
        // Initialize CryticERC4626PropertyTests
        initialize(address(_strategy), address(_yearnGauge), false);
    }

    /// @notice Handler for setting the max total assets in the strategy.
    function setStrategyMaxTotalAssets(uint256 assets) public {
        _strategy.setMaxTotalAssets(assets);
    }
}

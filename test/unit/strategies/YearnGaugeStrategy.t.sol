// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "tokenized-strategy/interfaces/IStrategy.sol";
import { YearnGaugeStrategy } from "src/strategies/YearnGaugeStrategy.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { IYearnGaugeStrategy } from "src/interfaces/IYearnGaugeStrategy.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { MockStakingDelegateRewards } from "test/mocks/MockStakingDelegateRewards.sol";
import { MockCurveRouter } from "test/mocks/MockCurveRouter.sol";
import { Errors } from "src/libraries/Errors.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { ERC4626Mock } from "@openzeppelin/contracts/mocks/ERC4626Mock.sol";
import { MockGauge } from "test/mocks/MockGauge.sol";
import { TokenizedStrategy } from "tokenized-strategy/TokenizedStrategy.sol";
import { MockDYFIRedeemer } from "test/mocks/MockDYFIRedeemer.sol";

contract YearnGaugeStrategy_Test is BaseTest {
    using SafeERC20 for IERC20;

    IYearnGaugeStrategy public yearnGaugeStrategy;
    IYearnStakingDelegate public yearnStakingDelegate;
    MockDYFIRedeemer public mockDYfiRedeemer;
    address public stakingDelegateRewards;
    address public dYfi;
    address public yfi;
    address public weth;
    address public vaultAsset;
    address public vault;
    address public gauge;
    address public curveRouter;
    // address public flashLoanProvider;
    // address public redemption;

    // Addresses
    address public admin;
    address public yearnAdmin;
    address public alice;
    address public manager;
    address public treasury;
    address public keeper;

    // Events TODO: remove for interface
    event DYfiRedeemerSet(address oldDYfiRedeemer, address newDYfiRedeemer);

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        yearnAdmin = createUser("yearnAdmin");
        alice = createUser("alice");
        manager = createUser("manager");
        treasury = createUser("treasury");
        keeper = createUser("keeper");

        // Deploy mock contracts
        dYfi = MAINNET_DYFI;
        vm.etch(dYfi, address(new ERC20Mock()).code);
        yfi = MAINNET_YFI;
        vm.etch(yfi, address(new ERC20Mock()).code);
        _deployVaultFactoryAt(yearnAdmin, MAINNET_VAULT_FACTORY);
        vm.etch(MAINNET_TOKENIZED_STRATEGY_IMPLEMENTATION, address(new TokenizedStrategy(MAINNET_VAULT_FACTORY)).code);
        vaultAsset = address(new ERC20Mock());
        vm.label(vaultAsset, "vaultAsset");
        vault = address(new ERC4626Mock(vaultAsset));
        vm.label(vault, "vault");
        gauge = address(new MockGauge(vault));
        vm.label(gauge, "gauge");
        mockDYfiRedeemer = new MockDYFIRedeemer();
        vm.label(address(mockDYfiRedeemer), "mockDYfiRedeemer");
        curveRouter = address(new MockCurveRouter());
        vm.label(curveRouter, "curveRouter");
        yearnStakingDelegate = IYearnStakingDelegate(address(new MockYearnStakingDelegate()));
        stakingDelegateRewards = address(new MockStakingDelegateRewards(dYfi));
        MockYearnStakingDelegate(address(yearnStakingDelegate)).setGaugeStakingRewards(stakingDelegateRewards);

        vm.startPrank(manager);
        yearnGaugeStrategy =
            IYearnGaugeStrategy(address(new YearnGaugeStrategy(gauge, address(yearnStakingDelegate), curveRouter)));
        yearnGaugeStrategy.setPerformanceFeeRecipient(treasury);
        yearnGaugeStrategy.setKeeper(keeper);
        yearnGaugeStrategy.setHarvestSwapParams(generateMockCurveSwapParams(MAINNET_YFI, vaultAsset));
        vm.stopPrank();
        vm.mockCall(
            address(yearnStakingDelegate),
            abi.encodeWithSelector(IYearnStakingDelegate.availableDepositLimit.selector, gauge),
            abi.encode(type(uint256).max)
        );
    }

    function _depositFromUser(address from, uint256 amount) internal {
        airdrop(IERC20(vaultAsset), from, amount);
        vm.startPrank(from);
        IERC20(vaultAsset).approve(address(vault), amount);
        IERC4626(vault).deposit(amount, from);
        IERC20(vault).approve(address(gauge), amount);
        IERC4626(gauge).deposit(amount, from);
        IERC20(gauge).approve(address(yearnGaugeStrategy), amount);
        yearnGaugeStrategy.deposit(amount, from);
        vm.stopPrank();
    }

    function _massRedeemStrategyDYfi() internal {
        address[] memory holders = new address[](1);
        holders[0] = address(yearnGaugeStrategy);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = IERC20(dYfi).balanceOf(address(yearnGaugeStrategy));
        mockDYfiRedeemer.massRedeem(holders, amounts);
    }

    function test_constructor() public {
        address underlyingVault = IERC4626(gauge).asset();
        assertEq(yearnGaugeStrategy.vault(), underlyingVault, "gauge address not set correctly");
        assertEq(
            yearnGaugeStrategy.vaultAsset(), IERC4626(underlyingVault).asset(), "vault asset address not set correctly"
        );
        assertEq(
            yearnGaugeStrategy.yearnStakingDelegate(),
            address(yearnStakingDelegate),
            "yearnStakingDelegate not set correctly"
        );
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // deposit into strategy happens
        _depositFromUser(alice, amount);
        // check for expected changes
        assertEq(yearnGaugeStrategy.balanceOf(alice), amount, "Deposit was not successful");
        assertEq(
            IYearnStakingDelegate(yearnStakingDelegate).balanceOf(address(yearnGaugeStrategy), gauge),
            amount,
            "yearn staking delegate deposit failed"
        );
        assertEq(yearnGaugeStrategy.totalSupply(), amount, "totalSupply did not update correctly");
    }

    function testFuzz_deposit_revertWhen_MaxTotalAssetsExceeded(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        vm.prank(manager);
        vm.mockCall(
            address(yearnStakingDelegate),
            abi.encodeWithSelector(IYearnStakingDelegate.availableDepositLimit.selector, gauge),
            abi.encode(amount / 10)
        );
        airdrop(IERC20(gauge), alice, amount);
        vm.startPrank(alice);
        IERC20(gauge).approve(address(yearnGaugeStrategy), amount);
        vm.expectRevert("ERC4626: deposit more than max");
        yearnGaugeStrategy.deposit(amount, alice);
        vm.stopPrank();
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        _depositFromUser(alice, amount); // deposit into strategy happens
        uint256 beforeDeployedAssets = yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge);
        assertEq(beforeDeployedAssets, amount, "all of deposit should be deployed");

        vm.prank(alice);
        yearnGaugeStrategy.withdraw(amount, alice, alice);
        assertEq(
            IYearnStakingDelegate(yearnStakingDelegate).balanceOf(address(yearnGaugeStrategy), gauge),
            0,
            "yearn staking delegate withdraw failed"
        );
        assertEq(yearnGaugeStrategy.balanceOf(alice), 0, "Withdraw was not successful");
        assertEq(yearnGaugeStrategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
    }

    function testFuzz_report_passWhen_stakingRewardsProfit(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);
        uint256 profitedVaultAssetAmount = 1e18;

        vm.prank(manager);
        yearnGaugeStrategy.setDYfiRedeemer(address(mockDYfiRedeemer));
        _depositFromUser(alice, amount);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        uint256 beforeDeployedAssets = yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge);
        assertEq(beforeDeployedAssets, amount, "all of deposit should be deployed");
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Send rewards to stakingDelegateRewards which will be claimed on report()
        airdrop(IERC20(dYfi), stakingDelegateRewards, 1e18);
        // The strategy will swap dYFI to vaultAsset using the CurveRouter
        // Then the strategy will deposit vaultAsset into the vault, and into the gauge
        airdrop(IERC20(vaultAsset), curveRouter, profitedVaultAssetAmount);

        // Claim rewards for the strategy
        MockStakingDelegateRewards(stakingDelegateRewards).getReward(address(yearnGaugeStrategy), gauge);
        assertEq(
            IERC20(dYfi).balanceOf(address(yearnGaugeStrategy)),
            profitedVaultAssetAmount,
            "dYfi rewards should be received"
        );

        // Call massRedeem() to swap received DYfi for Yfi
        _massRedeemStrategyDYfi();

        // call report on strategy again to deposit newly opbtained Yfi into strategy to record profit
        vm.prank(manager);
        (uint256 profit,) = yearnGaugeStrategy.report();

        assertEq(profit, profitedVaultAssetAmount, "profit should match newly minted gauge tokens");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + yearnGaugeStrategy.profitMaxUnlockTime());

        // manager calls report
        vm.prank(manager);
        yearnGaugeStrategy.report();

        uint256 afterTotalAssets = yearnGaugeStrategy.totalAssets();
        assertEq(afterTotalAssets, beforeTotalAssets + profit, "report did not increase total assets");
        assertEq(
            afterTotalAssets,
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            "all assets should be deployed"
        );
        assertEq(yearnGaugeStrategy.balanceOf(treasury), profit / 10, "treasury should have 10% of profit");
    }

    function testFuzz_report_passWhen_stakingRewardsProfitMultipleUsers(uint256 amount0, uint256 amount1) public {
        // first deposit will always be a large amount
        uint256 initialDeposit = 10e18;
        vm.assume(amount0 < type(uint128).max && amount1 < type(uint128).max);
        uint256 profitedVaultAssetAmount = 1e8;
        address bob = createUser("bob");
        address charlie = createUser("charlie");

        vm.prank(manager);
        yearnGaugeStrategy.setDYfiRedeemer(address(mockDYfiRedeemer));

        _depositFromUser(alice, initialDeposit);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        uint256 beforeDeployedAssets = yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge);
        assertEq(beforeDeployedAssets, initialDeposit, "all of alice's deposit should be deployed");
        assertEq(beforeTotalAssets, initialDeposit, "total assets should be equal to deposit initialDeposit");
        assertEq(beforePreviewRedeem, initialDeposit, "preview redeem should return deposit initialDeposit");

        // Send rewards to stakingDelegateRewards which will be claimed on report()
        airdrop(IERC20(dYfi), stakingDelegateRewards, 1e18);
        // The strategy will swap dYFI to vaultAsset using the CurveRouter
        // Then the strategy will deposit vaultAsset into the vault, and into the gauge
        airdrop(IERC20(vaultAsset), curveRouter, profitedVaultAssetAmount);

        // Claim rewards for the strategy
        MockStakingDelegateRewards(stakingDelegateRewards).getReward(address(yearnGaugeStrategy), gauge);
        assertEq(IERC20(dYfi).balanceOf(address(yearnGaugeStrategy)), 1e18, "dYfi rewards should be received");
        // Call massRedeem() to swap received DYfi for Yfi
        _massRedeemStrategyDYfi();

        // manager calls report on the wrapped strategy
        vm.prank(manager);
        (uint256 profit,) = yearnGaugeStrategy.report();
        assertEq(profit, profitedVaultAssetAmount, "profit should match newly minted gauge tokens");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + yearnGaugeStrategy.profitMaxUnlockTime());

        // calculate the minimum amount that can be deposited to result in at least 1 share
        vm.assume(amount0 * yearnGaugeStrategy.totalSupply() > yearnGaugeStrategy.totalAssets());

        // Test multiple users interaction
        _depositFromUser(bob, amount0);
        uint256 afterBobDeployedAssets = yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge);
        assertEq(
            afterBobDeployedAssets, beforeDeployedAssets + amount0 + profit, "all of bob's deposit should be deployed"
        );

        // manager calls report
        vm.prank(manager);
        yearnGaugeStrategy.report();
        // Test multiple users interaction, deposit is require to result in at least one shar
        vm.assume(amount1 * yearnGaugeStrategy.totalSupply() > yearnGaugeStrategy.totalAssets());
        _depositFromUser(charlie, amount1);
        uint256 afterCharlieDeployedAssets = yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge);
        assertEq(
            afterCharlieDeployedAssets, afterBobDeployedAssets + amount1, "all of Charlie's deposit should be deployed"
        );

        uint256 afterTotalAssets = yearnGaugeStrategy.totalAssets();
        // Profit should only be compared to assets deposited before profit was reported+unlocked
        assertEq(
            afterTotalAssets - amount0 - amount1, beforeTotalAssets + profit, "report did not increase total assets"
        );
        // All assets should be deployed if there has been a report() since the deposit
        assertEq(
            afterTotalAssets,
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            "all assets should be deployed"
        );
        assertEq(yearnGaugeStrategy.balanceOf(treasury), profit / 10, "treasury should have 10% of profit");
    }

    function testFuzz_report_passWhen_noProfits(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // deposit into strategy happens
        _depositFromUser(alice, amount);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        uint256 beforeDeployedAssets = yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge);
        assertEq(beforeDeployedAssets, amount, "all of deposit should be deployed");
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // manager calls report on the wrapped strategy
        vm.prank(manager);
        yearnGaugeStrategy.report();

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(yearnGaugeStrategy)).profitMaxUnlockTime());

        // manager calls report
        vm.prank(manager);
        (uint256 profit, uint256 loss) = yearnGaugeStrategy.report();
        assertEq(profit, 0, "profit should be 0");
        assertEq(loss, 0, "loss should be 0");
        assertEq(yearnGaugeStrategy.balanceOf(treasury), 0, "treasury should have 0 profit");
    }

    function testFuzz_withdraw_passWhen_DuringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // deposit into strategy happens
        _depositFromUser(alice, amount);

        // shutdown strategy
        vm.prank(manager);
        yearnGaugeStrategy.shutdownStrategy();

        vm.prank(alice);
        yearnGaugeStrategy.withdraw(amount, alice, alice);
        assertEq(yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge), 0, "_withdrawFromYSD failed");
        assertEq(yearnGaugeStrategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
        assertEq(yearnGaugeStrategy.balanceOf(alice), 0, "Withdraw was not successful");
    }

    function testFuzz_deposit_passWhen_DuringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // shutdown strategy
        vm.prank(manager);
        yearnGaugeStrategy.shutdownStrategy();
        // deposit into strategy happens
        airdrop(ERC20(gauge), alice, amount);
        vm.startPrank(alice);
        IERC20(yearnGaugeStrategy.asset()).approve(address(yearnGaugeStrategy), amount);
        // TokenizedStrategy.maxDeposit() returns 0 on shutdown
        vm.expectRevert("ERC4626: deposit more than max");
        yearnGaugeStrategy.deposit(amount, alice);
        vm.stopPrank();
    }

    function testFuzz_report_passWhen_DuringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);
        vm.prank(manager);
        yearnGaugeStrategy.setDYfiRedeemer(address(mockDYfiRedeemer));
        // Assume the exchange rate from vaultAsset to vault to gauge tokens is 1:1:1
        uint256 profitedVaultAssetAmount = 1e18;

        // deposit into strategy happens
        _depositFromUser(alice, amount);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        uint256 beforeDeployedAssets = yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");
        assertEq(beforeDeployedAssets, amount, "all of deposit should be deployed");

        // Send rewards to stakingDelegateRewards which will be claimed on report()
        airdrop(IERC20(dYfi), stakingDelegateRewards, 1e18);
        // The strategy will swap dYFI to vaultAsset using the CurveRouter
        // Then the strategy will deposit vaultAsset into the vault, and into the gauge
        airdrop(IERC20(vaultAsset), curveRouter, profitedVaultAssetAmount);

        // shutdown strategy
        vm.prank(manager);
        yearnGaugeStrategy.shutdownStrategy();

        // Claim rewards for the strategy
        MockStakingDelegateRewards(stakingDelegateRewards).getReward(address(yearnGaugeStrategy), gauge);
        assertEq(
            IERC20(dYfi).balanceOf(address(yearnGaugeStrategy)),
            profitedVaultAssetAmount,
            "dYfi rewards should be received"
        );
        // Call massRedeem() to swap received DYfi for Yfi
        _massRedeemStrategyDYfi();

        // call report on strategy again to deposit newly opbtained Yfi into strategy to record profit
        vm.prank(manager);
        (uint256 profit,) = yearnGaugeStrategy.report();

        assertEq(profit, profitedVaultAssetAmount, "profit should match newly minted gauge tokens");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(yearnGaugeStrategy)).profitMaxUnlockTime());

        // manager calls report
        vm.prank(manager);
        yearnGaugeStrategy.report();

        uint256 afterTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 afterDeployedAssets = yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge);
        assertEq(afterTotalAssets, beforeTotalAssets + profitedVaultAssetAmount, "report did not increase total assets");
        assertEq(yearnGaugeStrategy.balanceOf(treasury), profit / 10, "treasury should have 10% of profit");
        assertEq(beforeDeployedAssets, afterDeployedAssets, "deployed assets should not change");
    }

    function testFuzz_setHarvestSwapParams_revertWhen_CallerIsNotManagement(address caller) public {
        vm.assume(caller != manager);
        vm.assume(caller != address(0));
        vm.expectRevert("!management");
        vm.prank(caller);
        yearnGaugeStrategy.setHarvestSwapParams(generateMockCurveSwapParams(dYfi, vaultAsset));
    }

    function test_setdYfiRedeemer_revertWhen_ZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        vm.prank(manager);
        yearnGaugeStrategy.setDYfiRedeemer(address(0));
    }

    function test_emergencyWithdraw_revertWhen_nonManager(address caller) public {
        vm.assume(caller != manager);
        vm.assume(caller != admin);
        vm.assume(caller != address(0));
        vm.prank(caller);
        vm.expectRevert("!emergency authorized");
        yearnGaugeStrategy.emergencyWithdraw(1e18);
    }

    function testFuzz_setDYfiRedeemer(address a) public {
        vm.assume(a != address(0));

        vm.expectEmit();
        emit DYfiRedeemerSet(address(0), a);
        vm.prank(manager);
        yearnGaugeStrategy.setDYfiRedeemer(a);
        assertEq(yearnGaugeStrategy.dYfiRedeemer(), a);
        assertEq(IERC20(dYfi).allowance(address(yearnGaugeStrategy), a), type(uint256).max);
    }

    function testFuzz_setDYfiRedeemer_passWhen_Replacing(address a, address b) public {
        vm.assume(a != address(0));
        vm.assume(b != address(0));
        vm.assume(a != b);

        vm.expectEmit();
        emit DYfiRedeemerSet(address(0), a);
        vm.prank(manager);
        yearnGaugeStrategy.setDYfiRedeemer(a);
        assertEq(yearnGaugeStrategy.dYfiRedeemer(), a);
        assertEq(IERC20(dYfi).allowance(address(yearnGaugeStrategy), a), type(uint256).max);
        assertEq(IERC20(dYfi).allowance(address(yearnGaugeStrategy), b), 0);

        vm.expectEmit();
        emit DYfiRedeemerSet(a, b);
        vm.prank(manager);
        yearnGaugeStrategy.setDYfiRedeemer(b);
        assertEq(yearnGaugeStrategy.dYfiRedeemer(), b);
        assertEq(IERC20(dYfi).allowance(address(yearnGaugeStrategy), a), 0);
        assertEq(IERC20(dYfi).allowance(address(yearnGaugeStrategy), b), type(uint256).max);
    }

    function test_setDYfiRedeemer_revertWhen_ZeroAddress() public {
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        yearnGaugeStrategy.setDYfiRedeemer(address(0));
    }

    function testFuzz_setDYfiRedeemer_revertWhen_SameAddress(address a) public {
        vm.assume(a != address(0));
        vm.startPrank(manager);
        yearnGaugeStrategy.setDYfiRedeemer(a);
        vm.expectRevert(abi.encodeWithSelector(Errors.SameAddress.selector));
        yearnGaugeStrategy.setDYfiRedeemer(a);
        vm.stopPrank();
    }

    function testFuzz_emergencyWithdraw(uint256 amount) public {
        // _setFlashLoanProvider(flashLoanProvider);
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // deposit into strategy happens
        _depositFromUser(alice, amount);
        // manager calls report
        vm.prank(manager);
        yearnGaugeStrategy.report();
        uint256 beforeDeployedAssets = yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge);
        assertEq(beforeDeployedAssets, amount, "all of deposit should be deployed");

        // shutdown strategy
        vm.prank(manager);
        yearnGaugeStrategy.shutdownStrategy();

        // emergency withdraw, if given max amount will always attempt to withdraw its total balance
        vm.prank(manager);
        yearnGaugeStrategy.emergencyWithdraw(type(uint256).max);
        uint256 afterDeployedAssets = yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge);
        assertEq(afterDeployedAssets, 0, "emergency withdraw failed");

        // user withdraws
        vm.prank(alice);
        yearnGaugeStrategy.withdraw(amount, alice, alice);
        assertEq(yearnGaugeStrategy.balanceOf(alice), 0, "Withdraw was not successful");
        assertEq(yearnGaugeStrategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
    }
}

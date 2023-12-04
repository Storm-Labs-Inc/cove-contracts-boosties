// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "@tokenized-strategy/interfaces/IStrategy.sol";
import { WrappedYearnV3Strategy } from "src/strategies/WrappedYearnV3Strategy.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MockYearnStakingDelegate } from "./mocks/MockYearnStakingDelegate.sol";
import { MockStakingDelegateRewards } from "./mocks/MockStakingDelegateRewards.sol";
import { MockCurveRouter } from "test/mocks/MockCurveRouter.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { ERC4626Mock } from "@openzeppelin/contracts/mocks/ERC4626Mock.sol";
import { MockGauge } from "test/mocks/MockGauge.sol";

import { TokenizedStrategy } from "tokenized-strategy/TokenizedStrategy.sol";

contract WrappedStrategy_Test is BaseTest {
    using SafeERC20 for IERC20;

    IWrappedYearnV3Strategy public wrappedYearnV3Strategy;
    IYearnStakingDelegate public yearnStakingDelegate;
    address public stakingDelegateRewards;
    address public dYfi;
    address public vaultAsset;
    address public vault;
    address public gauge;
    address public curveRouter;

    // Addresses
    address public admin;
    address public yearnAdmin;
    address public alice;
    address public manager;
    address public treasury;
    address public keeper;

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
        vm.etch(MAINNET_TOKENIZED_STRATEGY_IMPLEMENTATION, address(new TokenizedStrategy()).code);
        _deployVaultFactoryAt(yearnAdmin, MAINNET_VAULT_FACTORY);
        vaultAsset = address(new ERC20Mock());
        vm.label(vaultAsset, "vaultAsset");
        vault = address(new ERC4626Mock(vaultAsset));
        vm.label(vault, "vault");
        gauge = address(new MockGauge(vault));
        vm.label(gauge, "gauge");
        curveRouter = address(new MockCurveRouter());
        yearnStakingDelegate = IYearnStakingDelegate(address(new MockYearnStakingDelegate()));
        stakingDelegateRewards = address(new MockStakingDelegateRewards(dYfi, address(yearnStakingDelegate)));
        MockYearnStakingDelegate(address(yearnStakingDelegate)).setGaugeStakingRewards(stakingDelegateRewards);

        vm.startPrank(manager);
        wrappedYearnV3Strategy = IWrappedYearnV3Strategy(
            address(new WrappedYearnV3Strategy(gauge, address(yearnStakingDelegate), dYfi, curveRouter))
        );
        wrappedYearnV3Strategy.setPerformanceFeeRecipient(treasury);
        wrappedYearnV3Strategy.setKeeper(keeper);
        wrappedYearnV3Strategy.setHarvestSwapParams(generateMockCurveSwapParams(dYfi, vaultAsset));
        wrappedYearnV3Strategy.setMaxTotalAssets(type(uint256).max);
        vm.stopPrank();
    }

    function _depositFromUser(address from, uint256 amount) internal {
        airdrop(IERC20(gauge), from, amount);
        vm.startPrank(from);
        IERC20(gauge).approve(address(wrappedYearnV3Strategy), amount);
        wrappedYearnV3Strategy.deposit(amount, from);
        vm.stopPrank();
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // deposit into strategy happens
        _depositFromUser(alice, amount);
        // check for expected changes
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), amount, "Deposit was not successful");
        assertEq(
            IYearnStakingDelegate(yearnStakingDelegate).balanceOf(address(wrappedYearnV3Strategy), gauge),
            amount,
            "yearn staking delegate deposit failed"
        );
        assertEq(wrappedYearnV3Strategy.totalSupply(), amount, "totalSupply did not update correctly");
    }

    function testFuzz_deposit_revertWhen_MaxTotalAssetsExceeded(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        vm.prank(manager);
        wrappedYearnV3Strategy.setMaxTotalAssets(amount / 10);
        airdrop(IERC20(gauge), alice, amount);
        vm.startPrank(alice);
        IERC20(gauge).approve(address(wrappedYearnV3Strategy), amount);
        vm.expectRevert("ERC4626: deposit more than max");
        wrappedYearnV3Strategy.deposit(amount, alice);
        vm.stopPrank();
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        _depositFromUser(alice, amount); // deposit into strategy happens

        vm.prank(alice);
        wrappedYearnV3Strategy.withdraw(amount, alice, alice);
        assertEq(
            IYearnStakingDelegate(yearnStakingDelegate).balanceOf(address(wrappedYearnV3Strategy), gauge),
            0,
            "yearn staking delegate withdraw failed"
        );
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), 0, "Withdraw was not successful");
        assertEq(wrappedYearnV3Strategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
    }

    function testFuzz_report_staking_rewards_profit(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);
        uint256 profitedVaultAssetAmount = 1e18;

        _depositFromUser(alice, amount);
        uint256 shares = wrappedYearnV3Strategy.balanceOf(alice);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Send rewards to stakingDelegateRewards which will be claimed on report()
        airdrop(IERC20(dYfi), stakingDelegateRewards, 1e18);
        // The strategy will swap dYFI to vaultAsset using the CurveRouter
        // Then the strategy will deposit vaultAsset into the vault, and into the gauge
        airdrop(IERC20(vaultAsset), curveRouter, profitedVaultAssetAmount);

        // manager calls report on the wrapped strategy
        vm.prank(manager);
        (uint256 profit,) = wrappedYearnV3Strategy.report();
        assertEq(profit, profitedVaultAssetAmount, "profit should match newly minted gauge tokens");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + wrappedYearnV3Strategy.profitMaxUnlockTime());

        // manager calls report
        vm.prank(manager);
        wrappedYearnV3Strategy.report();

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        assertEq(afterTotalAssets, beforeTotalAssets + profit, "report did not increase total assets");
        assertEq(
            afterTotalAssets,
            yearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge),
            "all assets should be deployed"
        );
        assertEq(wrappedYearnV3Strategy.balanceOf(treasury), profit / 10, "treasury should have 10% of profit");
    }

    function testFuzz_report_staking_rewards_profit_multiple_users(
        uint256 amount,
        uint256 amount1,
        uint256 amount2
    )
        public
    {
        vm.assume(amount != 0 && amount1 >= 1e6 && amount2 >= 1e6);
        // 1e6 for futher deposits to avoid "ZERO_SHARES" error due to rounding
        vm.assume(amount < type(uint128).max && amount1 < type(uint128).max && amount2 < type(uint128).max);
        uint256 profitedVaultAssetAmount = 1e18;
        address bob = createUser("bob");
        address charlie = createUser("charlie");

        _depositFromUser(alice, amount);
        uint256 shares = wrappedYearnV3Strategy.balanceOf(alice);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Send rewards to stakingDelegateRewards which will be claimed on report()
        airdrop(IERC20(dYfi), stakingDelegateRewards, 1e18);
        // The strategy will swap dYFI to vaultAsset using the CurveRouter
        // Then the strategy will deposit vaultAsset into the vault, and into the gauge
        airdrop(IERC20(vaultAsset), curveRouter, profitedVaultAssetAmount);

        // manager calls report on the wrapped strategy
        vm.prank(manager);
        (uint256 profit,) = wrappedYearnV3Strategy.report();
        assertEq(profit, profitedVaultAssetAmount, "profit should match newly minted gauge tokens");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + wrappedYearnV3Strategy.profitMaxUnlockTime());
        // Test multiple users interaction
        _depositFromUser(bob, amount1);

        // manager calls report
        vm.prank(manager);
        wrappedYearnV3Strategy.report();
        // Test multiple users interaction
        _depositFromUser(charlie, amount2);

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        // Profit should only be compared to assets deposited before profit was reported+unlocked
        assertEq(
            afterTotalAssets - amount1 - amount2, beforeTotalAssets + profit, "report did not increase total assets"
        );
        // All assets should be deployed if there has been a report() since the deposit
        assertEq(
            afterTotalAssets,
            yearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge),
            "all assets should be deployed"
        );
        assertEq(wrappedYearnV3Strategy.balanceOf(treasury), profit / 10, "treasury should have 10% of profit");
    }

    function testFuzz_report_passWhen_noProfits(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // deposit into strategy happens
        _depositFromUser(alice, amount);
        uint256 shares = wrappedYearnV3Strategy.balanceOf(alice);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // manager calls report on the wrapped strategy
        vm.prank(manager);
        wrappedYearnV3Strategy.report();

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(wrappedYearnV3Strategy)).profitMaxUnlockTime());

        // manager calls report
        vm.prank(manager);
        (uint256 profit, uint256 loss) = wrappedYearnV3Strategy.report();
        assertEq(profit, 0, "profit should be 0");
        assertEq(loss, 0, "loss should be 0");
        assertEq(wrappedYearnV3Strategy.balanceOf(treasury), 0, "treasury should have 0 profit");
    }

    function testFuzz_withdraw_duringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // deposit into strategy happens
        _depositFromUser(alice, amount);

        // shutdown strategy
        vm.prank(manager);
        wrappedYearnV3Strategy.shutdownStrategy();

        vm.prank(alice);
        wrappedYearnV3Strategy.withdraw(amount, alice, alice);
        assertEq(yearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge), 0, "_withdrawFromYSD failed");
        assertEq(wrappedYearnV3Strategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), 0, "Withdraw was not successful");
    }

    function testFuzz_deposit_duringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // shutdown strategy
        vm.prank(manager);
        wrappedYearnV3Strategy.shutdownStrategy();
        // deposit into strategy happens
        airdrop(ERC20(gauge), alice, amount);
        vm.startPrank(alice);
        IERC20(wrappedYearnV3Strategy.asset()).approve(address(wrappedYearnV3Strategy), amount);
        // TokenizedStrategy.maxDeposit() returns 0 on shutdown
        vm.expectRevert("ERC4626: deposit more than max");
        wrappedYearnV3Strategy.deposit(amount, alice);
        vm.stopPrank();
    }

    function testFuzz_withdraw_duringShutdownReport(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);
        uint256 profitedVaultAssetAmount = 1e18;

        // deposit into strategy happens
        _depositFromUser(alice, amount);
        uint256 shares = wrappedYearnV3Strategy.balanceOf(alice);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(shares);
        uint256 beforeDeployedAssets = yearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge);
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
        wrappedYearnV3Strategy.shutdownStrategy();

        // manager calls report on the wrapped strategy
        vm.prank(manager);
        (uint256 profit,) = wrappedYearnV3Strategy.report();
        assertGt(profit, 0, "profit should be greater than 0");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(wrappedYearnV3Strategy)).profitMaxUnlockTime());

        // manager calls report
        vm.prank(manager);
        wrappedYearnV3Strategy.report();

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 afterDeployedAssets = yearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge);
        assertEq(afterTotalAssets, beforeTotalAssets + profitedVaultAssetAmount, "report did not increase total assets");
        assertEq(wrappedYearnV3Strategy.balanceOf(treasury), profit / 10, "treasury should have 10% of profit");
        assertEq(beforeDeployedAssets, afterDeployedAssets, "deployed assets should not change");
    }

    function testFuzz_setHarvestSwapParams_revertWhen_CallerIsNotManagement(address caller) public {
        vm.expectRevert("!management");
        vm.prank(caller);
        wrappedYearnV3Strategy.setHarvestSwapParams(generateMockCurveSwapParams(dYfi, vaultAsset));
    }

    function test_emergencyWithdraw_nonManager() public {
        vm.prank(alice);
        vm.expectRevert("!emergency authorized");
        wrappedYearnV3Strategy.emergencyWithdraw(1e18);
    }

    function testFuzz_emergencyWithdraw(uint256 amount) public {
        vm.assume(amount > 1e6); // Minimum deposit size is required to farm dYFI emission
        vm.assume(amount < 1_000_000_000 * 1e6); // limit deposit size to 1 Billion USDC
        // deposit into strategy happens
        _depositFromUser(alice, amount);
        // manager calls report
        vm.prank(manager);
        wrappedYearnV3Strategy.report();
        uint256 beforeDeployedAssets = yearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge);
        assertEq(beforeDeployedAssets, amount, "all of deposit should be deployed");

        // shutdown strategy
        vm.prank(manager);
        wrappedYearnV3Strategy.shutdownStrategy();

        // emergency withdraw, if given max amount will always attempt to withdraw its total balance
        vm.prank(manager);
        wrappedYearnV3Strategy.emergencyWithdraw(type(uint256).max);
        uint256 afterDeployedAssets = yearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge);
        assertEq(afterDeployedAssets, 0, "emergency withdraw failed");

        // user withdraws
        vm.prank(alice);
        wrappedYearnV3Strategy.withdraw(amount, alice, alice);
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), 0, "Withdraw was not successful");
        assertEq(wrappedYearnV3Strategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
    }
}

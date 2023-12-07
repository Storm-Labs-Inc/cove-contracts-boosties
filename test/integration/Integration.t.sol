// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "test/utils/YearnV3BaseTest.t.sol";
import { IStrategy } from "@tokenized-strategy/interfaces/IStrategy.sol";
import { IVault } from "yearn-vaults-v3/interfaces/IVault.sol";
import { IYearnGaugeStrategy } from "src/interfaces/IYearnGaugeStrategy.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import { Errors } from "src/libraries/Errors.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { StakingDelegateRewards } from "src/StakingDelegateRewards.sol";
import { SwapAndLock } from "src/SwapAndLock.sol";
import { console2 as console } from "forge-std/Console2.sol";

contract YearnGaugeStrategy_IntegrationTest is YearnV3BaseTest {
    using SafeERC20 for IERC20;

    IYearnGaugeStrategy public yearnGaugeStrategy;
    YearnStakingDelegate public yearnStakingDelegate;
    StakingDelegateRewards public stakingDelegateRewards;
    SwapAndLock public swapAndLock;
    IVault public vault;

    // Addresses
    address public alice;
    address public gauge;
    address public treasury;
    address public rewardDistributor;
    address public gaugeRewardReceiver;

    function setUp() public override {
        super.setUp();
        //// generic ////
        alice = createUser("alice");
        treasury = createUser("treasury");
        vault = IVault(MAINNET_WETH_YETH_POOL_VAULT);
        vm.label(address(vault), "wethyethPoolVault");
        gauge = MAINNET_WETH_YETH_POOL_GAUGE;
        vm.label(gauge, "wethyethPoolGauge");
        rewardDistributor = createUser("rewardDistributor");

        // Deploy Contracts

        //// gauge rewards  ////
        {
            gaugeRewardReceiver = setUpGaugeRewardReceiverImplementation(admin);
            yearnStakingDelegate =
                YearnStakingDelegate(new YearnStakingDelegate(gaugeRewardReceiver, treasury, admin, admin));
            vm.label(address(yearnStakingDelegate), "yearnStakingDelegate");
            vm.label(yearnStakingDelegate.gaugeRewardReceivers(gauge), "gaugeRewardReceiver");
            stakingDelegateRewards =
                StakingDelegateRewards(setUpStakingDelegateRewards(admin, MAINNET_DYFI, address(yearnStakingDelegate)));
            swapAndLock = SwapAndLock(setUpSwapAndLock(admin, MAINNET_CURVE_ROUTER, address(yearnStakingDelegate)));
            vm.startPrank(admin);
            // sets gauge as reward and a 100% split to the strategy
            yearnStakingDelegate.addGaugeRewards(gauge, address(stakingDelegateRewards));
            yearnStakingDelegate.setSwapAndLock(address(swapAndLock));
            vm.stopPrank();
        }

        //// wrapped strategy ////
        {
            yearnGaugeStrategy = setUpWrappedStrategy(
                "Yearn Gauge Strategy", gauge, address(yearnStakingDelegate), MAINNET_DYFI, MAINNET_CURVE_ROUTER
            );
            vm.startPrank(tpManagement);
            // setting CurveRouterSwapper params for harvest rewards swapping
            CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
            // [token_from, pool, token_to, pool, ...]
            curveSwapParams.route[0] = MAINNET_DYFI;
            curveSwapParams.route[1] = MAINNET_DYFI_ETH_POOL;
            curveSwapParams.route[2] = MAINNET_WETH;
            curveSwapParams.route[3] = MAINNET_WETH_YETH_POOL;
            curveSwapParams.route[4] = MAINNET_WETH_YETH_POOL; // expect the lp token back

            // i, j, swap_type, pool_type, n_coins
            curveSwapParams.swapParams[0] = [uint256(0), 1, 1, 2, 2]; // dYFI -> wETH
            // wETH -> weth/yeth pool lp token, swap type is 4 to notify the swap router to call add_liquidity()
            curveSwapParams.swapParams[1] = [uint256(0), 0, 4, 1, 2];
            // set params for harvest rewards swapping
            yearnGaugeStrategy.setHarvestSwapParams(curveSwapParams);
            yearnGaugeStrategy.setMaxTotalAssets(type(uint256).max);
            vm.stopPrank();
        }
    }

    // Need a special function to airdrop to the gauge since it relies on totalSupply for calculation
    function _airdropGaugeTokens(address user, uint256 amount) internal {
        airdrop(ERC20(address(vault)), user, amount);
        vm.startPrank(user);
        IERC20(vault).approve(address(gauge), amount);
        IGauge(gauge).deposit(amount, user);
        vm.stopPrank();
    }

    function _setRewardSplit(uint80 treasurySplit, uint80 strategySplit, uint80 veYfiSplit) internal {
        vm.prank(admin);
        yearnStakingDelegate.setRewardSplit(gauge, treasurySplit, strategySplit, veYfiSplit);
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        uint256 expectedShares = yearnGaugeStrategy.previewDeposit(amount);
        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);
        // check for expected changes
        assertEq(yearnGaugeStrategy.balanceOf(alice), expectedShares, "Deposit was not successful");
        assertEq(
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            amount,
            "yearn staking delegate deposit failed"
        );
        assertEq(yearnGaugeStrategy.totalSupply(), expectedShares, "totalSupply did not update correctly");
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        uint256 expectedShares = yearnGaugeStrategy.previewDeposit(amount);
        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);

        vm.prank(alice);
        yearnGaugeStrategy.withdraw(expectedShares, alice, alice);
        assertEq(yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge), 0, "depositToGauge failed");
        assertEq(
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            0,
            "yearn staking delegate withdraw failed"
        );
        assertEq(yearnGaugeStrategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
        assertEq(yearnGaugeStrategy.balanceOf(alice), 0, "Withdraw was not successful");
    }

    function testFuzz_report_staking_rewards_profit_buh(uint256 amount) public {
        vm.assume(amount > 1e6); // Minimum deposit size is required to farm dYFI emission
        vm.assume(amount < 100_000 * 1e18); // limit deposit size to 100k ETH

        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Gauge rewards are currently active, warp block forward to accrue rewards
        vm.warp(block.timestamp + 1 weeks);
        // get the current rewards earned by the yearn staking delegate
        uint256 accruedRewards = IGauge(gauge).earned(address(yearnStakingDelegate));
        console.log("accruedRewards: %s", accruedRewards);

        // yearn staking delegate harvests available rewards
        vm.prank(admin);
        yearnStakingDelegate.harvest(gauge); // gets rewards from gauge and successfully calls
            // StakingDelegateRewards.notifyRewardAmount(reward)

        // Staking Delegate Rewards contract has accrued rewards and needs time to unlock them
        uint256 stakingDelegateperiodFinish = stakingDelegateRewards.periodFinish(gauge);
        console.log("reward rate", stakingDelegateRewards.rewardRate(gauge)); // 0
        console.log("reward per token stored: ", stakingDelegateRewards.rewardPerTokenStored(gauge)); // 0
        vm.warp(stakingDelegateperiodFinish); // not 0 does get set

        // manager calls report on the wrapped strategy
        vm.prank(tpManagement);
        (uint256 profit,) = yearnGaugeStrategy.report();
        assertGt(profit, 0, "profit should be greater than 0"); // always reporting 0

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(yearnGaugeStrategy)).profitMaxUnlockTime());

        // manager calls report
        vm.prank(tpManagement);
        yearnGaugeStrategy.report(); // here the StakingDelegateRewards.getReward() is called but does nothing meaning
            // the rewards() are empty

        uint256 afterTotalAssets = yearnGaugeStrategy.totalAssets();
        assertEq(
            afterTotalAssets,
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            "all assets should be deployed"
        );
        assertGt(afterTotalAssets, beforeTotalAssets, "report did not increase total assets");
    }

    function testFuzz_withdraw_duringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        uint256 expectedShares = yearnGaugeStrategy.previewDeposit(amount);
        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);

        // shutdown strategy
        vm.prank(tpManagement);
        yearnGaugeStrategy.shutdownStrategy();

        vm.prank(alice);
        yearnGaugeStrategy.withdraw(expectedShares, alice, alice);
        assertEq(yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge), 0, "depositToGauge failed");
        assertEq(
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            0,
            "yearn staking delegate withdraw failed"
        );
        assertEq(yearnGaugeStrategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
        assertEq(yearnGaugeStrategy.balanceOf(alice), 0, "Withdraw was not successful");
    }

    function testFuzz_deposit_duringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // shutdown strategy
        vm.prank(tpManagement);
        yearnGaugeStrategy.shutdownStrategy();
        // deposit into strategy happens
        _airdropGaugeTokens(alice, amount);
        vm.startPrank(alice);
        IERC20(yearnGaugeStrategy.asset()).safeApprove(address(yearnGaugeStrategy), amount);
        // TokenizedStrategy.maxDeposit() returns 0 on shutdown
        vm.expectRevert("ERC4626: deposit more than max");
        yearnGaugeStrategy.deposit(amount, alice);
    }

    function testFuzz_withdraw_duringShutdownReport(uint256 amount) public {
        vm.assume(amount > 1e6); // Minimum deposit size is required to farm dYFI emission
        vm.assume(amount < 100_000 * 1e18); // limit deposit size to 100k ETH

        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Simulate profit by mocking stakingDelegateRewards sending rewards on harvestAndReport()
        airdrop(ERC20(MAINNET_DYFI), address(stakingDelegateRewards), 1e18);

        // shutdown strategy
        vm.prank(tpManagement);
        yearnGaugeStrategy.shutdownStrategy();

        // manager calls report on the wrapped strategy
        vm.prank(tpManagement);
        (uint256 profit,) = yearnGaugeStrategy.report();
        assertGt(profit, 0, "profit should be greater than 0");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(yearnGaugeStrategy)).profitMaxUnlockTime());

        // manager calls report
        vm.prank(tpManagement);
        yearnGaugeStrategy.report();

        uint256 afterTotalAssets = yearnGaugeStrategy.totalAssets();
        assertEq(afterTotalAssets, beforeTotalAssets + profit, "report did not increase total assets");
    }
}

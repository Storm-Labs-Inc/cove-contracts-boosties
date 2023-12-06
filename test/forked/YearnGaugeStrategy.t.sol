// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "test/utils/YearnV3BaseTest.t.sol";
import { IStrategy } from "@tokenized-strategy/interfaces/IStrategy.sol";
import { IVault } from "yearn-vaults-v3/interfaces/IVault.sol";
import { IYearnGaugeStrategy } from "src/interfaces/IYearnGaugeStrategy.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { MockStakingDelegateRewards } from "test/mocks/MockStakingDelegateRewards.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";

contract YearnGaugeStrategy_ForkedTest is YearnV3BaseTest {
    using SafeERC20 for IERC20;

    IStrategy public mockStrategy;
    IYearnGaugeStrategy public wrappedYearnV3Strategy;
    MockYearnStakingDelegate public mockYearnStakingDelegate;
    MockStakingDelegateRewards public mockStakingDelegateRewards;
    IVault public vault;

    // Addresses
    address public alice;
    address public gauge;
    address public manager;
    address public treasury;

    function setUp() public override {
        super.setUp();
        //// generic ////
        alice = createUser("alice");
        manager = createUser("manager");
        treasury = createUser("treasury");
        vault = IVault(MAINNET_WETH_YETH_POOL_VAULT);
        vm.label(address(vault), "wethyethPoolVault");
        gauge = MAINNET_WETH_YETH_POOL_GAUGE;
        vm.label(gauge, "wethyethPoolGauge");

        // Deploy Mock Contracts
        mockYearnStakingDelegate = new MockYearnStakingDelegate();
        mockStakingDelegateRewards = new MockStakingDelegateRewards(MAINNET_DYFI);
        vm.label(address(mockYearnStakingDelegate), "mockYearnStakingDelegate");
        vm.label(address(mockStakingDelegateRewards), "mockStakingDelegateRewards");
        mockYearnStakingDelegate.setGaugeStakingRewards(address(mockStakingDelegateRewards));

        //// wrapped strategy ////
        {
            wrappedYearnV3Strategy = setUpWrappedStrategy(
                "Wrapped YearnV3 Strategy", gauge, address(mockYearnStakingDelegate), MAINNET_DYFI, MAINNET_CURVE_ROUTER
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
            wrappedYearnV3Strategy.setHarvestSwapParams(curveSwapParams);
            wrappedYearnV3Strategy.setMaxTotalAssets(type(uint256).max);
            vm.stopPrank();
        }
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        uint256 expectedShares = wrappedYearnV3Strategy.previewDeposit(amount);
        // deposit into strategy happens
        mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, gauge);
        // check for expected changes
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), expectedShares, "Deposit was not successful");
        assertEq(
            mockYearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge),
            amount,
            "yearn staking delegate deposit failed"
        );
        assertEq(wrappedYearnV3Strategy.totalSupply(), expectedShares, "totalSupply did not update correctly");
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        uint256 expectedShares = wrappedYearnV3Strategy.previewDeposit(amount);
        // deposit into strategy happens
        mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, gauge);

        vm.prank(alice);
        wrappedYearnV3Strategy.withdraw(expectedShares, alice, alice);
        assertEq(mockYearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge), 0, "depositToGauge failed");
        assertEq(
            mockYearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge),
            0,
            "yearn staking delegate withdraw failed"
        );
        assertEq(wrappedYearnV3Strategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), 0, "Withdraw was not successful");
    }

    function testFuzz_report_staking_rewards_profit(uint256 amount) public {
        vm.assume(amount > 1e6); // Minimum deposit size is required to farm dYFI emission
        vm.assume(amount < 100_000 * 1e18); // limit deposit size to 100k ETH

        // deposit into strategy happens
        mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, gauge);
        uint256 shares = wrappedYearnV3Strategy.balanceOf(alice);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Gauge rewards are currently active, warp block forward to accrue rewards
        vm.warp(block.timestamp + 1 weeks);
        // get the current rewards earned by the yearn staking delegate
        uint256 accruedRewards = IGauge(gauge).earned(address(mockYearnStakingDelegate));
        // send earned rewards to the staking delegate rewards contract
        airdrop(ERC20(MAINNET_DYFI), address(mockStakingDelegateRewards), accruedRewards);

        // manager calls report on the wrapped strategy
        vm.prank(tpManagement);
        (uint256 profit,) = wrappedYearnV3Strategy.report();
        assertGt(profit, 0, "profit should be greater than 0");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(wrappedYearnV3Strategy)).profitMaxUnlockTime());

        // manager calls report
        vm.prank(tpManagement);
        wrappedYearnV3Strategy.report();

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        assertEq(
            afterTotalAssets,
            mockYearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge),
            "all assets should be deployed"
        );
        assertEq(afterTotalAssets, beforeTotalAssets + profit, "report did not increase total assets");
    }

    function testFuzz_report_passWhen_noProfits(uint256 amount) public {
        vm.assume(amount > 1e6); // Minimum deposit size is required to farm dYFI emission
        vm.assume(amount < 100_000 * 1e18); // limit deposit size to 100k ETH

        // deposit into strategy happens
        mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, gauge);
        uint256 shares = wrappedYearnV3Strategy.balanceOf(alice);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // manager calls report on the wrapped strategy
        vm.prank(tpManagement);
        wrappedYearnV3Strategy.report();

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(wrappedYearnV3Strategy)).profitMaxUnlockTime());

        // manager calls report
        vm.prank(tpManagement);
        (uint256 profit, uint256 loss) = wrappedYearnV3Strategy.report();
        assertEq(profit, 0, "profit should be 0");
        assertEq(loss, 0, "loss should be 0");
    }

    function testFuzz_withdraw_duringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        uint256 expectedShares = wrappedYearnV3Strategy.previewDeposit(amount);
        // deposit into strategy happens
        mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, gauge);

        // shutdown strategy
        vm.prank(tpManagement);
        wrappedYearnV3Strategy.shutdownStrategy();

        vm.prank(alice);
        wrappedYearnV3Strategy.withdraw(expectedShares, alice, alice);
        assertEq(mockYearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge), 0, "depositToGauge failed");
        assertEq(
            mockYearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), gauge),
            0,
            "yearn staking delegate withdraw failed"
        );
        assertEq(wrappedYearnV3Strategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), 0, "Withdraw was not successful");
    }

    function testFuzz_deposit_duringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // shutdown strategy
        vm.prank(tpManagement);
        wrappedYearnV3Strategy.shutdownStrategy();
        // deposit into strategy happens
        airdrop(ERC20(gauge), alice, amount);
        vm.startPrank(alice);
        IERC20(wrappedYearnV3Strategy.asset()).safeApprove(address(wrappedYearnV3Strategy), amount);
        // TokenizedStrategy.maxDeposit() returns 0 on shutdown
        vm.expectRevert("ERC4626: deposit more than max");
        wrappedYearnV3Strategy.deposit(amount, alice);
    }

    function testFuzz_withdraw_duringShutdownReport(uint256 amount) public {
        vm.assume(amount > 1e6); // Minimum deposit size is required to farm dYFI emission
        vm.assume(amount < 100_000 * 1e18); // limit deposit size to 100k ETH

        // deposit into strategy happens
        mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, gauge);
        uint256 shares = wrappedYearnV3Strategy.balanceOf(alice);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Simulate profit by mocking stakingDelegateRewards sending rewards on harvestAndReport()
        airdrop(ERC20(MAINNET_DYFI), address(mockStakingDelegateRewards), 1e18);

        // shutdown strategy
        vm.prank(tpManagement);
        wrappedYearnV3Strategy.shutdownStrategy();

        // manager calls report on the wrapped strategy
        vm.prank(tpManagement);
        (uint256 profit,) = wrappedYearnV3Strategy.report();
        assertGt(profit, 0, "profit should be greater than 0");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(wrappedYearnV3Strategy)).profitMaxUnlockTime());

        // manager calls report
        vm.prank(tpManagement);
        wrappedYearnV3Strategy.report();

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        assertEq(afterTotalAssets, beforeTotalAssets + profit, "report did not increase total assets");
    }

    function test_setHarvestSwapParams_nonManager() public {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_DYFI;
        curveSwapParams.route[1] = MAINNET_DYFI_ETH_POOL;
        curveSwapParams.route[2] = MAINNET_ETH;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_USDC;
        curveSwapParams.route[4] = MAINNET_USDC;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 1, 1, 2, 2]; // dYFI -> ETH
        curveSwapParams.swapParams[1] = [uint256(2), 0, 1, 2, 3]; // ETH -> USDC
        // set params for harvest rewards swapping
        vm.prank(alice);
        vm.expectRevert("!management");
        wrappedYearnV3Strategy.setHarvestSwapParams(curveSwapParams);
    }

    function test_setHarvestSwapParams_validateSwapParams_revertWhen_InvalidCoinIndex() public {
        vm.startPrank(tpManagement);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // Set route to include a token index that does not exist in the given pools
        curveSwapParams.route[0] = MAINNET_DYFI;
        curveSwapParams.route[1] = MAINNET_DYFI_ETH_POOL;
        curveSwapParams.route[2] = MAINNET_ETH;
        curveSwapParams.route[3] = MAINNET_WETH_YETH_POOL;
        curveSwapParams.route[4] = MAINNET_WETH_YETH_POOL;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 1, 1, 2, 2]; // dYFI -> ETH
        curveSwapParams.swapParams[1] = [uint256(5), 1, 4, 1, 2];
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSwapParams.selector));
        wrappedYearnV3Strategy.setHarvestSwapParams(curveSwapParams);
    }
}

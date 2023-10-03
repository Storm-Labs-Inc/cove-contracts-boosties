// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "src/interfaces/deps/yearn/tokenized-strategy/IStrategy.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { ICurveTwoAssetPool } from "src/interfaces/deps/curve/ICurveTwoAssetPool.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { IERC20, SafeERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { IGaugeFactory } from "src/interfaces/deps/yearn/veYFI/IGaugeFactory.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { Errors } from "../src/libraries/Errors.sol";

contract WrappedStrategyTest is YearnV3BaseTest {
    IStrategy public mockStrategy;
    IWrappedYearnV3Strategy public wrappedYearnV3Strategy;
    YearnStakingDelegate public yearnStakingDelegate;
    IVault public deployedVault;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 1000e18;

    // Addresses
    address public alice;
    address public testGauge;
    address public manager;
    address public treasury;

    function setUp() public override {
        super.setUp();
        //// generic ////
        alice = createUser("alice");
        manager = createUser("manager");
        treasury = createUser("treasury");
        mockStrategy = setUpStrategy("Mock USDC Strategy", MAINNET_USDC);
        address[] memory strategies = new address[](1);
        strategies[0] = address(mockStrategy);
        deployedVault = IVault(deployVaultV3("USDC Vault", MAINNET_USDC, strategies));

        //// yearn staking delegate ////
        {
            yearnStakingDelegate = YearnStakingDelegate(setUpYearnStakingDelegate(treasury, admin, manager));
            // Deploy gauge
            testGauge = deployGaugeViaFactory(address(deployedVault), admin, "Test Gauge for USDC Vault");
            // Give admin some dYFI
            airdrop(ERC20(MAINNET_YFI), alice, ALICE_YFI);
            airdrop(ERC20(dYFI), admin, DYFI_REWARD_AMOUNT);
            // Start new rewards
            vm.startPrank(admin);
            IERC20(dYFI).approve(testGauge, DYFI_REWARD_AMOUNT);
            IGauge(testGauge).queueNewRewards(DYFI_REWARD_AMOUNT);
            require(IERC20(dYFI).balanceOf(testGauge) == DYFI_REWARD_AMOUNT, "queueNewRewards failed");
            yearnStakingDelegate.setAssociatedGauge(address(deployedVault), testGauge);

            vm.stopPrank();

            require(IERC20(dYFI).balanceOf(testGauge) == DYFI_REWARD_AMOUNT, "queueNewRewards failed");
            yearnStakingDelegate = YearnStakingDelegate(setUpYearnStakingDelegate(treasury, admin, manager));
            vm.prank(admin);
            yearnStakingDelegate.setAssociatedGauge(address(deployedVault), testGauge);
        }

        //// wrapped strategy ////
        {
            wrappedYearnV3Strategy = setUpWrappedStrategy(
                "Wrapped YearnV3 Strategy",
                MAINNET_USDC,
                address(deployedVault),
                address(yearnStakingDelegate),
                dYFI,
                MAINNET_CURVE_ROUTER
            );
            vm.startPrank(tpManagement);
            // setting CurveRouterSwapper params for harvest rewards swapping
            CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
            // [token_from, pool, token_to, pool, ...]
            curveSwapParams.route[0] = dYFI;
            curveSwapParams.route[1] = dYfiEthCurvePool;
            curveSwapParams.route[2] = MAINNET_ETH;
            curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_USDC;
            curveSwapParams.route[4] = MAINNET_USDC;

            // i, j, swap_type, pool_type, n_coins
            curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2]; // dYFI -> ETH
            curveSwapParams.swapParams[1] = [uint256(2), 0, 1, 2, 3]; // ETH -> USDC
            // set params for harvest rewards swapping
            wrappedYearnV3Strategy.setHarvestSwapPrams(curveSwapParams);
            vm.stopPrank();
        }
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount != 0);
        // limit fuzzing to ysd.userInfo.balance type max
        vm.assume(amount < type(uint128).max);
        deal({ token: MAINNET_USDC, to: users["alice"], give: amount });
        // deposit into strategy happens
        depositIntoStrategy(wrappedYearnV3Strategy, users["alice"], amount);
        // check for expected changes
        assertEq(deployedVault.balanceOf(testGauge), amount, "depositToGauge failed");
        uint128 userBalance = IYearnStakingDelegate(address(yearnStakingDelegate)).userInfo(
            address(wrappedYearnV3Strategy), address(deployedVault)
        ).balance;
        assertEq(userBalance, amount, "userInfo in ysd not updated correctly");
        assertEq(deployedVault.totalSupply(), amount, "vault total_supply did not update correctly");
        assertEq(wrappedYearnV3Strategy.balanceOf(users["alice"]), amount, "Deposit was not successful");
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount != 0);
        // limit fuzzing to ysd.userInfo.balance type max
        vm.assume(amount < type(uint128).max);
        deal({ token: MAINNET_USDC, to: users["alice"], give: amount });
        depositIntoStrategy(wrappedYearnV3Strategy, users["alice"], amount);
        // withdraw from strategy happens
        vm.prank(users["alice"]);
        wrappedYearnV3Strategy.withdraw(amount, users["alice"], users["alice"], 0);
        // check for expected changes
        assertEq(deployedVault.balanceOf(testGauge), 0, "withdrawFromGauge failed");
        uint128 userBalance = IYearnStakingDelegate(address(yearnStakingDelegate)).userInfo(
            address(wrappedYearnV3Strategy), address(deployedVault)
        ).balance;
        assertEq(userBalance, 0, "userInfo in ysd not updated correctly");
        assertEq(
            deployedVault.balanceOf(wrappedYearnV3Strategy.yearnStakingDelegate()),
            0,
            "vault shares not taken from delegate"
        );
        assertEq(deployedVault.totalSupply(), 0, "vault total_supply did not update correctly");
        assertEq(wrappedYearnV3Strategy.balanceOf(users["alice"]), 0, "Withdraw was not successful");
        assertEq(
            ERC20(MAINNET_USDC).balanceOf(users["alice"]),
            amount,
            "user balance should be deposit amount after withdraw"
        );
    }

    function test_harvestAndReport() public {
        // TODO: integrate fuzzing in future testing
        // vm.assume(amount > 0);
        // // limit fuzzing to ysd.userInfo.balance type max
        // vm.assume(amount < type(uint128).max);
        uint256 amount = 1e18;
        // alice locks her YFI
        vm.startPrank(users["alice"]);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), ALICE_YFI);
        yearnStakingDelegate.lockYfi(ALICE_YFI);
        vm.stopPrank();

        // alice deposits into vault
        deal({ token: MAINNET_USDC, to: users["alice"], give: amount });
        // deposit into strategy happens
        depositIntoStrategy(wrappedYearnV3Strategy, users["alice"], amount);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();

        // warp blocks forward to accrue rewards
        vm.warp(block.timestamp + 14 days);

        // manager calls harvestAndReport
        vm.prank(tpManagement);
        wrappedYearnV3Strategy.report();

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        assertGt(afterTotalAssets, beforeTotalAssets, "harvestAndReport did not increase total assets");
    }

    function test_harvestAndReport_passWhenRelocking() public {
        // TODO: integrate fuzzing in future testing
        // vm.assume(amount > 0);
        // // limit fuzzing to ysd.userInfo.balance type max
        // vm.assume(amount < type(uint128).max);
        uint256 amount = 1e18;
        // set reward split to 50/50
        vm.prank(admin);
        yearnStakingDelegate.setRewardSplit(0, 0.5e18, 0.5e18);
        // alice locks her YFI
        vm.startPrank(users["alice"]);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), ALICE_YFI);
        yearnStakingDelegate.lockYfi(ALICE_YFI);
        vm.stopPrank();

        // alice deposits into vault
        deal({ token: MAINNET_USDC, to: users["alice"], give: amount });
        // deposit into strategy happens
        depositIntoStrategy(wrappedYearnV3Strategy, users["alice"], amount);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();

        // warp blocks forward to accrue rewards
        vm.warp(block.timestamp + 14 days);

        // manager calls harvestAndReport
        vm.prank(tpManagement);
        wrappedYearnV3Strategy.report();

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        assertGt(afterTotalAssets, beforeTotalAssets, "harvestAndReport did not increase total assets");
    }
}

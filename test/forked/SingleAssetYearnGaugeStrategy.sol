// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "test/utils/YearnV3BaseTest.t.sol";
import { IStrategy } from "@tokenized-strategy/interfaces/IStrategy.sol";
import { IVault } from "yearn-vaults-v3/interfaces/IVault.sol";
import { ISingleAssetYearnGaugeStrategy } from "src/interfaces/ISingleAssetYearnGaugeStrategy.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { Errors } from "src/libraries/Errors.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { MockStakingDelegateRewards } from "test/mocks/MockStakingDelegateRewards.sol";

contract WrappedStrategy_ForkedTest is YearnV3BaseTest {
    using SafeERC20 for IERC20;

    IStrategy public mockStrategy;
    ISingleAssetYearnGaugeStrategy public wrappedYearnV3Strategy;
    MockYearnStakingDelegate public mockYearnStakingDelegate;
    MockStakingDelegateRewards public mockStakingDelegateRewards;
    IVault public deployedVault;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 10e18;

    // Addresses
    address public alice;
    address public testGauge;
    address public manager;
    address public treasury;
    address public deployedGauge = address(0);

    function setUp() public override {
        super.setUp();
        //// generic ////
        alice = createUser("alice");
        manager = createUser("manager");
        treasury = createUser("treasury");
        (address _deployedVault, address _mockStrategy) = deployVaultV3WithMockStrategy("USDC Vault", MAINNET_USDC);
        deployedVault = IVault(_deployedVault);
        vm.label(_deployedVault, "deployedVault");
        mockStrategy = IStrategy(_mockStrategy);
        vm.label(_mockStrategy, "mockStrategy");
        mockYearnStakingDelegate = new MockYearnStakingDelegate();
        mockStakingDelegateRewards = new MockStakingDelegateRewards(MAINNET_DYFI);
        vm.label(address(mockYearnStakingDelegate), "mockYearnStakingDelegate");
        vm.label(address(mockStakingDelegateRewards), "mockStakingDelegateRewards");
        mockYearnStakingDelegate.setGaugeStakingRewards(address(mockStakingDelegateRewards));

        // Deploy gauge
        testGauge = deployGaugeViaFactory(_deployedVault, admin, "USDC Test Vault Gauge");

        vm.label(testGauge, "testGauge");

        //// wrapped strategy ////
        {
            wrappedYearnV3Strategy = setUpWrappedStrategy(
                "Wrapped YearnV3 Strategy",
                testGauge,
                address(mockYearnStakingDelegate),
                MAINNET_DYFI,
                MAINNET_CURVE_ROUTER
            );
            vm.startPrank(tpManagement);
            // setting CurveRouterSwapper params for harvest rewards swapping
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
            wrappedYearnV3Strategy.setHarvestSwapParams(curveSwapParams);
            wrappedYearnV3Strategy.setMaxTotalAssets(type(uint256).max);
            vm.stopPrank();
        }
    }

    function _setUpDYfiRewards() internal {
        // Start new rewards
        vm.startPrank(admin);
        IERC20(MAINNET_DYFI).approve(testGauge, DYFI_REWARD_AMOUNT);
        IGauge(testGauge).queueNewRewards(DYFI_REWARD_AMOUNT);
        if (IERC20(MAINNET_DYFI).balanceOf(testGauge) != DYFI_REWARD_AMOUNT) {
            revert Errors.QueueNewRewardsFailed();
        }
        vm.stopPrank();
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        uint256 expectedShares = wrappedYearnV3Strategy.previewDeposit(amount);
        // deposit into strategy happens
        mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, testGauge);
        // check for expected changes
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), expectedShares, "Deposit was not successful");
        assertEq(
            mockYearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), testGauge),
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
        mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, testGauge);

        vm.prank(alice);
        wrappedYearnV3Strategy.withdraw(expectedShares, alice, alice);
        assertEq(
            mockYearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), testGauge), 0, "depositToGauge failed"
        );
        assertEq(
            mockYearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), testGauge),
            0,
            "yearn staking delegate withdraw failed"
        );
        assertEq(wrappedYearnV3Strategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(testGauge).balanceOf(alice), amount, "asset was not returned on withdraw");
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), 0, "Withdraw was not successful");
    }

    function testFuzz_report_staking_rewards_profit(uint256 amount) public {
        vm.assume(amount > 1e6); // Minimum deposit size is required to farm dYFI emission
        vm.assume(amount < 1_000_000_000 * 1e6); // limit deposit size to 1 Billion USDC
        // DYI emissions are setup
        // _setUpDYfiRewards();

        // deposit into strategy happens
        mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, testGauge);
        uint256 shares = wrappedYearnV3Strategy.balanceOf(alice);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Simulate profit by mocking stakingDelegateRewards sending rewards on harvestAndReport()
        airdrop(ERC20(MAINNET_DYFI), address(mockStakingDelegateRewards), 1e18);

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
        assertGt(afterTotalAssets, beforeTotalAssets, "report did not increase total assets");
    }

    function testFuzz_report_passWhen_noProfits(uint256 amount) public {
        vm.assume(amount > 1e6); // Minimum deposit size is required to farm dYFI emission
        vm.assume(amount < 1_000_000_000 * 1e6); // limit deposit size to 1 Billion USDC
        // DYI emissions are setup
        // _setUpDYfiRewards();

        // deposit into strategy happens
        mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, testGauge);
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
        mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, testGauge);

        // shutdown strategy
        vm.prank(tpManagement);
        wrappedYearnV3Strategy.shutdownStrategy();

        vm.prank(alice);
        wrappedYearnV3Strategy.withdraw(expectedShares, alice, alice);
        assertEq(
            mockYearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), testGauge), 0, "depositToGauge failed"
        );
        assertEq(
            mockYearnStakingDelegate.balanceOf(address(wrappedYearnV3Strategy), testGauge),
            0,
            "yearn staking delegate withdraw failed"
        );
        assertEq(wrappedYearnV3Strategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(testGauge).balanceOf(alice), amount, "asset was not returned on withdraw");
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), 0, "Withdraw was not successful");
    }

    function testFuzz_deposit_duringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // shutdown strategy
        vm.prank(tpManagement);
        wrappedYearnV3Strategy.shutdownStrategy();
        // deposit into strategy happens
        airdrop(ERC20(testGauge), alice, amount);
        vm.startPrank(alice);
        IERC20(wrappedYearnV3Strategy.asset()).safeApprove(address(wrappedYearnV3Strategy), amount);
        // TokenizedStrategy.maxDeposit() returns 0 on shutdown
        vm.expectRevert("ERC4626: deposit more than max");
        wrappedYearnV3Strategy.deposit(amount, alice);
    }

    // function testFuzz_withdraw_duringShutdownReport(uint256 amount) public {
    //     vm.assume(amount > 1e6); // Minimum deposit size is required to farm dYFI emission
    //     vm.assume(amount < 1_000_000_000 * 1e6); // limit deposit size to 1 Billion USDC

    //     // deposit into strategy happens
    //     mintAndDepositIntoStrategy(wrappedYearnV3Strategy, alice, amount, testGauge);
    //     uint256 shares = wrappedYearnV3Strategy.balanceOf(alice);
    //     uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
    //     uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(shares);
    //     assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
    //     assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

    //     // Simulate profit by mocking stakingDelegateRewards sending rewards on harvestAndReport()
    //     airdrop(ERC20(MAINNET_DYFI), address(mockStakingDelegateRewards), 1e18);

    //     // shutdown strategy
    //     vm.prank(tpManagement);
    //     wrappedYearnV3Strategy.shutdownStrategy();

    //     // manager calls report on the wrapped strategy
    //     vm.prank(tpManagement);
    //     (uint256 profit,) = wrappedYearnV3Strategy.report();
    //     assertGt(profit, 0, "profit should be greater than 0");

    //     // warp blocks forward to profit locking is finished
    //     vm.warp(block.timestamp + IStrategy(address(wrappedYearnV3Strategy)).profitMaxUnlockTime());

    //     // manager calls report
    //     vm.prank(tpManagement);
    //     wrappedYearnV3Strategy.report();

    //     uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
    //     // todo: fails here, this should increase even during shutdown?
    //     // assertGt(afterTotalAssets, beforeTotalAssets, "report did not increase total assets");
    // }

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

    function test_SetSwapParams_validateSwapParams() public {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_DYFI;
        curveSwapParams.route[1] = MAINNET_DYFI_ETH_POOL;
        curveSwapParams.route[2] = MAINNET_ETH;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_USDC;
        curveSwapParams.route[4] = MAINNET_USDC;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 1, 1, 2, 2]; // dYFI -> ETH
        // coin index is incorrect
        curveSwapParams.swapParams[1] = [uint256(2), 2, 1, 2, 3]; // ETH -> USDC
        // set params for harvest rewards swapping
        vm.startPrank(tpManagement);
        // abi.encodeWithSelector(Errors.OnlyMintingEnabled.selector)
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidCoinIndex.selector));
        wrappedYearnV3Strategy.setHarvestSwapParams(curveSwapParams);

        // swap does not end in strategy base asset, but index is correct
        curveSwapParams.route[4] = MAINNET_ETH;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidToToken.selector, MAINNET_USDC, MAINNET_ETH));
        wrappedYearnV3Strategy.setHarvestSwapParams(curveSwapParams);
    }

    // function testFuzz_report_passWhen_onlyUnderlyingVaultProfits(
    //     uint256 amount,
    //     uint256 underlyingVaultProfit
    // )
    //     public
    // {
    // }
}

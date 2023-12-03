// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { IStrategy } from "@tokenized-strategy/interfaces/IStrategy.sol";
import { IVault } from "yearn-vaults-v3/interfaces/IVault.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { MockYearnStakingDelegate } from "./mocks/MockYearnStakingDelegate.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { Errors } from "src/libraries/Errors.sol";
import { MockYearnStakingDelegate } from "./mocks/MockYearnStakingDelegate.sol";
import { MockStakingDelegateRewards } from "./mocks/MockStakingDelegateRewards.sol";

contract WrappedStrategyTest is YearnV3BaseTest {
    IStrategy public mockStrategy;
    IWrappedYearnV3Strategy public wrappedYearnV3Strategy;
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
        mockStakingDelegateRewards = new MockStakingDelegateRewards(MAINNET_DYFI, address(0));
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
            mockYearnStakingDelegate.balances(testGauge, address(wrappedYearnV3Strategy)),
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
            mockYearnStakingDelegate.balances(testGauge, address(wrappedYearnV3Strategy)), 0, "depositToGauge failed"
        );
        assertEq(
            mockYearnStakingDelegate.balances(testGauge, address(wrappedYearnV3Strategy)),
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
        wrappedYearnV3Strategy.report();

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(wrappedYearnV3Strategy)).profitMaxUnlockTime());

        // manager calls report
        vm.prank(tpManagement);
        (uint256 profit, uint256 loss) = wrappedYearnV3Strategy.report();

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 afterPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(shares);
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

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 afterPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(shares);
        assertGt(afterTotalAssets, beforeTotalAssets, "report did not increase total assets");
    }

    // function testFuzz_report_passWhen_noProfits(uint256 amount) public {
    //     vm.assume(amount > 0);
    //     vm.assume(amount < 1_000_000_000 * 1e6); // limit deposit size to 1 Billion USDC
    //     // alice locks her YFI
    //     vm.startPrank(alice);
    //     IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), ALICE_YFI);
    //     yearnStakingDelegate.lockYfi(ALICE_YFI);
    //     vm.stopPrank();

    //     // alice deposits into vault
    //     deal({ token: MAINNET_USDC, to: alice, give: amount });
    //     // deposit into strategy happens
    //     uint256 ownedShares = depositIntoStrategy(wrappedYearnV3Strategy, alice, amount);
    //     addDebtToStrategy(deployedVault, mockStrategy, amount);

    //     uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
    //     uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
    //     assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
    //     assertEq(beforePreviewRedeem, amount, "redeemable asset should not change");

    //     // manager calls report
    //     vm.prank(tpManagement);
    //     (uint256 profit, uint256 loss) = wrappedYearnV3Strategy.report();

    //     uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
    //     uint256 afterPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
    //     assertEq(afterTotalAssets, beforeTotalAssets, "report did not increase total assets");
    //     assertEq(afterPreviewRedeem, beforePreviewRedeem, "unexpected profit");
    //     assertEq(profit, 0, "report did not report 0 profit");
    //     assertEq(loss, 0, "report did not report 0 loss");

    //     // warp blocks forward to profit locking is finished
    //     vm.warp(block.timestamp + IStrategy(address(wrappedYearnV3Strategy)).profitMaxUnlockTime());

    //     uint256 profitUnlockedPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
    //     assertEq(profitUnlockedPreviewRedeem, afterPreviewRedeem, "unexpected profit");
    // }

    // function testFuzz_report_passWhen_onlyUnderlyingVaultProfits(
    //     uint256 amount,
    //     uint256 underlyingVaultProfit
    // )
    //     public
    // {
    //     vm.assume(amount > 1e6); // Minimum deposit size is required to farm underlying vault profit
    //     vm.assume(amount < 1_000_000_000 * 1e6); // limit deposit size to 1 Billion USDC
    //     vm.assume(underlyingVaultProfit > 1e6); // Minimum profit size is required to test
    //     vm.assume(underlyingVaultProfit < 1_000_000_000 * 1e6); // limit profit size to 1 Billion USDC
    //     // alice locks her YFI
    //     vm.startPrank(alice);
    //     IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), ALICE_YFI);
    //     yearnStakingDelegate.lockYfi(ALICE_YFI);
    //     vm.stopPrank();

    //     // alice deposits into vault
    //     deal({ token: MAINNET_USDC, to: alice, give: amount });
    //     // deposit into strategy happens
    //     uint256 ownedShares = depositIntoStrategy(wrappedYearnV3Strategy, alice, amount);
    //     addDebtToStrategy(deployedVault, mockStrategy, amount);
    //     uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
    //     uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
    //     uint256 beforePerformanceFeeRecipientOwnedShares =
    // wrappedYearnV3Strategy.balanceOf(tpPerformanceFeeRecipient);

    //     // Increase underlying vault's value
    //     increaseMockStrategyValue(address(deployedVault), address(mockStrategy), underlyingVaultProfit);
    //     // warp blocks forward to yearn's strategy's profit locking is finished
    //     vm.warp(block.timestamp + IStrategy(address(mockStrategy)).profitMaxUnlockTime());
    //     // Yearn vault process report
    //     reportAndProcessProfits(address(deployedVault), address(mockStrategy));
    //     // warp blocks forward to yearn's vault's profit locking is finished
    //     vm.warp(block.timestamp + IStrategy(address(mockStrategy)).profitMaxUnlockTime());
    //     reportAndProcessProfits(address(deployedVault), address(mockStrategy));

    //     // manager calls report
    //     vm.prank(tpManagement);
    //     (uint256 profit, uint256 loss) = wrappedYearnV3Strategy.report();

    //     uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
    //     uint256 afterPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
    //     uint256 afterPerformanceFeeRecipientOwnedShares =
    // wrappedYearnV3Strategy.balanceOf(tpPerformanceFeeRecipient);
    //     assertGe(afterTotalAssets, beforeTotalAssets, "report did not increase total assets");
    //     assertEq(afterPreviewRedeem, beforePreviewRedeem, "report did not lock profit");
    //     assertEq(
    //         profit * 1e2 / (wrappedYearnV3Strategy.performanceFee()), // performance fee like 10_000 == 100%
    //         afterPerformanceFeeRecipientOwnedShares - beforePerformanceFeeRecipientOwnedShares,
    //         "correct profit not given to performance fee recipient"
    //     );
    //     assertEq(profit + beforeTotalAssets, afterTotalAssets, "report did not report correct profit");
    //     assertEq(loss, 0, "report did not report 0 loss");

    //     // warp blocks forward to our strategy's profit locking is finished
    //     vm.warp(block.timestamp + IStrategy(address(mockStrategy)).profitMaxUnlockTime());

    //     uint256 profitUnlockedPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
    //     assertGt(profitUnlockedPreviewRedeem, afterPreviewRedeem, "redeemable asset per share increased over time");
    // }

    // function testFuzz_report_passWhen_relocking(uint256 amount) public {
    //     vm.assume(amount > 1e6); // Minimum required for farming dYFI emission
    //     vm.assume(amount < 1_000_000_000 * 1e6); // Maximum deposit size is 1 Billion USDC
    //     _setUpDYfiRewards();

    //     // set reward split to 50/50
    //     vm.prank(admin);
    //     yearnStakingDelegate.setRewardSplit(deployedGauge, 0, 0.5e18, 0.5e18);
    //     // alice locks her YFI
    //     vm.startPrank(alice);
    //     IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), ALICE_YFI);
    //     yearnStakingDelegate.lockYfi(ALICE_YFI);
    //     vm.stopPrank();

    //     // alice deposits into vault
    //     deal({ token: MAINNET_USDC, to: alice, give: amount });
    //     // deposit into strategy happens
    //     depositIntoStrategy(wrappedYearnV3Strategy, alice, amount);
    //     uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();

    //     // warp blocks forward to accrue rewards
    //     vm.warp(block.timestamp + 14 days);

    //     // manager calls report
    //     vm.prank(tpManagement);
    //     wrappedYearnV3Strategy.report();

    //     uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
    //     assertGt(afterTotalAssets, beforeTotalAssets, "report did not increase total assets");
    // }
}

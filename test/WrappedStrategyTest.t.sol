// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { IStrategy } from "src/interfaces/deps/yearn/tokenized-strategy/IStrategy.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";

contract WrappedStrategyTest is YearnV3BaseTest {
    IStrategy public mockStrategy;
    IWrappedYearnV3Strategy public wrappedYearnV3Strategy;
    YearnStakingDelegate public yearnStakingDelegate;
    IVault public deployedVault;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 10e18;

    // Addresses
    address public alice;
    address public deployedGauge;
    address public manager;
    address public treasury;

    function setUp() public override {
        super.setUp();
        //// generic ////
        alice = createUser("alice");
        manager = createUser("manager");
        treasury = createUser("treasury");
        (address _deployedVault, address _mockStrategy) = deployVaultV3WithMockStrategy("USDC Vault", MAINNET_USDC);
        deployedVault = IVault(_deployedVault);
        mockStrategy = IStrategy(_mockStrategy);

        //// yearn staking delegate ////
        {
            yearnStakingDelegate = YearnStakingDelegate(setUpYearnStakingDelegate(treasury, admin, manager));
            // Deploy gauge
            deployedGauge = deployGaugeViaFactory(address(deployedVault), admin, "Test Gauge for USDC Vault");
            // Give admin some dYFI
            airdrop(ERC20(MAINNET_YFI), alice, ALICE_YFI);
            airdrop(ERC20(MAINNET_DYFI), admin, DYFI_REWARD_AMOUNT);
            vm.prank(admin);
            yearnStakingDelegate.setAssociatedGauge(address(deployedVault), deployedGauge);
        }

        //// wrapped strategy ////
        {
            wrappedYearnV3Strategy = setUpWrappedStrategy(
                "Wrapped YearnV3 Strategy",
                MAINNET_USDC,
                address(deployedVault),
                address(yearnStakingDelegate),
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
        IERC20(MAINNET_DYFI).approve(deployedGauge, DYFI_REWARD_AMOUNT);
        IGauge(deployedGauge).queueNewRewards(DYFI_REWARD_AMOUNT);
        require(IERC20(MAINNET_DYFI).balanceOf(deployedGauge) == DYFI_REWARD_AMOUNT, "queueNewRewards failed");
        vm.stopPrank();
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount != 0);
        // limit fuzzing to ysd.userInfo.balance type max
        vm.assume(amount < type(uint128).max);
        _setUpDYfiRewards();
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        // deposit into strategy happens
        depositIntoStrategy(wrappedYearnV3Strategy, alice, amount);
        // check for expected changes
        assertEq(deployedVault.balanceOf(deployedGauge), amount, "depositToGauge failed");
        uint128 userBalance = IYearnStakingDelegate(address(yearnStakingDelegate)).userInfo(
            address(wrappedYearnV3Strategy), address(deployedVault)
        ).balance;
        assertEq(userBalance, amount, "userInfo in ysd not updated correctly");
        assertEq(deployedVault.totalSupply(), amount, "vault total_supply did not update correctly");
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), amount, "Deposit was not successful");
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount != 0);
        // limit fuzzing to ysd.userInfo.balance type max
        vm.assume(amount < type(uint128).max);
        _setUpDYfiRewards();
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        depositIntoStrategy(wrappedYearnV3Strategy, alice, amount);
        // withdraw from strategy happens
        vm.prank(alice);
        wrappedYearnV3Strategy.withdraw(amount, alice, alice, 0);
        // check for expected changes
        assertEq(deployedVault.balanceOf(deployedGauge), 0, "withdrawFromGauge failed");
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
        assertEq(wrappedYearnV3Strategy.balanceOf(alice), 0, "Withdraw was not successful");
        assertEq(ERC20(MAINNET_USDC).balanceOf(alice), amount, "user balance should be deposit amount after withdraw");
    }

    function testFuzz_report(uint256 amount) public {
        vm.assume(amount > 1e6); // Minimum deposit size is required to farm dYFI emission
        vm.assume(amount < 1_000_000_000 * 1e6); // limit deposit size to 1 Billion USDC
        _setUpDYfiRewards();
        // alice locks her YFI
        vm.startPrank(alice);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), ALICE_YFI);
        yearnStakingDelegate.lockYfi(ALICE_YFI);
        vm.stopPrank();

        // alice deposits into vault
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        // deposit into strategy happens
        uint256 ownedShares = depositIntoStrategy(wrappedYearnV3Strategy, alice, amount);
        addDebtToStrategy(deployedVault, mockStrategy, amount);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // warp blocks forward to accrue rewards
        vm.warp(block.timestamp + 14 days);

        // manager calls report
        vm.prank(tpManagement);
        (uint256 profit, uint256 loss) = wrappedYearnV3Strategy.report();

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 afterPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
        assertGt(afterTotalAssets, beforeTotalAssets, "report did not increase total assets");
        assertEq(afterPreviewRedeem, beforePreviewRedeem, "report did not lock profit");
        assertEq(profit + beforeTotalAssets, afterTotalAssets, "report did not report correct profit");
        assertEq(loss, 0, "report did not report 0 loss");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(wrappedYearnV3Strategy)).profitMaxUnlockTime());

        uint256 profitUnlockedPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
        assertGt(profitUnlockedPreviewRedeem, afterPreviewRedeem, "profit locking did not work correctly");
    }

    function testFuzz_report_passWhen_noProfits(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 1_000_000_000 * 1e6); // limit deposit size to 1 Billion USDC
        // alice locks her YFI
        vm.startPrank(alice);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), ALICE_YFI);
        yearnStakingDelegate.lockYfi(ALICE_YFI);
        vm.stopPrank();

        // alice deposits into vault
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        // deposit into strategy happens
        uint256 ownedShares = depositIntoStrategy(wrappedYearnV3Strategy, alice, amount);
        addDebtToStrategy(deployedVault, mockStrategy, amount);

        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "redeemable asset should not change");

        // manager calls report
        vm.prank(tpManagement);
        (uint256 profit, uint256 loss) = wrappedYearnV3Strategy.report();

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 afterPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
        assertEq(afterTotalAssets, beforeTotalAssets, "report did not increase total assets");
        assertEq(afterPreviewRedeem, beforePreviewRedeem, "unexpected profit");
        assertEq(profit, 0, "report did not report 0 profit");
        assertEq(loss, 0, "report did not report 0 loss");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(wrappedYearnV3Strategy)).profitMaxUnlockTime());

        uint256 profitUnlockedPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
        assertEq(profitUnlockedPreviewRedeem, afterPreviewRedeem, "unexpected profit");
    }

    function testFuzz_report_passWhen_onlyUnderlyingVaultProfits(
        uint256 amount,
        uint256 underlyingVaultProfit
    )
        public
    {
        vm.assume(amount > 1e6); // Minimum deposit size is required to farm underlying vault profit
        vm.assume(amount < 1_000_000_000 * 1e6); // limit deposit size to 1 Billion USDC
        vm.assume(underlyingVaultProfit > 1e6); // Minimum profit size is required to test
        vm.assume(underlyingVaultProfit < 1_000_000_000 * 1e6); // limit profit size to 1 Billion USDC
        // alice locks her YFI
        vm.startPrank(alice);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), ALICE_YFI);
        yearnStakingDelegate.lockYfi(ALICE_YFI);
        vm.stopPrank();

        // alice deposits into vault
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        // deposit into strategy happens
        uint256 ownedShares = depositIntoStrategy(wrappedYearnV3Strategy, alice, amount);
        addDebtToStrategy(deployedVault, mockStrategy, amount);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 beforePreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
        uint256 beforePerformanceFeeRecipientOwnedShares = wrappedYearnV3Strategy.balanceOf(tpPerformanceFeeRecipient);

        // Increase underlying vault's value
        increaseMockStrategyValue(address(deployedVault), address(mockStrategy), underlyingVaultProfit);
        // warp blocks forward to yearn's strategy's profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(mockStrategy)).profitMaxUnlockTime());
        // Yearn vault process report
        reportAndProcessProfits(address(deployedVault), address(mockStrategy));
        // warp blocks forward to yearn's vault's profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(mockStrategy)).profitMaxUnlockTime());
        reportAndProcessProfits(address(deployedVault), address(mockStrategy));

        // manager calls report
        vm.prank(tpManagement);
        (uint256 profit, uint256 loss) = wrappedYearnV3Strategy.report();

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        uint256 afterPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
        uint256 afterPerformanceFeeRecipientOwnedShares = wrappedYearnV3Strategy.balanceOf(tpPerformanceFeeRecipient);
        assertGe(afterTotalAssets, beforeTotalAssets, "report did not increase total assets");
        assertEq(afterPreviewRedeem, beforePreviewRedeem, "report did not lock profit");
        assertEq(
            profit * 1e2 / (wrappedYearnV3Strategy.performanceFee()), // performance fee like 10_000 == 100%
            afterPerformanceFeeRecipientOwnedShares - beforePerformanceFeeRecipientOwnedShares,
            "correct profit not given to performance fee recipient"
        );
        assertEq(profit + beforeTotalAssets, afterTotalAssets, "report did not report correct profit");
        assertEq(loss, 0, "report did not report 0 loss");

        // warp blocks forward to our strategy's profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(mockStrategy)).profitMaxUnlockTime());

        uint256 profitUnlockedPreviewRedeem = wrappedYearnV3Strategy.previewRedeem(ownedShares);
        assertGt(profitUnlockedPreviewRedeem, afterPreviewRedeem, "redeemable asset per share increased over time");
    }

    function testFuzz_report_passWhen_relocking(uint256 amount) public {
        vm.assume(amount > 1e6); // Minimum required for farming dYFI emission
        vm.assume(amount < 1_000_000_000 * 1e6); // Maximum deposit size is 1 Billion USDC
        _setUpDYfiRewards();

        // set reward split to 50/50
        vm.prank(admin);
        yearnStakingDelegate.setRewardSplit(0, 0.5e18, 0.5e18);
        // alice locks her YFI
        vm.startPrank(alice);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), ALICE_YFI);
        yearnStakingDelegate.lockYfi(ALICE_YFI);
        vm.stopPrank();

        // alice deposits into vault
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        // deposit into strategy happens
        depositIntoStrategy(wrappedYearnV3Strategy, alice, amount);
        uint256 beforeTotalAssets = wrappedYearnV3Strategy.totalAssets();

        // warp blocks forward to accrue rewards
        vm.warp(block.timestamp + 14 days);

        // manager calls report
        vm.prank(tpManagement);
        wrappedYearnV3Strategy.report();

        uint256 afterTotalAssets = wrappedYearnV3Strategy.totalAssets();
        assertGt(afterTotalAssets, beforeTotalAssets, "report did not increase total assets");
    }
}

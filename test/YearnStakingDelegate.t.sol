// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { IStrategy } from "@tokenized-strategy/interfaces/IStrategy.sol";
import { ISnapshotDelegateRegistry } from "src/interfaces/deps/snapshot/ISnapshotDelegateRegistry.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { ICurveTwoAssetPool } from "src/interfaces/deps/curve/ICurveTwoAssetPool.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

contract YearnStakingDelegateTest is YearnV3BaseTest {
    using SafeERC20 for IERC20;

    YearnStakingDelegate public yearnStakingDelegate;
    IStrategy public mockStrategy;
    address public testVault;
    address public testGauge;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 10e18;

    // Addresses
    address public alice;
    address public manager;
    address public wrappedStrategy;
    address public treasury;

    CurveRouterSwapper.CurveSwapParams internal _routerParams;

    function setUp() public override {
        super.setUp();

        // create alice who will be lock YFI via the yearnStakingDelegate
        alice = createUser("alice");
        // create manager of the yearnStakingDelegate
        manager = createUser("manager");
        // create an address that will act as a wrapped strategy
        wrappedStrategy = createUser("wrappedStrategy");
        // create an address that will act as a treasury
        treasury = createUser("treasury");

        // Deploy vault
        testVault = deployVaultV3("USDC Test Vault", MAINNET_USDC, new address[](0));
        // Deploy gauge
        testGauge = deployGaugeViaFactory(testVault, admin, "USDC Test Vault Gauge");

        // Give alice some YFI
        airdrop(ERC20(MAINNET_YFI), alice, ALICE_YFI);

        // Give admin some dYFI
        airdrop(ERC20(MAINNET_DYFI), admin, DYFI_REWARD_AMOUNT);

        // Start new rewards
        vm.startPrank(admin);
        IERC20(MAINNET_DYFI).approve(testGauge, DYFI_REWARD_AMOUNT);
        IGauge(testGauge).queueNewRewards(DYFI_REWARD_AMOUNT);
        vm.stopPrank();

        require(IERC20(MAINNET_DYFI).balanceOf(testGauge) == DYFI_REWARD_AMOUNT, "queueNewRewards failed");

        yearnStakingDelegate = new YearnStakingDelegate(
            MAINNET_YFI,
            MAINNET_DYFI,
            MAINNET_VE_YFI,
            MAINNET_SNAPSHOT_DELEGATE_REGISTRY,
            MAINNET_CURVE_ROUTER,
            treasury,
            admin,
            manager
        );
    }

    function testFuzz_constructor(address noAdminRole, address noManagerRole) public {
        vm.assume(noAdminRole != admin);
        // manager role is given to admin and manager
        vm.assume(noManagerRole != manager && noManagerRole != admin);
        // Check for storage variables default values
        assertEq(yearnStakingDelegate.yfi(), MAINNET_YFI);
        assertEq(yearnStakingDelegate.dYfi(), MAINNET_DYFI);
        assertEq(yearnStakingDelegate.veYfi(), MAINNET_VE_YFI);
        assertTrue(yearnStakingDelegate.shouldPerpetuallyLock());
        (uint80 treasurySplit, uint80 strategySplit, uint80 veYfiSplit) = yearnStakingDelegate.rewardSplit();
        assertEq(treasurySplit, 0);
        assertEq(strategySplit, 1e18);
        assertEq(veYfiSplit, 0);
        // Check for roles
        assertTrue(yearnStakingDelegate.hasRole(yearnStakingDelegate.MANAGER_ROLE(), manager));
        assertTrue(!yearnStakingDelegate.hasRole(yearnStakingDelegate.MANAGER_ROLE(), noManagerRole));
        assertTrue(yearnStakingDelegate.hasRole(yearnStakingDelegate.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(!yearnStakingDelegate.hasRole(yearnStakingDelegate.DEFAULT_ADMIN_ROLE(), noAdminRole));
        // Check for approvals
        assertEq(IERC20(MAINNET_YFI).allowance(address(yearnStakingDelegate), MAINNET_VE_YFI), type(uint256).max);
    }

    function _setAssociatedGauge() internal {
        vm.prank(manager);
        yearnStakingDelegate.setAssociatedGauge(testVault, testGauge);
    }

    function _setRewardSplit(uint80 treasurySplit, uint80 strategySplit, uint80 veYfiSplit) internal {
        vm.prank(admin);
        yearnStakingDelegate.setRewardSplit(treasurySplit, strategySplit, veYfiSplit);
    }

    function _setRouterParams() internal {
        _routerParams.route[0] = MAINNET_DYFI;
        _routerParams.route[1] = MAINNET_DYFI_ETH_POOL;
        _routerParams.route[2] = MAINNET_ETH;
        _routerParams.route[3] = MAINNET_YFI_ETH_POOL;
        _routerParams.route[4] = MAINNET_YFI;

        _routerParams.swapParams[0] = [uint256(0), 1, 1, 2, 2];
        _routerParams.swapParams[1] = [uint256(0), 1, 1, 2, 2];

        vm.prank(admin);
        yearnStakingDelegate.setRouterParams(_routerParams);
    }

    function test_setAssociatedGauge() public {
        _setAssociatedGauge();
        require(yearnStakingDelegate.associatedGauge(testVault) == testGauge, "setAssociatedGauge failed");
    }

    function _lockYFI(address user, uint256 amount) internal {
        vm.startPrank(user);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), amount);
        yearnStakingDelegate.lockYfi(amount);
        vm.stopPrank();
    }

    function test_lockYFI() public {
        _lockYFI(alice, 1e18);

        assertEq(IERC20(MAINNET_YFI).balanceOf(address(yearnStakingDelegate)), 0, "lock failed");
        assertEq(
            IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), 999_999_999_971_481_600, "lock failed"
        );
    }

    function test_lockYFI_revertWhen_WithZeroAmount() public {
        uint256 lockAmount = 0;
        vm.startPrank(alice);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), lockAmount);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        yearnStakingDelegate.lockYfi(lockAmount);
        vm.stopPrank();
    }

    function test_lockYFI_revertWhen_PerpetualLockDisabled() public {
        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        uint256 lockAmount = 1e18;
        vm.startPrank(alice);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), lockAmount);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockDisabled.selector));
        yearnStakingDelegate.lockYfi(lockAmount);
        vm.stopPrank();
    }

    function testFuzz_lockYFI_revertWhen_CreatingLockWithLessThanMinAmount(uint256 lockAmount) public {
        vm.assume(lockAmount > 0);
        vm.assume(lockAmount < 1e18);
        vm.startPrank(alice);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), lockAmount);
        vm.expectRevert();
        yearnStakingDelegate.lockYfi(lockAmount);
        vm.stopPrank();
    }

    function testFuzz_lockYFI(uint256 lockAmount) public {
        vm.assume(lockAmount >= 1e18);
        vm.assume(lockAmount < IERC20(MAINNET_YFI).balanceOf(alice));
        _lockYFI(alice, lockAmount);

        assertEq(IERC20(MAINNET_YFI).balanceOf(address(yearnStakingDelegate)), 0, "lock failed");
        assertGt(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), lockAmount - 1e9, "lock failed");
        assertLe(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), lockAmount, "lock failed");
    }

    function test_earlyUnlock() public {
        _lockYFI(alice, 1e18);

        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(admin);
        vm.stopPrank();

        assertEq(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
    }

    function testFuzz_earlyUnlock(uint256 lockAmount) public {
        vm.assume(lockAmount >= 1e18);
        vm.assume(lockAmount < IERC20(MAINNET_YFI).balanceOf(alice));
        _lockYFI(alice, lockAmount);

        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(admin);
        vm.stopPrank();

        assertEq(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
    }

    function test_earlyUnlock_revertWhen_PerpeutalLockEnabled() public {
        _lockYFI(alice, 1e18);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockEnabled.selector));
        yearnStakingDelegate.earlyUnlock(admin);
    }

    function _deposit(address addr, uint256 amount) internal {
        vm.startPrank(addr);
        IERC20(testVault).approve(address(yearnStakingDelegate), amount);
        yearnStakingDelegate.depositToGauge(testVault, amount);
        vm.stopPrank();
    }

    function testFuzz_depositToGauge(uint256 vaultBalance) public {
        vm.assume(vaultBalance > 0);
        _setAssociatedGauge();

        airdrop(ERC20(testVault), wrappedStrategy, vaultBalance);
        _deposit(wrappedStrategy, vaultBalance);

        // Check the yearn staking delegate has received the gauge tokens
        assertEq(IERC20(testGauge).balanceOf(address(yearnStakingDelegate)), vaultBalance, "depositToGauge failed");
        // Check the gauge has received the vault tokens
        assertEq(IERC20(testVault).balanceOf(testGauge), vaultBalance, "depositToGauge failed");
    }

    function testFuzz_depositToGauge_revertWhen_NoAssociatedGauge(uint256 vaultBalance) public {
        vm.assume(vaultBalance > 0);

        airdrop(ERC20(testVault), wrappedStrategy, vaultBalance);

        vm.startPrank(wrappedStrategy);
        IERC20(testVault).approve(address(yearnStakingDelegate), vaultBalance);
        vm.expectRevert(abi.encodeWithSelector(Errors.NoAssociatedGauge.selector));
        yearnStakingDelegate.depositToGauge(testVault, vaultBalance);
        vm.stopPrank();
    }

    function testFuzz_withdrawFromGauge(uint256 vaultBalance) public {
        vm.assume(vaultBalance > 0);
        _setAssociatedGauge();

        airdrop(ERC20(testVault), wrappedStrategy, vaultBalance);
        _deposit(wrappedStrategy, vaultBalance);

        // Start withdraw process
        vm.startPrank(wrappedStrategy);
        yearnStakingDelegate.withdrawFromGauge(testVault, vaultBalance);
        vm.stopPrank();

        // Check the yearn staking delegate has released the gauge tokens
        assertEq(IERC20(testGauge).balanceOf(address(yearnStakingDelegate)), 0, "withdrawFromGauge failed");
        // Check the gauge has released the vault tokens
        assertEq(IERC20(testVault).balanceOf(testGauge), 0, "withdrawFromGauge failed");
        // Check that wrappedStrategy has received the vault tokens
        assertEq(IERC20(testVault).balanceOf(wrappedStrategy), vaultBalance, "withdrawFromGauge failed");
    }

    function test_harvest_revertWhen_NoAssociatedGauge() public {
        vm.startPrank(wrappedStrategy);
        vm.expectRevert(abi.encodeWithSelector(Errors.NoAssociatedGauge.selector));
        yearnStakingDelegate.harvest(testVault);
        vm.stopPrank();
    }

    function test_harvest_passWhen_NoVeYFI() public {
        _setAssociatedGauge();
        airdrop(ERC20(testVault), wrappedStrategy, 1e18);
        _deposit(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        uint256 rewardAmount = yearnStakingDelegate.harvest(testVault);

        // Check that the vault has received the rewards
        // expect to be close to 10% of the rewards, giving 90% as the penalty
        assertEq(rewardAmount, IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy), "harvest did not return correct value");
        assertLe(
            IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy),
            DYFI_REWARD_AMOUNT / 10,
            "harvested reward amount is incorrect"
        );
        assertApproxEqRel(
            IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy),
            DYFI_REWARD_AMOUNT / 10,
            0.01e18,
            "harvested reward amount is incorrect"
        );
    }

    function test_harvest_passWhen_SomeVeYFI() public {
        _setAssociatedGauge();
        _lockYFI(alice, 1e18);
        airdrop(ERC20(testVault), wrappedStrategy, 1e18);
        _deposit(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        uint256 rewardAmount = yearnStakingDelegate.harvest(testVault);

        // Check that the vault has received the rewards
        // expect to be higher than 10% of the rewards due to the 1 YFI locked
        assertEq(rewardAmount, IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy), "harvest did not return correct value");
        assertGt(
            IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy),
            DYFI_REWARD_AMOUNT / 10,
            "harvested reward amount is incorrect"
        );
        assertApproxEqRel(
            IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy),
            DYFI_REWARD_AMOUNT / 10,
            0.05e18,
            "harvested reward amount is incorrect"
        );
    }

    function test_harvest_passWhen_LargeVeYFI() public {
        _setAssociatedGauge();
        _lockYFI(alice, ALICE_YFI);
        airdrop(ERC20(testVault), wrappedStrategy, 1e18);
        _deposit(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        uint256 rewardAmount = yearnStakingDelegate.harvest(testVault);

        // Check that the vault has received the rewards
        // expect to be close to 100% of the rewards
        assertEq(rewardAmount, IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy), "harvest did not return correct value");
        assertApproxEqRel(
            IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy), DYFI_REWARD_AMOUNT, 0.01e18, "harvest failed"
        );
    }

    function test_harvest_passWhen_WithVeYfiSplit() public {
        _setAssociatedGauge();
        _lockYFI(alice, 1e18);
        _setRewardSplit(0.3e18, 0.3e18, 0.4e18);
        _setRouterParams();
        airdrop(ERC20(testVault), wrappedStrategy, 1e18);
        _deposit(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Reward amount is slightly higher than 1e18 due to Alice locking 1e18 YFI as veYFI.
        uint256 actualRewardAmount = 1_016_092_352_451_786_806;

        // Calculate split amounts strategy split amount
        uint256 estimatedStrategySplit = actualRewardAmount * 0.3e18 / 1e18;
        uint256 estimatedTreasurySplit = actualRewardAmount * 0.3e18 / 1e18;
        uint256 estimatedVeYfiSplit = actualRewardAmount * 0.4e18 / 1e18;

        // Harvest
        vm.prank(wrappedStrategy);
        uint256 rewardAmount = yearnStakingDelegate.harvest(testVault);

        uint256 strategyDYfiBalance = IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy);
        assertEq(rewardAmount, strategyDYfiBalance, "harvest did not return correct value");
        assertEq(strategyDYfiBalance, estimatedStrategySplit, "strategy split is incorrect");

        uint256 treasuryBalance = IERC20(MAINNET_DYFI).balanceOf(treasury);
        assertEq(treasuryBalance, estimatedTreasurySplit, "treausry split is incorrect");

        assertEq(yearnStakingDelegate.dYfiToSwapAndLock(), estimatedVeYfiSplit, "dYfiToSwapAndLock is incorrect");
    }

    function test_swapDYfiToVeYfi() public {
        _setAssociatedGauge();
        _lockYFI(alice, 1e18);
        _setRewardSplit(0.3e18, 0.3e18, 0.4e18);
        _setRouterParams();
        airdrop(ERC20(testVault), wrappedStrategy, 1e18);
        _deposit(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        yearnStakingDelegate.harvest(testVault);

        // Calculate expected yfi amount after swapping through curve pools
        // dYFI -> WETH then WETH -> YFI
        uint256 wethAmount =
            ICurveTwoAssetPool(MAINNET_DYFI_ETH_POOL).get_dy(0, 1, yearnStakingDelegate.dYfiToSwapAndLock());
        uint256 yfiAmount = ICurveTwoAssetPool(MAINNET_YFI_ETH_POOL).get_dy(0, 1, wethAmount);

        vm.prank(manager);
        yearnStakingDelegate.swapDYfiToVeYfi();

        // Check for the new veYfi balance
        IVotingYFI.LockedBalance memory lockedBalance = IVotingYFI(MAINNET_VE_YFI).locked(address(yearnStakingDelegate));
        assertApproxEqRel(
            lockedBalance.amount, 1e18 + yfiAmount, 0.001e18, "swapDYfiToVeYfi failed: locked amount is incorrect"
        );
        assertApproxEqRel(
            lockedBalance.end,
            block.timestamp + 4 * 365 days + 4 weeks,
            0.001e18,
            "swapDYfiToVeYfi failed: locked end timestamp is incorrect"
        );
    }

    function test_swapDYfiToVeYfi_revertWhen_NoDYfiToSwap() public {
        _setAssociatedGauge();
        _lockYFI(alice, 1e18);
        _setRouterParams();
        airdrop(ERC20(testVault), wrappedStrategy, 1e18);
        _deposit(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest but no split is set for veYfi portion
        vm.prank(wrappedStrategy);
        yearnStakingDelegate.harvest(testVault);

        vm.expectRevert(abi.encodeWithSelector(Errors.NoDYfiToSwap.selector));
        vm.prank(manager);
        yearnStakingDelegate.swapDYfiToVeYfi();
    }

    function test_swapDYfiToVeYfi_revertWhen_PerpetualLockDisabled() public {
        _setAssociatedGauge();
        _lockYFI(alice, 1e18);
        _setRewardSplit(0.3e18, 0.3e18, 0.4e18);
        _setRouterParams();
        airdrop(ERC20(testVault), wrappedStrategy, 1e18);
        _deposit(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        yearnStakingDelegate.harvest(testVault);

        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockDisabled.selector));
        yearnStakingDelegate.swapDYfiToVeYfi();
        vm.stopPrank();
    }

    function test_setSnapshotDelegate() public {
        vm.startPrank(manager);
        yearnStakingDelegate.setSnapshotDelegate("veyfi.eth", manager);
        vm.stopPrank();

        assertEq(
            ISnapshotDelegateRegistry(MAINNET_SNAPSHOT_DELEGATE_REGISTRY).delegation(
                address(yearnStakingDelegate), "veyfi.eth"
            ),
            manager,
            "setSnapshotDelegate failed"
        );
    }

    function test_setSnapshotDelegate_revertWhen_ZeroAddress() public {
        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        yearnStakingDelegate.setSnapshotDelegate("veyfi.eth", address(0));
        vm.stopPrank();
    }

    function testFuzz_setTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0));
        vm.startPrank(admin);
        yearnStakingDelegate.setTreasury(newTreasury);
        vm.stopPrank();

        assertEq(yearnStakingDelegate.treasury(), newTreasury, "setTreasury failed");
    }

    function test_setTreasury_revertWhen_ZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        yearnStakingDelegate.setTreasury(address(0));
        vm.stopPrank();
    }

    function testFuzz_setRewardSplit(uint80 a, uint80 b) public {
        // Workaround for vm.assume max tries
        vm.assume(uint256(a) + b <= 1e18);
        uint80 c = 1e18 - a - b;
        vm.prank(admin);
        yearnStakingDelegate.setRewardSplit(a, b, c);
        (uint80 treasurySplit, uint80 strategySplit, uint80 lockSplit) = yearnStakingDelegate.rewardSplit();
        assertEq(treasurySplit, a, "setRewardSplit failed, treasury split is incorrect");
        assertEq(strategySplit, b, "setRewardSplit failed, strategy split is incorrect");
        assertEq(lockSplit, c, "setRewardSplit failed, lock split is incorrect");
    }

    function testFuzz_setRewardSplit_revertWhen_InvalidRewardSplit(uint80 a, uint80 b, uint80 c) public {
        vm.assume(uint256(a) + b + c != 1e18);
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardSplit.selector));
        yearnStakingDelegate.setRewardSplit(a, b, c);
        vm.stopPrank();
    }

    function test_setRouterParams_revertWhen_EmptyPaths() public {
        vm.prank(admin);
        CurveRouterSwapper.CurveSwapParams memory params;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFromToken.selector, MAINNET_DYFI, address(0)));
        yearnStakingDelegate.setRouterParams(params);
    }

    function test_setRouterParams_revertWhen_InvalidFromToken() public {
        vm.prank(admin);
        CurveRouterSwapper.CurveSwapParams memory params;
        // Set from token to be USDC instead of dYFI
        params.route[0] = MAINNET_USDC;
        params.route[1] = MAINNET_TRI_CRYPTO_USDC;
        params.route[2] = MAINNET_ETH;
        params.route[3] = MAINNET_YFI_ETH_POOL;
        params.route[4] = MAINNET_YFI;

        params.swapParams[0] = [uint256(0), 2, 1, 2, 2];
        params.swapParams[1] = [uint256(0), 1, 1, 2, 2];
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFromToken.selector, MAINNET_DYFI, MAINNET_USDC));
        yearnStakingDelegate.setRouterParams(params);
    }

    function test_setRouterParams_revertWhen_InvalidToToken() public {
        vm.prank(admin);
        CurveRouterSwapper.CurveSwapParams memory params;
        params.route[0] = MAINNET_DYFI;
        params.route[1] = MAINNET_DYFI_ETH_POOL;
        params.route[2] = MAINNET_ETH;
        params.route[3] = MAINNET_TRI_CRYPTO_USDC;
        params.route[4] = MAINNET_USDC;

        params.swapParams[0] = [uint256(0), 1, 1, 2, 2];
        params.swapParams[1] = [uint256(2), 0, 1, 2, 2];
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidToToken.selector, MAINNET_YFI, MAINNET_USDC));
        yearnStakingDelegate.setRouterParams(params);
    }

    function test_setRouterParams_revertWhen_InvalidCoinIndex() public {
        vm.prank(admin);
        CurveRouterSwapper.CurveSwapParams memory params;
        // Set route to include a token address that does not exist in the given pools
        params.route[0] = MAINNET_DYFI;
        params.route[1] = MAINNET_DYFI_ETH_POOL;
        params.route[2] = MAINNET_USDC;
        params.route[3] = MAINNET_YFI_ETH_POOL;
        params.route[4] = MAINNET_YFI;

        params.swapParams[0] = [uint256(0), 1, 1, 2, 2];
        params.swapParams[1] = [uint256(0), 1, 1, 2, 2];
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidCoinIndex.selector));
        yearnStakingDelegate.setRouterParams(params);
    }
}

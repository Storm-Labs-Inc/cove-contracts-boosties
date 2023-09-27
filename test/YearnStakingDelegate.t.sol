// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "src/interfaces/yearn/tokenized-strategy/IStrategy.sol";
import { IVault } from "src/interfaces/yearn/yearn-vaults-v3/IVault.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { ISnapshotDelegateRegistry } from "src/interfaces/ISnapshotDelegateRegistry.sol";
import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { IERC20, SafeERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/yearn/veYFI/IVotingYFI.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IGaugeFactory } from "src/interfaces/yearn/veYFI/IGaugeFactory.sol";
import { IGauge } from "src/interfaces/yearn/veYFI/IGauge.sol";
import { ICurveTwoAssetPool } from "src/interfaces/curve/ICurveTwoAssetPool.sol";

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
        testVault = deployVaultV3("USDC Test Vault", USDC, new address[](0));
        // Deploy gauge
        testGauge = deployGaugeViaFactory(testVault, admin, "USDC Test Vault Gauge");

        // Give alice some YFI
        airdrop(ERC20(ETH_YFI), alice, ALICE_YFI);

        // Give admin some dYFI
        airdrop(ERC20(dYFI), admin, DYFI_REWARD_AMOUNT);

        // Start new rewards
        vm.startPrank(admin);
        IERC20(dYFI).approve(testGauge, DYFI_REWARD_AMOUNT);
        IGauge(testGauge).queueNewRewards(DYFI_REWARD_AMOUNT);
        vm.stopPrank();

        require(IERC20(dYFI).balanceOf(testGauge) == DYFI_REWARD_AMOUNT, "queueNewRewards failed");

        yearnStakingDelegate = new YearnStakingDelegate(ETH_YFI, dYFI, ETH_VE_YFI, treasury, admin, manager);
    }

    function testFuzz_constructor(address noAdminRole, address noManagerRole) public {
        vm.assume(noAdminRole != admin);
        // manager role is given to admin and manager
        vm.assume(noManagerRole != manager && noManagerRole != admin);
        // Check for storage variables default values
        assertEq(yearnStakingDelegate.yfi(), ETH_YFI);
        assertEq(yearnStakingDelegate.dYfi(), dYFI);
        assertEq(yearnStakingDelegate.veYfi(), ETH_VE_YFI);
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
        assertEq(IERC20(ETH_YFI).allowance(address(yearnStakingDelegate), ETH_VE_YFI), type(uint256).max);
    }

    function _setAssociatedGauge() internal {
        vm.prank(manager);
        yearnStakingDelegate.setAssociatedGauge(testVault, testGauge);
    }

    function _setRewardSplit(uint80 treasurySplit, uint80 strategySplit, uint80 veYfiSplit) internal {
        vm.prank(admin);
        yearnStakingDelegate.setRewardSplit(treasurySplit, strategySplit, veYfiSplit);
    }

    function _setSwapPaths() internal {
        YearnStakingDelegate.SwapPath[] memory swapPaths = new YearnStakingDelegate.SwapPath[](2);
        swapPaths[0] = YearnStakingDelegate.SwapPath(dYfiEthCurvePool, dYFI, WETH);
        swapPaths[1] = YearnStakingDelegate.SwapPath(yfiEthCurvePool, WETH, ETH_YFI);
        vm.prank(admin);
        yearnStakingDelegate.setSwapPaths(swapPaths);
    }

    function test_setAssociatedGauge() public {
        _setAssociatedGauge();
        require(yearnStakingDelegate.associatedGauge(testVault) == testGauge, "setAssociatedGauge failed");
    }

    function _lockYFI(address user, uint256 amount) internal {
        vm.startPrank(user);
        IERC20(ETH_YFI).approve(address(yearnStakingDelegate), amount);
        yearnStakingDelegate.lockYfi(amount);
        vm.stopPrank();
    }

    function test_lockYFI() public {
        _lockYFI(alice, 1e18);

        assertEq(IERC20(ETH_YFI).balanceOf(address(yearnStakingDelegate)), 0, "lock failed");
        assertEq(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)), 999_999_999_971_481_600, "lock failed");
    }

    function test_lockYFI_revertsWithZeroAmount() public {
        uint256 lockAmount = 0;
        vm.startPrank(alice);
        IERC20(ETH_YFI).approve(address(yearnStakingDelegate), lockAmount);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        yearnStakingDelegate.lockYfi(lockAmount);
        vm.stopPrank();
    }

    function testFuzz_lockYFI_revertsWhenCreatingLockWithLessThanMinAmount(uint256 lockAmount) public {
        vm.assume(lockAmount > 0);
        vm.assume(lockAmount < 1e18);
        vm.startPrank(alice);
        IERC20(ETH_YFI).approve(address(yearnStakingDelegate), lockAmount);
        vm.expectRevert();
        yearnStakingDelegate.lockYfi(lockAmount);
        vm.stopPrank();
    }

    function testFuzz_lockYFI(uint256 lockAmount) public {
        vm.assume(lockAmount >= 1e18);
        vm.assume(lockAmount < IERC20(ETH_YFI).balanceOf(alice));
        _lockYFI(alice, lockAmount);

        assertEq(IERC20(ETH_YFI).balanceOf(address(yearnStakingDelegate)), 0, "lock failed");
        assertGt(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)), lockAmount - 1e9, "lock failed");
        assertLe(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)), lockAmount, "lock failed");
    }

    function test_earlyUnlock() public {
        _lockYFI(alice, 1e18);

        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(admin);
        vm.stopPrank();

        assertEq(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
    }

    function testFuzz_earlyUnlock(uint256 lockAmount) public {
        vm.assume(lockAmount >= 1e18);
        vm.assume(lockAmount < IERC20(ETH_YFI).balanceOf(alice));
        _lockYFI(alice, lockAmount);

        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(admin);
        vm.stopPrank();

        assertEq(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
    }

    function test_earlyUnlock_revertsPerpeutalLockEnabled() public {
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

    function testFuzz_depositToGauge_revertsWhenNoAssociatedGauge(uint256 vaultBalance) public {
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

    function test_harvest_revertsWithNoAssociatedGauge() public {
        vm.startPrank(wrappedStrategy);
        vm.expectRevert(abi.encodeWithSelector(Errors.NoAssociatedGauge.selector));
        yearnStakingDelegate.harvest(testVault);
        vm.stopPrank();
    }

    function test_harvest_withNoVeYFI() public {
        _setAssociatedGauge();
        airdrop(ERC20(testVault), wrappedStrategy, 1e18);
        _deposit(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        yearnStakingDelegate.harvest(testVault);

        // Check that the vault has received the rewards
        // expect to be close to 10% of the rewards, giving 90% as the penalty
        assertLe(IERC20(dYFI).balanceOf(wrappedStrategy), DYFI_REWARD_AMOUNT / 10, "harvest failed");
        assertApproxEqRel(IERC20(dYFI).balanceOf(wrappedStrategy), DYFI_REWARD_AMOUNT / 10, 0.01e18, "harvest failed");
    }

    function test_harvest_withSomeYFI() public {
        _setAssociatedGauge();
        _lockYFI(alice, 1e18);
        airdrop(ERC20(testVault), wrappedStrategy, 1e18);
        _deposit(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        yearnStakingDelegate.harvest(testVault);

        // Check that the vault has received the rewards
        // expect to be higher than 10% of the rewards due to the 1 YFI locked
        assertGt(IERC20(dYFI).balanceOf(wrappedStrategy), DYFI_REWARD_AMOUNT / 10, "harvest failed");
        assertApproxEqRel(IERC20(dYFI).balanceOf(wrappedStrategy), DYFI_REWARD_AMOUNT / 10, 0.05e18, "harvest failed");
    }

    function test_harvest_withLargeYFI() public {
        _setAssociatedGauge();
        _lockYFI(alice, ALICE_YFI);
        airdrop(ERC20(testVault), wrappedStrategy, 1e18);
        _deposit(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        yearnStakingDelegate.harvest(testVault);

        // Check that the vault has received the rewards
        // expect to be close to 100% of the rewards
        assertApproxEqRel(IERC20(dYFI).balanceOf(wrappedStrategy), DYFI_REWARD_AMOUNT, 0.01e18, "harvest failed");
    }

    function test_harvest_swapAndLock_With1veYfi() public {
        _setAssociatedGauge();
        _lockYFI(alice, 1e18);
        _setRewardSplit(0.3e18, 0.3e18, 0.4e18);
        _setSwapPaths();
        airdrop(ERC20(testVault), wrappedStrategy, 1e18);
        _deposit(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Measure veYfi balance before harvest
        IVotingYFI.LockedBalance memory lockedBalanceBefore =
            IVotingYFI(ETH_VE_YFI).locked(address(yearnStakingDelegate));

        // Reward amount is slightly higher than 1e18 due to Alice locking 1e18 YFI as veYFI.
        uint256 actualRewardAmount = 1_021_755_338_445_599_531;

        // Calculate split amounts strategy split amount
        uint256 estimatedStrategySplit = actualRewardAmount * 0.3e18 / 1e18;
        uint256 estimatedTreasurySplit = actualRewardAmount * 0.3e18 / 1e18;
        uint256 estimatedVeYfiSplit = actualRewardAmount * 0.4e18 / 1e18;

        // Calculate expected yfi amount after swapping through curve pools
        // dYFI -> WETH then WETH -> YFI
        uint256 wethAmount = ICurveTwoAssetPool(dYfiEthCurvePool).get_dy(1, 0, estimatedVeYfiSplit);
        uint256 yfiAmount = ICurveTwoAssetPool(yfiEthCurvePool).get_dy(0, 1, wethAmount);

        // Harvest
        vm.prank(wrappedStrategy);
        yearnStakingDelegate.harvest(testVault);

        uint256 strategyDYfiBalance = IERC20(dYFI).balanceOf(wrappedStrategy);
        assertEq(strategyDYfiBalance, estimatedStrategySplit, "strategy split is incorrect");

        uint256 treasuryBalance = IERC20(dYFI).balanceOf(treasury);
        assertEq(treasuryBalance, estimatedTreasurySplit, "treausry split is incorrect");

        IVotingYFI.LockedBalance memory lockedBalanceAfter =
            IVotingYFI(ETH_VE_YFI).locked(address(yearnStakingDelegate));
        assertEq(
            uint256(uint128(lockedBalanceAfter.amount - lockedBalanceBefore.amount)),
            yfiAmount,
            "veYfi split is incorrect"
        );
    }

    function test_setSnapshotDelegate() public {
        vm.startPrank(manager);
        yearnStakingDelegate.setSnapshotDelegate("veyfi.eth", manager);
        vm.stopPrank();

        assertEq(
            ISnapshotDelegateRegistry(yearnStakingDelegate.SNAPSHOT_DELEGATE_REGISTRY()).delegation(
                address(yearnStakingDelegate), "veyfi.eth"
            ),
            manager,
            "setSnapshotDelegate failed"
        );
    }

    function test_setSnapshotDelegate_revertsWithZeroAddress() public {
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

    function test_setTreasury_revertsWhenZeroAddress() public {
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
    }

    function testFuzz_setRewardSplit_revertsWhenNotEqualOne(uint80 a, uint80 b, uint80 c) public {
        vm.assume(uint256(a) + b + c != 1e18);
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardSplit.selector));
        yearnStakingDelegate.setRewardSplit(a, b, c);
        vm.stopPrank();
    }
}

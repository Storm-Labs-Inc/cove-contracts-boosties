// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "test/utils/YearnV3BaseTest.t.sol";
import { ISnapshotDelegateRegistry } from "src/interfaces/deps/snapshot/ISnapshotDelegateRegistry.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract YearnStakingDelegate_ForkedTest is YearnV3BaseTest {
    using SafeERC20 for IERC20;

    YearnStakingDelegate public yearnStakingDelegate;
    address public gauge;
    address public vault;
    address public stakingDelegateRewards;
    address public swapAndLock;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 10e18;
    uint256 public constant YFI_MAX_SUPPLY = 36_666e18;

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

        vault = MAINNET_WETH_YETH_POOL_VAULT;

        gauge = MAINNET_WETH_YETH_POOL_GAUGE;

        // Give admin some dYFI
        airdrop(ERC20(MAINNET_DYFI), admin, DYFI_REWARD_AMOUNT);

        address receiver = setUpGaugeRewardReceiverImplementation(admin);
        yearnStakingDelegate = new YearnStakingDelegate(receiver, treasury, admin, manager);
        stakingDelegateRewards = setUpStakingDelegateRewards(admin, MAINNET_DYFI, address(yearnStakingDelegate));
        swapAndLock = setUpSwapAndLock(admin, MAINNET_CURVE_ROUTER, address(yearnStakingDelegate));

        // Setup approvals for YFI spending
        vm.startPrank(alice);
        IERC20(MAINNET_YFI).approve(MAINNET_VE_YFI, type(uint256).max);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), type(uint256).max);
        vm.stopPrank();
    }

    // Need a special function to airdrop to the gauge since it relies on totalSupply for calculation
    function _airdropGaugeTokens(address user, uint256 amount) internal {
        airdrop(ERC20(vault), user, amount);
        vm.startPrank(user);
        IERC20(vault).approve(address(gauge), amount);
        IGauge(gauge).deposit(amount, user);
        vm.stopPrank();
    }

    function _setGaugeRewards() internal {
        vm.prank(admin);
        yearnStakingDelegate.addGaugeRewards(gauge, stakingDelegateRewards);
    }

    function _setSwapAndLock() internal {
        vm.prank(admin);
        yearnStakingDelegate.setSwapAndLock(swapAndLock);
    }

    function _setRewardSplit(address gauge_, uint80 treasurySplit, uint80 strategySplit, uint80 veYfiSplit) internal {
        vm.prank(admin);
        yearnStakingDelegate.setRewardSplit(gauge_, treasurySplit, strategySplit, veYfiSplit);
    }

    function _lockYfiForYSD(uint256 amount) internal {
        airdrop(ERC20(MAINNET_YFI), alice, amount);
        vm.prank(alice);
        yearnStakingDelegate.lockYfi(amount);
    }

    function _lockYfiForUser(address user, uint256 amount, uint256 duration) internal {
        airdrop(ERC20(MAINNET_YFI), user, amount);
        vm.startPrank(user);
        IERC20(MAINNET_YFI).approve(MAINNET_VE_YFI, amount);
        IVotingYFI(MAINNET_VE_YFI).modify_lock(amount, block.timestamp + duration, address(user));
        vm.stopPrank();
    }

    function _depositGaugeTokensToYSD(address from, uint256 amount) internal {
        _airdropGaugeTokens(from, amount);
        vm.startPrank(from);
        IERC20(gauge).approve(address(yearnStakingDelegate), amount);
        yearnStakingDelegate.deposit(gauge, amount);
        vm.stopPrank();
    }

    function testFuzz_constructor(address noAdminRole, address noManagerRole, address anyGauge) public {
        vm.assume(noAdminRole != admin);
        // manager role is given to admin and manager
        vm.assume(noManagerRole != manager && noManagerRole != admin);
        // Check for storage variables default values
        assertEq(yearnStakingDelegate.yfi(), MAINNET_YFI);
        assertEq(yearnStakingDelegate.dYfi(), MAINNET_DYFI);
        assertEq(yearnStakingDelegate.veYfi(), MAINNET_VE_YFI);
        assertTrue(yearnStakingDelegate.shouldPerpetuallyLock());
        (uint80 treasurySplit, uint80 strategySplit, uint80 veYfiSplit) =
            yearnStakingDelegate.gaugeRewardSplit(anyGauge);
        assertEq(treasurySplit, 0);
        assertEq(strategySplit, 0);
        assertEq(veYfiSplit, 0);
        // Check for roles
        assertTrue(yearnStakingDelegate.hasRole(yearnStakingDelegate.MANAGER_ROLE(), manager));
        assertTrue(!yearnStakingDelegate.hasRole(yearnStakingDelegate.MANAGER_ROLE(), noManagerRole));
        assertTrue(yearnStakingDelegate.hasRole(yearnStakingDelegate.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(!yearnStakingDelegate.hasRole(yearnStakingDelegate.DEFAULT_ADMIN_ROLE(), noAdminRole));
        // Check for approvals
        assertEq(IERC20(MAINNET_YFI).allowance(address(yearnStakingDelegate), MAINNET_VE_YFI), type(uint256).max);
    }

    function test_lockYFI() public {
        _lockYfiForYSD(1e18);
        assertEq(IERC20(MAINNET_YFI).balanceOf(address(yearnStakingDelegate)), 0, "lock failed");
        assertEq(
            IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), 999_999_999_971_481_600, "lock failed"
        );
    }

    function test_lockYFI_revertWhen_WithZeroAmount() public {
        uint256 lockAmount = 0;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        vm.prank(alice);
        yearnStakingDelegate.lockYfi(lockAmount);
    }

    function test_lockYFI_revertWhen_PerpetualLockDisabled() public {
        vm.prank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        uint256 lockAmount = 1e18;
        airdrop(ERC20(MAINNET_YFI), alice, lockAmount);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockDisabled.selector));
        yearnStakingDelegate.lockYfi(lockAmount);
    }

    function testFuzz_lockYFI_revertWhen_CreatingLockWithLessThanMinAmount(uint256 lockAmount) public {
        vm.assume(lockAmount > 0);
        vm.assume(lockAmount < 1e18);
        airdrop(ERC20(MAINNET_YFI), alice, lockAmount);
        vm.prank(alice);
        vm.expectRevert();
        yearnStakingDelegate.lockYfi(lockAmount);
    }

    function testFuzz_lockYFI(uint256 lockAmount) public {
        vm.assume(lockAmount >= 1e18);
        vm.assume(lockAmount <= YFI_MAX_SUPPLY);
        _lockYfiForYSD(lockAmount);

        assertEq(IERC20(MAINNET_YFI).balanceOf(address(yearnStakingDelegate)), 0, "lock failed");
        assertGt(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), lockAmount - 1e9, "lock failed");
        assertLe(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), lockAmount, "lock failed");
    }

    function test_earlyUnlock() public {
        _lockYfiForYSD(1e18);

        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(admin);
        vm.stopPrank();

        assertEq(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
    }

    function testFuzz_earlyUnlock(uint256 lockAmount) public {
        vm.assume(lockAmount >= 1e18);
        vm.assume(lockAmount <= YFI_MAX_SUPPLY);
        _lockYfiForYSD(lockAmount);

        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(admin);
        vm.stopPrank();

        assertEq(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
    }

    function test_earlyUnlock_revertWhen_PerpeutalLockEnabled() public {
        _lockYfiForYSD(1e18);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockEnabled.selector));
        yearnStakingDelegate.earlyUnlock(admin);
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 100_000 * 1e18); // limit deposit size to 100k ETH
        _setGaugeRewards();
        _depositGaugeTokensToYSD(wrappedStrategy, amount);

        // Check the yearn staking delegate has received the gauge tokens
        assertEq(yearnStakingDelegate.balanceOf(wrappedStrategy, gauge), amount, "deposit failed");
        assertEq(IERC20(gauge).balanceOf(address(yearnStakingDelegate)), amount, "deposit failed");
        assertEq(IERC20(gauge).balanceOf(wrappedStrategy), 0, "deposit failed");
    }

    function testFuzz_deposit_revertWhen_GaugeRewardsNotYetAdded(uint256 amount) public {
        vm.assume(amount > 0);

        address newGaugeToken = address(new ERC20Mock());
        airdrop(IERC20(newGaugeToken), wrappedStrategy, amount);

        vm.startPrank(wrappedStrategy);
        IERC20(newGaugeToken).approve(address(yearnStakingDelegate), amount);
        vm.expectRevert(abi.encodeWithSelector(Errors.GaugeRewardsNotYetAdded.selector));
        yearnStakingDelegate.deposit(newGaugeToken, amount);
        vm.stopPrank();
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 100_000 * 1e18); // limit deposit size to 100k ETH
        _setGaugeRewards();
        _depositGaugeTokensToYSD(wrappedStrategy, amount);

        // Start withdraw process
        vm.startPrank(wrappedStrategy);
        yearnStakingDelegate.withdraw(gauge, amount);
        vm.stopPrank();

        // Check the yearn staking delegate has released the gauge tokens
        assertEq(IERC20(gauge).balanceOf(address(yearnStakingDelegate)), 0, "withdraw failed");
        // Check the accounting is correct
        assertEq(yearnStakingDelegate.balanceOf(wrappedStrategy, gauge), 0, "withdraw failed");
        // Check that wrappedStrategy has received the vault tokens
        assertEq(IERC20(gauge).balanceOf(wrappedStrategy), amount, "withdraw failed");
    }

    function test_harvest_revertWhen_SwapAndLockNotSet() public {
        _setGaugeRewards();
        vm.expectRevert(abi.encodeWithSelector(Errors.SwapAndLockNotSet.selector));
        vm.prank(wrappedStrategy);
        yearnStakingDelegate.harvest(gauge);
    }

    function test_harvest_revertWhen_GaugeRewardsNotYetAdded() public {
        _setSwapAndLock();
        vm.expectRevert(abi.encodeWithSelector(Errors.GaugeRewardsNotYetAdded.selector));
        vm.prank(wrappedStrategy);
        yearnStakingDelegate.harvest(gauge);
    }

    function test_harvest_passWhen_NoVeYFI() public {
        _setSwapAndLock();
        _setGaugeRewards();
        _depositGaugeTokensToYSD(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        uint256 totalRewardAmount = yearnStakingDelegate.harvest(gauge);

        // Check that the vault has received the rewards
        assertEq(
            totalRewardAmount,
            IERC20(MAINNET_DYFI).balanceOf(stakingDelegateRewards),
            "harvest did not return correct value"
        );
        assertGt(IERC20(MAINNET_DYFI).balanceOf(stakingDelegateRewards), 0, "harvest failed");
    }

    function test_harvest_passWhen_SomeVeYFI() public {
        _lockYfiForYSD(1e18);
        _setSwapAndLock();
        _setGaugeRewards();
        _depositGaugeTokensToYSD(wrappedStrategy, 1e18);
        address bob = createUser("bob");
        _airdropGaugeTokens(bob, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        uint256 totalRewardAmount = yearnStakingDelegate.harvest(gauge);
        assertGt(totalRewardAmount, 0, "harvest failed");
        vm.prank(bob);
        IGauge(gauge).getReward(bob);
        uint256 nonBoostedRewardAmount = IERC20(MAINNET_DYFI).balanceOf(bob);
        assertGt(nonBoostedRewardAmount, 0, "harvest failed");
        assertGt(totalRewardAmount, nonBoostedRewardAmount, "veYfi boost failed");
        // Check that the vault has received the rewards
        assertEq(
            totalRewardAmount,
            IERC20(MAINNET_DYFI).balanceOf(stakingDelegateRewards),
            "harvest did not return correct value"
        );
    }

    function test_harvest_passWhen_LargeVeYFI() public {
        _lockYfiForYSD(ALICE_YFI);
        _setSwapAndLock();
        _setGaugeRewards();
        _depositGaugeTokensToYSD(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        uint256 totalRewardAmount = yearnStakingDelegate.harvest(gauge);

        // Check that the StakingDelegateRewards contract has received the rewards
        // expect to be close to 100% of the rewards
        assertEq(
            totalRewardAmount,
            IERC20(MAINNET_DYFI).balanceOf(stakingDelegateRewards),
            "harvest did not return correct value"
        );
        assertGt(IERC20(MAINNET_DYFI).balanceOf(stakingDelegateRewards), 0, "harvest failed");
    }

    function test_harvest_passWhen_WithVeYfiSplit() public {
        _lockYfiForYSD(1e18);
        _setSwapAndLock();
        _setGaugeRewards();
        _setRewardSplit(gauge, 0.3e18, 0.3e18, 0.4e18);
        _depositGaugeTokensToYSD(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        uint256 totalRewardAmount = yearnStakingDelegate.harvest(gauge);
        assertGt(totalRewardAmount, 0, "harvest failed");

        // Calculate split amounts strategy split amount
        uint256 estimatedTreasurySplit = totalRewardAmount * 0.3e18 / 1e18;
        uint256 estimatedVeYfiSplit = totalRewardAmount * 0.4e18 / 1e18;
        uint256 estimatedUserSplit = totalRewardAmount - estimatedTreasurySplit - estimatedVeYfiSplit;

        uint256 strategyDYfiBalance = IERC20(MAINNET_DYFI).balanceOf(stakingDelegateRewards);
        assertEq(strategyDYfiBalance, estimatedUserSplit, "strategy split is incorrect");

        uint256 treasuryBalance = IERC20(MAINNET_DYFI).balanceOf(treasury);
        assertEq(treasuryBalance, estimatedTreasurySplit, "treausry split is incorrect");

        uint256 swapAndLockBalance = IERC20(MAINNET_DYFI).balanceOf(address(swapAndLock));
        assertEq(swapAndLockBalance, estimatedVeYfiSplit, "veYfi split is incorrect");
    }

    function test_claimBoostRewards() public {
        _lockYfiForYSD(10e18);
        vm.warp(block.timestamp + 1 weeks);
        yearnStakingDelegate.claimBoostRewards();
        uint256 balanceBefore = IERC20(MAINNET_DYFI).balanceOf(treasury);
        // Alice deposits some vault tokens to a yearn gauge without any veYFI
        airdrop(IERC20(vault), alice, 1e18);
        vm.startPrank(alice);
        IERC20(vault).approve(address(gauge), 1e18);
        IGauge(gauge).deposit(1e18, alice);
        vm.stopPrank();
        // Some time passes
        vm.warp(block.timestamp + 2 weeks);
        // Claim the dYFI gauge rewards for alice
        IGauge(gauge).getReward(alice);
        vm.warp(block.timestamp + 1 weeks);
        // YSD claims the dYFI rewards Alice was penalized for
        yearnStakingDelegate.claimBoostRewards();
        uint256 balanceAfter = IERC20(MAINNET_DYFI).balanceOf(treasury);
        assertGt(balanceAfter, balanceBefore, "claimBoostRewards failed");
    }

    function test_claimExitRewards() public {
        // Lock YFI for YSD
        _lockYfiForYSD(10e18);
        vm.warp(block.timestamp + 1 weeks);
        yearnStakingDelegate.claimExitRewards();
        uint256 balanceBefore = IERC20(MAINNET_YFI).balanceOf(treasury);
        // Lock YFI for the user
        _lockYfiForUser(alice, 10e18, 8 * 52 weeks);
        // Another user early exits
        vm.prank(alice);
        IVotingYFI(MAINNET_VE_YFI).withdraw();
        // Advance to the next epoch
        vm.warp(block.timestamp + 1 weeks);
        // Claim exit rewards
        yearnStakingDelegate.claimExitRewards();
        uint256 balanceAfter = IERC20(MAINNET_YFI).balanceOf(treasury);
        // Assert the treasury balance is increased by the expected amount
        assertGt(balanceAfter, balanceBefore, "claimBoostRewards failed");
    }

    function test_setSnapshotDelegate() public {
        vm.prank(admin);
        yearnStakingDelegate.setSnapshotDelegate("veyfi.eth", manager);

        assertEq(
            ISnapshotDelegateRegistry(MAINNET_SNAPSHOT_DELEGATE_REGISTRY).delegation(
                address(yearnStakingDelegate), "veyfi.eth"
            ),
            manager,
            "setSnapshotDelegate failed"
        );
    }

    function test_setSnapshotDelegate_revertWhen_ZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        yearnStakingDelegate.setSnapshotDelegate("veyfi.eth", address(0));
        vm.stopPrank();
    }

    function testFuzz_setTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0));
        vm.prank(admin);
        yearnStakingDelegate.setTreasury(newTreasury);
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
        yearnStakingDelegate.setRewardSplit(gauge, a, b, c);
        (uint80 treasurySplit, uint80 strategySplit, uint80 lockSplit) = yearnStakingDelegate.gaugeRewardSplit(gauge);
        assertEq(treasurySplit, a, "setRewardSplit failed, treasury split is incorrect");
        assertEq(strategySplit, b, "setRewardSplit failed, strategy split is incorrect");
        assertEq(lockSplit, c, "setRewardSplit failed, lock split is incorrect");
    }

    function testFuzz_setRewardSplit_revertWhen_InvalidRewardSplit(uint80 a, uint80 b, uint80 c) public {
        vm.assume(uint256(a) + b + c != 1e18);
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardSplit.selector));
        yearnStakingDelegate.setRewardSplit(gauge, a, b, c);
        vm.stopPrank();
    }
}

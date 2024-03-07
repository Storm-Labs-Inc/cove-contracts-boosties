// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { ERC4626Mock } from "@openzeppelin/contracts/mocks/ERC4626Mock.sol";
import { MockGauge } from "test/mocks/MockGauge.sol";
import { MockGaugeRewardReceiver } from "test/mocks/MockGaugeRewardReceiver.sol";
import { MockStakingDelegateRewards } from "test/mocks/MockStakingDelegateRewards.sol";
import { MockVotingYFI } from "test/mocks/MockVotingYFI.sol";
import { MockRewardPool } from "test/mocks/MockRewardPool.sol";
import { MockTarget } from "test/mocks/MockTarget.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";

contract YearnStakingDelegate_Test is BaseTest {
    using SafeERC20 for IERC20;

    YearnStakingDelegate public yearnStakingDelegate;
    address public testGauge;
    address public testVault;
    address public baseAsset;
    address public stakingDelegateRewards;
    address public swapAndLock;
    address public dYfi;
    address public yfi;
    address public veYfi;
    address public yfiRewardPool;
    address public dYfiRewardPool;
    address public mockTarget;
    address public coveYfiRewardForwarder;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 10e18;
    uint256 public constant YFI_REWARD_AMOUNT = 5e18;
    uint256 public constant YFI_MAX_SUPPLY = 36_666e18;

    // Addresses
    address public admin;
    address public alice;
    address public timelock;
    address public pauser;
    address public treasury;

    event LockYfi(address indexed sender, uint256 amount);
    event GaugeRewardsSet(address indexed gauge, address stakingRewardsContract, address receiver);
    event PerpetualLockSet(bool shouldLock);
    event GaugeRewardSplitSet(address indexed gauge, IYearnStakingDelegate.RewardSplit split);
    event SwapAndLockSet(address swapAndLockContract);
    event TreasurySet(address newTreasury);
    event CoveYfiRewardForwarderSet(address forwarder);
    event Deposit(address indexed sender, address indexed gauge, uint256 amount);
    event Withdraw(address indexed sender, address indexed gauge, uint256 amount);

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        // create alice who will be lock YFI via the yearnStakingDelegate
        alice = createUser("alice");
        // create timelock address for the yearnStakingDelegate
        timelock = createUser("timelock");
        // create pauser of the yearnStakingDelegate
        pauser = createUser("pauser");
        // create an address that will act as the treasury
        treasury = createUser("treasury");
        // create an address that will act as the coveYfiRewardForwarder
        coveYfiRewardForwarder = createUser("coveYfiRewardForwarder");

        // Deploy base asset
        baseAsset = address(new ERC20Mock());
        // Deploy vault
        testVault = address(new ERC4626Mock(baseAsset));
        // Deploy gauge
        testGauge = address(new MockGauge(testVault));
        // Deploy YFI related tokens
        dYfi = MAINNET_DYFI;
        vm.etch(dYfi, address(new ERC20Mock()).code);
        yfi = MAINNET_YFI;
        vm.etch(yfi, address(new ERC20Mock()).code);
        veYfi = MAINNET_VE_YFI;
        vm.etch(veYfi, address(new MockVotingYFI(yfi)).code);
        yfiRewardPool = MAINNET_YFI_REWARD_POOL;
        vm.etch(yfiRewardPool, address(new MockRewardPool(yfi)).code);
        dYfiRewardPool = MAINNET_DYFI_REWARD_POOL;
        vm.etch(dYfiRewardPool, address(new MockRewardPool(dYfi)).code);
        mockTarget = address(new MockTarget());

        address receiver = address(new MockGaugeRewardReceiver());
        yearnStakingDelegate = new YearnStakingDelegate(receiver, treasury, admin, pauser, timelock);
        stakingDelegateRewards = address(new MockStakingDelegateRewards(dYfi));
        swapAndLock = createUser("swapAndLock");

        // Setup approvals for YFI spending
        vm.startPrank(alice);
        IERC20(yfi).approve(address(yearnStakingDelegate), type(uint256).max);
        vm.stopPrank();
    }

    // Need a special function to airdrop to the gauge since it relies on totalSupply for calculation
    function _airdropGaugeTokens(address user, uint256 amount) internal {
        airdrop(ERC20(testVault), user, amount);
        vm.startPrank(user);
        IERC20(testVault).approve(address(testGauge), amount);
        IGauge(testGauge).deposit(amount, user);
        vm.stopPrank();
    }

    function _addTestGaugeRewards() internal {
        vm.prank(admin);
        yearnStakingDelegate.addGaugeRewards(testGauge, stakingDelegateRewards);
    }

    function _setSwapAndLock() internal {
        vm.expectEmit();
        emit SwapAndLockSet(swapAndLock);
        vm.prank(timelock);
        yearnStakingDelegate.setSwapAndLock(swapAndLock);
    }

    function _setCoveYfiRewardForwarder(address forwarder) internal {
        vm.expectEmit();
        emit CoveYfiRewardForwarderSet(forwarder);
        vm.prank(timelock);
        yearnStakingDelegate.setCoveYfiRewardForwarder(forwarder);
    }

    function _setGaugeRewardSplit(
        address gauge,
        uint64 treasurySplit,
        uint64 coveYfiSplit,
        uint64 userSplit,
        uint64 lockSplit
    )
        internal
    {
        vm.prank(timelock);
        yearnStakingDelegate.setGaugeRewardSplit(gauge, treasurySplit, coveYfiSplit, userSplit, lockSplit);
    }

    function _setBoostRewardSplit(uint128 treasurySplit, uint128 coveYfiSplit) internal {
        vm.prank(timelock);
        yearnStakingDelegate.setBoostRewardSplit(treasurySplit, coveYfiSplit);
    }

    function _setExitRewardSplit(uint128 treasurySplit, uint128 coveYfiSplit) internal {
        vm.prank(timelock);
        yearnStakingDelegate.setExitRewardSplit(treasurySplit, coveYfiSplit);
    }

    function _lockYfiForYSD(address from, uint256 amount) internal {
        airdrop(ERC20(MAINNET_YFI), from, amount);
        vm.prank(from);
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
        IERC20(testGauge).approve(address(yearnStakingDelegate), amount);
        vm.expectEmit();
        emit Deposit(from, testGauge, amount);
        yearnStakingDelegate.deposit(testGauge, amount);
        vm.stopPrank();
    }

    function testFuzz_constructor(address anyGauge) public {
        // Check for storage variables default values
        assertEq(yearnStakingDelegate.yfi(), MAINNET_YFI);
        assertEq(yearnStakingDelegate.dYfi(), MAINNET_DYFI);
        assertEq(yearnStakingDelegate.veYfi(), MAINNET_VE_YFI);
        assertTrue(yearnStakingDelegate.shouldPerpetuallyLock());
        IYearnStakingDelegate.RewardSplit memory rewardSplit = yearnStakingDelegate.getGaugeRewardSplit(anyGauge);
        assertEq(rewardSplit.treasury, 0);
        assertEq(rewardSplit.coveYfi, 0);
        assertEq(rewardSplit.user, 0);
        assertEq(rewardSplit.lock, 0);
        // Check for roles
        assertTrue(yearnStakingDelegate.hasRole(yearnStakingDelegate.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(yearnStakingDelegate.hasRole(_PAUSER_ROLE, pauser));
        assertTrue(yearnStakingDelegate.hasRole(_TIMELOCK_ROLE, timelock));
        // Check for approvals
        assertEq(IERC20(MAINNET_YFI).allowance(address(yearnStakingDelegate), MAINNET_VE_YFI), type(uint256).max);
    }

    function test_unpause() public {
        vm.prank(pauser);
        yearnStakingDelegate.pause();
        assertTrue(yearnStakingDelegate.paused(), "contract not paused");
        vm.prank(admin);
        yearnStakingDelegate.unpause();
        assertFalse(yearnStakingDelegate.paused(), "contract not unpaused");
    }

    function test_pause_revertWhen_notPauser() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.Unauthorized.selector));
        yearnStakingDelegate.pause();
    }

    function test_unpause_revertWhen_notAdmin() public {
        vm.expectRevert(_formatAccessControlError(address(this), yearnStakingDelegate.DEFAULT_ADMIN_ROLE()));
        yearnStakingDelegate.unpause();
    }

    function test_lockYFI() public {
        vm.expectEmit();
        emit LockYfi(alice, 1e18);
        _lockYfiForYSD(alice, 1e18);
    }

    function test_lockYFI_revertWhen_WithZeroAmount() public {
        uint256 lockAmount = 0;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        vm.prank(alice);
        yearnStakingDelegate.lockYfi(lockAmount);
    }

    function test_lockYFI_revertWhen_PerpetualLockDisabled() public {
        vm.prank(timelock);
        yearnStakingDelegate.setPerpetualLock(false);
        uint256 lockAmount = 1e18;
        airdrop(ERC20(MAINNET_YFI), alice, lockAmount);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockDisabled.selector));
        yearnStakingDelegate.lockYfi(lockAmount);
    }

    function test_lockYfi_revertWhen_Paused() public {
        vm.prank(admin);
        yearnStakingDelegate.pause();
        assertTrue(yearnStakingDelegate.paused());
        vm.expectRevert("Pausable: paused");
        yearnStakingDelegate.lockYfi(1e18);
    }

    function test_setPerpetualLock() public {
        vm.expectEmit();
        emit PerpetualLockSet(false);
        vm.prank(timelock);
        yearnStakingDelegate.setPerpetualLock(false);
        assertTrue(!yearnStakingDelegate.shouldPerpetuallyLock());

        vm.expectEmit();
        emit PerpetualLockSet(true);
        vm.prank(timelock);
        yearnStakingDelegate.setPerpetualLock(true);
        assertTrue(yearnStakingDelegate.shouldPerpetuallyLock());
    }

    function test_earlyUnlock() public {
        _lockYfiForYSD(alice, 1e18);

        vm.startPrank(timelock);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock();
        vm.stopPrank();

        assertEq(IERC20(yfi).balanceOf(address(veYfi)), 0, "early unlock failed");
        assertEq(IERC20(yfi).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
        assertEq(IERC20(yfi).balanceOf(treasury), 1e18, "early unlock failed");
    }

    function testFuzz_earlyUnlock(uint256 lockAmount) public {
        vm.assume(lockAmount > 0);
        _lockYfiForYSD(alice, lockAmount);

        vm.startPrank(timelock);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock();
        vm.stopPrank();

        assertEq(IERC20(yfi).balanceOf(address(veYfi)), 0, "early unlock failed");
        assertEq(IERC20(yfi).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
        assertEq(IERC20(yfi).balanceOf(treasury), lockAmount, "early unlock failed");
    }

    function test_earlyUnlock_revertWhen_PerpeutalLockEnabled() public {
        _lockYfiForYSD(alice, 1e18);

        vm.startPrank(timelock);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockEnabled.selector));
        yearnStakingDelegate.earlyUnlock();
    }

    function test_earlyUnlock_revertWhen_CallerIsNotTimelock() public {
        _lockYfiForYSD(alice, 1e18);

        vm.expectRevert(_formatAccessControlError(admin, _TIMELOCK_ROLE));
        vm.prank(admin);
        yearnStakingDelegate.earlyUnlock();
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        _addTestGaugeRewards();
        _depositGaugeTokensToYSD(alice, amount);

        // Check the yearn staking delegate has received the gauge tokens
        assertEq(yearnStakingDelegate.balanceOf(alice, testGauge), amount, "deposit failed");
        assertEq(IERC20(testGauge).balanceOf(address(yearnStakingDelegate)), amount, "deposit failed");
        assertEq(IERC20(testGauge).balanceOf(alice), 0, "deposit failed");
    }

    function testFuzz_deposit_revertWhen_GaugeRewardsNotYetAdded(uint256 amount) public {
        vm.assume(amount > 0);

        address newGaugeToken = address(new ERC20Mock());
        airdrop(IERC20(newGaugeToken), alice, amount);

        vm.startPrank(alice);
        IERC20(newGaugeToken).approve(address(yearnStakingDelegate), amount);
        vm.expectRevert(abi.encodeWithSelector(Errors.GaugeRewardsNotYetAdded.selector));
        yearnStakingDelegate.deposit(newGaugeToken, amount);
        vm.stopPrank();
    }

    function test_deposit_revertWhen_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        yearnStakingDelegate.deposit(testGauge, 0);
    }

    function test_deposit_revertWhen_Paused() public {
        vm.prank(pauser);
        yearnStakingDelegate.pause();
        assertTrue(yearnStakingDelegate.paused());
        vm.expectRevert("Pausable: paused");
        yearnStakingDelegate.deposit(testGauge, 1e18);
    }

    function testFuzz_deposit_passWhen_unpaused(uint256 amount) public {
        vm.assume(amount > 0);

        vm.prank(pauser);
        yearnStakingDelegate.pause();
        assertTrue(yearnStakingDelegate.paused());
        vm.prank(admin);
        yearnStakingDelegate.unpause();
        assertTrue(!yearnStakingDelegate.paused());
        _addTestGaugeRewards();
        _depositGaugeTokensToYSD(alice, amount);
        assertEq(IERC20(testGauge).balanceOf(address(yearnStakingDelegate)), amount, "deposit failed");
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount > 0);
        _addTestGaugeRewards();
        _depositGaugeTokensToYSD(alice, amount);

        // Start withdraw process
        vm.startPrank(alice);
        vm.expectEmit();
        emit Withdraw(alice, testGauge, amount);
        yearnStakingDelegate.withdraw(testGauge, amount);
        vm.stopPrank();

        // Check the yearn staking delegate has released the gauge tokens
        assertEq(IERC20(testGauge).balanceOf(address(yearnStakingDelegate)), 0, "withdraw failed");
        // Check the accounting is correct
        assertEq(yearnStakingDelegate.balanceOf(alice, testGauge), 0, "withdraw failed");
        // Check that wrappedStrategy has received the vault tokens
        assertEq(IERC20(testGauge).balanceOf(alice), amount, "withdraw failed");
    }

    function test_withdraw_revertWhen_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        yearnStakingDelegate.withdraw(testGauge, 0);
    }

    function testFuzz_withdraw_passWhen_Paused(uint256 amount) public {
        vm.assume(amount > 0);
        _addTestGaugeRewards();
        _depositGaugeTokensToYSD(alice, amount);
        vm.prank(pauser);
        yearnStakingDelegate.pause();

        // Start withdraw process
        vm.startPrank(alice);
        vm.expectEmit();
        emit Withdraw(alice, testGauge, amount);
        yearnStakingDelegate.withdraw(testGauge, amount);
        vm.stopPrank();

        // Check the yearn staking delegate has released the gauge tokens
        assertEq(IERC20(testGauge).balanceOf(address(yearnStakingDelegate)), 0, "withdraw failed");
        // Check the accounting is correct
        assertEq(yearnStakingDelegate.balanceOf(alice, testGauge), 0, "withdraw failed");
        // Check that wrappedStrategy has received the vault tokens
        assertEq(IERC20(testGauge).balanceOf(alice), amount, "withdraw failed");
    }

    function test_harvest_revertWhen_SwapAndLockNotSet() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.SwapAndLockNotSet.selector));
        yearnStakingDelegate.harvest(testGauge);
    }

    function test_harvest_revertWhen_GaugeRewardsNotYetAdded() public {
        _setSwapAndLock();
        vm.expectRevert(abi.encodeWithSelector(Errors.GaugeRewardsNotYetAdded.selector));
        yearnStakingDelegate.harvest(testGauge);
    }

    function test_harvest_revertWhen_CoveYfiRewardForwarderNotSet() public {
        _setSwapAndLock();
        _addTestGaugeRewards();
        vm.prank(timelock);
        yearnStakingDelegate.setTreasury(treasury);
        vm.expectRevert(abi.encodeWithSelector(Errors.CoveYfiRewardForwarderNotSet.selector));
        yearnStakingDelegate.harvest(testGauge);
    }

    function testFuzz_setBoostRewardSplit(uint128 treasuryPct) public {
        vm.assume(treasuryPct <= 0.2e18);
        uint128 coveYfiPct = 1e18 - treasuryPct;
        _setBoostRewardSplit(treasuryPct, coveYfiPct);
        IYearnStakingDelegate.BoostRewardSplit memory rewardSplit = yearnStakingDelegate.getBoostRewardSplit();
        assertEq(rewardSplit.treasury, treasuryPct, "setBoostRewardSplit failed, treasury split is incorrect");
        assertEq(rewardSplit.coveYfi, coveYfiPct, "setBoostRewardSplit failed, coveYfi split is incorrect");
    }

    function testFuzz_setBoostRewardSplit_revertWhen_InvalidRewardSplit(
        uint128 treasuryPct,
        uint128 coveYfiPct
    )
        public
    {
        vm.assume(treasuryPct <= 0.2e18);
        vm.assume(uint256(treasuryPct) + coveYfiPct != 1e18);
        vm.startPrank(timelock);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardSplit.selector));
        yearnStakingDelegate.setBoostRewardSplit(treasuryPct, coveYfiPct);
        vm.stopPrank();
    }

    function testFuzz_setBoostRewardSplit_revertWhen_TreasuryPctTooHigh(uint128 treasuryPct) public {
        vm.assume(treasuryPct > 0.2e18);
        vm.assume(treasuryPct <= 1e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.TreasuryPctTooHigh.selector));
        vm.prank(timelock);
        yearnStakingDelegate.setBoostRewardSplit(treasuryPct, 1e18 - treasuryPct);
    }

    function test_setBoostRewardSplit_revertWhen_CallerIsNotTimelock() public {
        vm.expectRevert(_formatAccessControlError(admin, _TIMELOCK_ROLE));
        vm.prank(admin);
        yearnStakingDelegate.setBoostRewardSplit(1e18, 0);
    }

    function testFuzz_setCoveYfiRewardForwarder(address forwarder) public {
        vm.assume(forwarder != address(0));
        vm.expectEmit();
        emit CoveYfiRewardForwarderSet(forwarder);
        vm.prank(timelock);
        yearnStakingDelegate.setCoveYfiRewardForwarder(forwarder);
        assertEq(yearnStakingDelegate.coveYfiRewardForwarder(), forwarder, "setCoveYfiRewardForwarder failed");
    }

    function test_setCoveYfiRewardForwarder_revertWhen_ZeroAddress() public {
        vm.prank(timelock);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        yearnStakingDelegate.setCoveYfiRewardForwarder(address(0));
    }

    function testFuzz_claimBoostRewards(uint128 treasuryPct) public {
        vm.assume(treasuryPct <= 0.2e18);
        uint128 coveYfiPct = 1e18 - treasuryPct;
        _setBoostRewardSplit(treasuryPct, coveYfiPct);
        _setCoveYfiRewardForwarder(coveYfiRewardForwarder);
        airdrop(IERC20(dYfi), dYfiRewardPool, DYFI_REWARD_AMOUNT);
        // YSD claims the dYFI rewards Alice was penalized for
        yearnStakingDelegate.claimBoostRewards();
        uint256 treasuryAmount = DYFI_REWARD_AMOUNT * treasuryPct / 1e18;
        uint256 coveYfiAmount = DYFI_REWARD_AMOUNT - treasuryAmount;
        assertEq(IERC20(dYfi).balanceOf(treasury), treasuryAmount, "claimBoostRewards failed");
        assertEq(IERC20(dYfi).balanceOf(coveYfiRewardForwarder), coveYfiAmount, "claimBoostRewards failed");
    }

    function test_claimBoostRewards_revertWhen_CoveYfiRewardForwarderNotSet() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.CoveYfiRewardForwarderNotSet.selector));
        yearnStakingDelegate.claimBoostRewards();
    }

    function testFuzz_setExitRewardSplit(uint128 treasuryPct) public {
        vm.assume(treasuryPct <= 0.2e18);
        uint128 coveYfiPct = 1e18 - treasuryPct;
        _setExitRewardSplit(treasuryPct, coveYfiPct);
        IYearnStakingDelegate.ExitRewardSplit memory rewardSplit = yearnStakingDelegate.getExitRewardSplit();
        assertEq(rewardSplit.treasury, treasuryPct, "setExitRewardSplit failed, treasury split is incorrect");
        assertEq(rewardSplit.coveYfi, coveYfiPct, "setExitRewardSplit failed, coveYfi split is incorrect");
    }

    function testFuzz_setExitRewardSplit_revertWhen_InvalidRewardSplit(
        uint128 treasuryPct,
        uint128 coveYfiPct
    )
        public
    {
        vm.assume(treasuryPct <= 0.2e18);
        vm.assume(uint256(treasuryPct) + coveYfiPct != 1e18);
        vm.startPrank(timelock);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardSplit.selector));
        yearnStakingDelegate.setExitRewardSplit(treasuryPct, coveYfiPct);
        vm.stopPrank();
    }

    function testFuzz_setExitRewardSplit_revertWhen_TreasuryPctTooHigh(uint128 treasuryPct) public {
        vm.assume(treasuryPct > 0.2e18);
        vm.assume(treasuryPct <= 1e18);
        vm.startPrank(timelock);
        vm.expectRevert(abi.encodeWithSelector(Errors.TreasuryPctTooHigh.selector));
        yearnStakingDelegate.setExitRewardSplit(treasuryPct, 1e18 - treasuryPct);
        vm.stopPrank();
    }

    function test_setExitRewardSplit_revertWhen_CallerIsNotTimelock() public {
        vm.expectRevert(_formatAccessControlError(admin, _TIMELOCK_ROLE));
        vm.prank(admin);
        yearnStakingDelegate.setExitRewardSplit(1e18, 0);
    }

    function testFuzz_claimExitRewards(uint128 treasuryPct) public {
        vm.assume(treasuryPct <= 0.2e18);
        uint128 coveYfiPct = 1e18 - treasuryPct;
        _setExitRewardSplit(treasuryPct, coveYfiPct);
        _setCoveYfiRewardForwarder(coveYfiRewardForwarder);
        airdrop(IERC20(yfi), yfiRewardPool, YFI_REWARD_AMOUNT);
        // YSD claims the dYFI rewards Alice was penalized for
        yearnStakingDelegate.claimExitRewards();
        uint256 treasuryAmount = YFI_REWARD_AMOUNT * treasuryPct / 1e18;
        uint256 coveYfiAmount = YFI_REWARD_AMOUNT - treasuryAmount;
        assertEq(IERC20(yfi).balanceOf(treasury), treasuryAmount, "claimExitRewards failed");
        assertEq(IERC20(yfi).balanceOf(coveYfiRewardForwarder), coveYfiAmount, "claimExitRewards failed");
    }

    function test_claimExitRewards_revertWhen_CoveYfiRewardForwarderNotSet() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.CoveYfiRewardForwarderNotSet.selector));
        yearnStakingDelegate.claimExitRewards();
    }

    function testFuzz_setTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0));
        vm.expectEmit();
        emit TreasurySet(newTreasury);
        vm.prank(timelock);
        yearnStakingDelegate.setTreasury(newTreasury);
        assertEq(yearnStakingDelegate.treasury(), newTreasury, "setTreasury failed");
    }

    function test_setTreasury_revertWhen_ZeroAddress() public {
        vm.startPrank(timelock);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        yearnStakingDelegate.setTreasury(address(0));
        vm.stopPrank();
    }

    function test_setTreasury_revertWhen_CallerIsNotTimelock() public {
        vm.expectRevert(_formatAccessControlError(admin, _TIMELOCK_ROLE));
        vm.prank(admin);
        yearnStakingDelegate.setTreasury(admin);
    }

    function testFuzz_setSwapAndLock(address newSwapAndLock) public {
        vm.assume(newSwapAndLock != address(0));
        vm.prank(timelock);
        yearnStakingDelegate.setSwapAndLock(newSwapAndLock);
        assertEq(yearnStakingDelegate.swapAndLock(), newSwapAndLock, "setSwapAndLock failed");
    }

    function test_setSwapAndLock_revertWhen_ZeroAddress() public {
        vm.startPrank(timelock);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        yearnStakingDelegate.setSwapAndLock(address(0));
        vm.stopPrank();
    }

    function test_setSwapAndLock_revertWhen_CallerIsNotTimelock() public {
        vm.expectRevert(_formatAccessControlError(admin, _TIMELOCK_ROLE));
        vm.prank(admin);
        yearnStakingDelegate.setSwapAndLock(admin);
    }

    function testFuzz_setGaugeRewardSplit(uint64 a, uint64 b, uint64 c) public {
        vm.assume(a <= 0.2e18);
        // Workaround for vm.assume max tries
        vm.assume(uint256(a) + b + c <= 1e18);
        uint64 d = 1e18 - a - b - c;
        vm.expectEmit();
        emit GaugeRewardSplitSet(testGauge, IYearnStakingDelegate.RewardSplit(a, b, c, d));
        vm.prank(timelock);
        yearnStakingDelegate.setGaugeRewardSplit(testGauge, a, b, c, d);
        IYearnStakingDelegate.RewardSplit memory rewardSplit = yearnStakingDelegate.getGaugeRewardSplit(testGauge);
        assertEq(rewardSplit.treasury, a, "setGaugeRewardSplit failed, treasury split is incorrect");
        assertEq(rewardSplit.coveYfi, b, "setGaugeRewardSplit failed, coveYfi split is incorrect");
        assertEq(rewardSplit.user, c, "setGaugeRewardSplit failed, user split is incorrect");
        assertEq(rewardSplit.lock, d, "setGaugeRewardSplit failed, lock split is incorrect");
    }

    function testFuzz_setGaugeRewardSplit_revertWhen_InvalidRewardSplit(
        uint64 a,
        uint64 b,
        uint64 c,
        uint64 d
    )
        public
    {
        vm.assume(uint256(a) + b + c + d != 1e18);
        vm.startPrank(timelock);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardSplit.selector));
        yearnStakingDelegate.setGaugeRewardSplit(testGauge, a, b, c, d);
        vm.stopPrank();
    }

    function test_setGaugeRewardSplit_revertWhen_CallerIsNotTimelock() public {
        vm.expectRevert(_formatAccessControlError(admin, _TIMELOCK_ROLE));
        vm.prank(admin);
        yearnStakingDelegate.setGaugeRewardSplit(testGauge, 1e18, 0, 0, 0);
    }

    function test_addGaugeRewards() public {
        _addTestGaugeRewards();
        assertEq(yearnStakingDelegate.gaugeStakingRewards(testGauge), stakingDelegateRewards, "addGaugeRewards failed");
    }

    function test_addGaugeRewards_revertWhen_GaugeZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        vm.prank(admin);
        yearnStakingDelegate.addGaugeRewards(address(0), stakingDelegateRewards);
    }

    function test_addGaugeRewards_revertWhen_StakingDelegateRewardsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        vm.prank(admin);
        yearnStakingDelegate.addGaugeRewards(testGauge, address(0));
    }

    function test_addGaugeRewards_revertWhen_GaugeRewardsAlreadyAdded() public {
        _addTestGaugeRewards();
        vm.expectRevert(abi.encodeWithSelector(Errors.GaugeRewardsAlreadyAdded.selector));
        vm.prank(admin);
        yearnStakingDelegate.addGaugeRewards(testGauge, stakingDelegateRewards);
    }

    function test_addGaugeRewards_revertWhen_CallerIsNotAdmin() public {
        vm.expectRevert(_formatAccessControlError(alice, DEFAULT_ADMIN_ROLE));
        vm.prank(alice);
        yearnStakingDelegate.addGaugeRewards(testGauge, stakingDelegateRewards);
    }

    function test_updateGaugeRewards() public {
        _addTestGaugeRewards();
        address newStakingDelegateRewards = address(new MockStakingDelegateRewards(dYfi));
        vm.prank(timelock);
        yearnStakingDelegate.updateGaugeRewards(testGauge, newStakingDelegateRewards);
        assertEq(
            yearnStakingDelegate.gaugeStakingRewards(testGauge), newStakingDelegateRewards, "updateGaugeRewards failed"
        );
    }

    function test_updateGaugeRewards_revertWhen_GaugeZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        vm.prank(timelock);
        yearnStakingDelegate.updateGaugeRewards(address(0), stakingDelegateRewards);
    }

    function test_updateGaugeRewards_revertWhen_StakingDelegateRewardsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        vm.prank(timelock);
        yearnStakingDelegate.updateGaugeRewards(testGauge, address(0));
    }

    function test_updateGaugeRewards_revertWhen_GaugeRewardsNotYetAdded() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.GaugeRewardsNotYetAdded.selector));
        vm.prank(timelock);
        yearnStakingDelegate.updateGaugeRewards(testGauge, stakingDelegateRewards);
    }

    function test_updateGaugeRewards_revertWhen_GaugeRewardsAlreadyAdded() public {
        _addTestGaugeRewards();
        vm.expectRevert(abi.encodeWithSelector(Errors.GaugeRewardsAlreadyAdded.selector));
        vm.prank(timelock);
        yearnStakingDelegate.updateGaugeRewards(testGauge, stakingDelegateRewards);
    }

    function test_updateGaugeRewards_revertWhen_CallerIsNotTimelock() public {
        vm.expectRevert(_formatAccessControlError(admin, _TIMELOCK_ROLE));
        vm.prank(admin);
        yearnStakingDelegate.updateGaugeRewards(testGauge, stakingDelegateRewards);
    }

    function test_execute() public {
        vm.prank(timelock);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        yearnStakingDelegate.execute{ value: 1 ether }(mockTarget, data, 1 ether);
        assertEq(MockTarget(payable(mockTarget)).value(), 1 ether, "execute failed");
        assertEq(MockTarget(payable(mockTarget)).data(), data, "execute failed");
    }

    function test_execute_passWhen_ZeroValue() public {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        vm.prank(timelock);
        yearnStakingDelegate.execute{ value: 0 }(mockTarget, data, 0);
        assertEq(MockTarget(payable(mockTarget)).value(), 0, "execute failed");
        assertEq(MockTarget(payable(mockTarget)).data(), data, "execute failed");
    }

    function testFuzz_execute(bytes4 selector, bytes32 data, address data2, uint256 value) public {
        vm.assume(selector != MockTarget.fail.selector);
        bytes memory fullData = abi.encodeWithSelector(selector, data, data2);
        assertEq(fullData.length, 68, "data packing failed");
        hoax(timelock, value);
        yearnStakingDelegate.execute{ value: value }(mockTarget, fullData, value);
        assertEq(MockTarget(payable(mockTarget)).value(), value, "execute failed");
        assertEq(MockTarget(payable(mockTarget)).data(), fullData, "execute failed");
    }

    function test_execute_revertWhen_TargetIsYFI_ExecutionNotAllowed() public {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.ExecutionNotAllowed.selector));
        vm.prank(timelock);
        yearnStakingDelegate.execute{ value: 1 ether }(yfi, data, 1 ether);
    }

    function test_execute_revertWhen_TargetIsDYFI_ExecutionNotAllowed() public {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.ExecutionNotAllowed.selector));
        vm.prank(timelock);
        yearnStakingDelegate.execute{ value: 1 ether }(dYfi, data, 1 ether);
    }

    function test_execute_revertWhen_TargetIsGaugeToken_ExecutionNotAllowed() public {
        _addTestGaugeRewards();
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.ExecutionNotAllowed.selector));
        vm.prank(timelock);
        yearnStakingDelegate.execute{ value: 1 ether }(testGauge, data, 1 ether);
    }

    function test_execute_revertWhen_TargetIsRewardReceiver_ExecutionNotAllowed() public {
        _addTestGaugeRewards();
        address target = yearnStakingDelegate.gaugeRewardReceivers(testGauge);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.ExecutionNotAllowed.selector));
        vm.prank(timelock);
        yearnStakingDelegate.execute{ value: 1 ether }(target, data, 1 ether);
    }

    function test_execute_revertWhen_TargetIsStakingRewards_ExecutionNotAllowed() public {
        _addTestGaugeRewards();
        address target = yearnStakingDelegate.gaugeStakingRewards(testGauge);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.ExecutionNotAllowed.selector));
        vm.prank(timelock);
        yearnStakingDelegate.execute{ value: 1 ether }(target, data, 1 ether);
    }

    function test_execute_revertWhen_TargetIsVeYFI_ExecutionNotAllowed() public {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.ExecutionNotAllowed.selector));
        vm.prank(timelock);
        yearnStakingDelegate.execute{ value: 1 ether }(veYfi, data, 1 ether);
    }

    function test_execute_revertWhen_TargetIsYFIRewardPool_ExecutionNotAllowed() public {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.ExecutionNotAllowed.selector));
        vm.prank(timelock);
        yearnStakingDelegate.execute{ value: 1 ether }(yfiRewardPool, data, 1 ether);
    }

    function test_execute_revertWhen_TargetIsDYFIRewardPool_ExecutionNotAllowed() public {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.ExecutionNotAllowed.selector));
        vm.prank(timelock);
        yearnStakingDelegate.execute{ value: 1 ether }(dYfiRewardPool, data, 1 ether);
    }

    function test_execute_revertWhen_ExecutionFailed() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.fail.selector);
        vm.expectRevert(abi.encodeWithSelector(Errors.ExecutionFailed.selector));
        vm.prank(timelock);
        yearnStakingDelegate.execute{ value: 1 ether }(mockTarget, data, 1 ether);
    }

    function test_execute_revertWhen_CallerIsNotTimelock() public {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        vm.expectRevert(_formatAccessControlError(admin, _TIMELOCK_ROLE));
        vm.prank(admin);
        yearnStakingDelegate.execute{ value: 1 ether }(mockTarget, data, 1 ether);
    }

    function test_grantRole_TimelockRole_revertWhen_CallerIsNotTimelock() public {
        vm.prank(admin);
        yearnStakingDelegate.grantRole(DEFAULT_ADMIN_ROLE, alice);
        vm.expectRevert(_formatAccessControlError(alice, _TIMELOCK_ROLE));
        vm.prank(alice);
        yearnStakingDelegate.grantRole(_TIMELOCK_ROLE, alice);
    }
}

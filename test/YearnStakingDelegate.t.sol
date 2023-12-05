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
import { IYearnStakingDelegateEvents } from "src/interfaces/IYearnStakingDelegateEvents.sol";

contract YearnStakingDelegate_Test is BaseTest, IYearnStakingDelegateEvents {
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

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 10e18;
    uint256 public constant YFI_REWARD_AMOUNT = 5e18;
    uint256 public constant YFI_MAX_SUPPLY = 36_666e18;

    // Addresses
    address public admin;
    address public alice;
    address public manager;
    address public treasury;

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        // create alice who will be lock YFI via the yearnStakingDelegate
        alice = createUser("alice");
        // create manager of the yearnStakingDelegate
        manager = createUser("manager");
        // create an address that will act as a treasury
        treasury = createUser("treasury");

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
        yearnStakingDelegate = new YearnStakingDelegate(receiver, treasury, admin, manager);
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

    function _setGaugeRewards() internal {
        vm.prank(admin);
        yearnStakingDelegate.addGaugeRewards(testGauge, stakingDelegateRewards);
    }

    function _setSwapAndLock() internal {
        vm.prank(admin);
        yearnStakingDelegate.setSwapAndLock(swapAndLock);
    }

    function _setRewardSplit(address gauge, uint80 treasurySplit, uint80 strategySplit, uint80 veYfiSplit) internal {
        vm.prank(admin);
        yearnStakingDelegate.setRewardSplit(gauge, treasurySplit, strategySplit, veYfiSplit);
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
        yearnStakingDelegate.deposit(testGauge, amount);
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
        vm.prank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        uint256 lockAmount = 1e18;
        airdrop(ERC20(MAINNET_YFI), alice, lockAmount);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockDisabled.selector));
        yearnStakingDelegate.lockYfi(lockAmount);
    }

    function test_earlyUnlock() public {
        _lockYfiForYSD(alice, 1e18);

        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(treasury);
        vm.stopPrank();

        assertEq(IERC20(yfi).balanceOf(address(veYfi)), 0, "early unlock failed");
        assertEq(IERC20(yfi).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
        assertEq(IERC20(yfi).balanceOf(treasury), 1e18, "early unlock failed");
    }

    function testFuzz_earlyUnlock(uint256 lockAmount) public {
        vm.assume(lockAmount > 0);
        _lockYfiForYSD(alice, lockAmount);

        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(treasury);
        vm.stopPrank();

        assertEq(IERC20(yfi).balanceOf(address(veYfi)), 0, "early unlock failed");
        assertEq(IERC20(yfi).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
        assertEq(IERC20(yfi).balanceOf(treasury), lockAmount, "early unlock failed");
    }

    function test_earlyUnlock_revertWhen_PerpeutalLockEnabled() public {
        _lockYfiForYSD(alice, 1e18);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockEnabled.selector));
        yearnStakingDelegate.earlyUnlock(admin);
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        _setGaugeRewards();
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

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount > 0);
        _setGaugeRewards();
        _depositGaugeTokensToYSD(alice, amount);

        // Start withdraw process
        vm.startPrank(alice);
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

    function test_harvest_revertWhen_SwapAndLockNotSet() public {
        _setGaugeRewards();
        vm.expectRevert(abi.encodeWithSelector(Errors.SwapAndLockNotSet.selector));
        yearnStakingDelegate.harvest(testGauge);
    }

    function test_harvest_revertWhen_GaugeRewardsNotYetAdded() public {
        _setSwapAndLock();
        vm.expectRevert(abi.encodeWithSelector(Errors.GaugeRewardsNotYetAdded.selector));
        yearnStakingDelegate.harvest(testGauge);
    }

    function test_claimBoostRewards() public {
        airdrop(IERC20(dYfi), dYfiRewardPool, DYFI_REWARD_AMOUNT);
        // YSD claims the dYFI rewards Alice was penalized for
        yearnStakingDelegate.claimBoostRewards();
        assertEq(IERC20(dYfi).balanceOf(treasury), DYFI_REWARD_AMOUNT, "claimBoostRewards failed");
    }

    function test_claimExitRewards() public {
        airdrop(IERC20(yfi), yfiRewardPool, YFI_REWARD_AMOUNT);
        // YSD claims the dYFI rewards Alice was penalized for
        yearnStakingDelegate.claimExitRewards();
        assertEq(IERC20(yfi).balanceOf(treasury), YFI_REWARD_AMOUNT, "claimExitRewards failed");
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
        yearnStakingDelegate.setRewardSplit(testGauge, a, b, c);
        (uint80 treasurySplit, uint80 strategySplit, uint80 lockSplit) =
            yearnStakingDelegate.gaugeRewardSplit(testGauge);
        assertEq(treasurySplit, a, "setRewardSplit failed, treasury split is incorrect");
        assertEq(strategySplit, b, "setRewardSplit failed, strategy split is incorrect");
        assertEq(lockSplit, c, "setRewardSplit failed, lock split is incorrect");
    }

    function testFuzz_setRewardSplit_revertWhen_InvalidRewardSplit(uint80 a, uint80 b, uint80 c) public {
        vm.assume(uint256(a) + b + c != 1e18);
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardSplit.selector));
        yearnStakingDelegate.setRewardSplit(testGauge, a, b, c);
        vm.stopPrank();
    }

    function test_addGaugeRewards() public {
        _setGaugeRewards();
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
        _setGaugeRewards();
        vm.expectRevert(abi.encodeWithSelector(Errors.GaugeRewardsAlreadyAdded.selector));
        vm.prank(admin);
        yearnStakingDelegate.addGaugeRewards(testGauge, stakingDelegateRewards);
    }

    function test_updateGaugeRewards() public {
        _setGaugeRewards();
        address newStakingDelegateRewards = address(new MockStakingDelegateRewards(dYfi));
        vm.prank(admin);
        yearnStakingDelegate.updateGaugeRewards(testGauge, newStakingDelegateRewards);
        assertEq(
            yearnStakingDelegate.gaugeStakingRewards(testGauge), newStakingDelegateRewards, "updateGaugeRewards failed"
        );
    }

    function test_updateGaugeRewards_revertWhen_GaugeZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        vm.prank(admin);
        yearnStakingDelegate.updateGaugeRewards(address(0), stakingDelegateRewards);
    }

    function test_updateGaugeRewards_revertWhen_StakingDelegateRewardsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        vm.prank(admin);
        yearnStakingDelegate.updateGaugeRewards(testGauge, address(0));
    }

    function test_updateGaugeRewards_revertWhen_GaugeRewardsNotYetAdded() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.GaugeRewardsNotYetAdded.selector));
        vm.prank(admin);
        yearnStakingDelegate.updateGaugeRewards(testGauge, stakingDelegateRewards);
    }

    function test_updateGaugeRewards_revertWhen_GaugeRewardsAlreadyAdded() public {
        _setGaugeRewards();
        vm.expectRevert(abi.encodeWithSelector(Errors.GaugeRewardsAlreadyAdded.selector));
        vm.prank(admin);
        yearnStakingDelegate.updateGaugeRewards(testGauge, stakingDelegateRewards);
    }

    function test_execute() public {
        vm.prank(admin);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(treasury), 100e18);
        yearnStakingDelegate.execute{ value: 1 ether }(mockTarget, data, 1 ether);
        assertEq(MockTarget(payable(mockTarget)).value(), 1 ether, "execute failed");
        assertEq(MockTarget(payable(mockTarget)).data(), data, "execute failed");
    }
}

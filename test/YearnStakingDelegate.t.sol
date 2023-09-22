// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "tokenized-strategy/interfaces/IStrategy.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { ISnapshotDelegateRegistry } from "src/interfaces/ISnapshotDelegateRegistry.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/IVotingYFI.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IGaugeFactory } from "src/interfaces/IGaugeFactory.sol";
import { IGauge } from "src/interfaces/IGauge.sol";

contract YearnStakingDelegateTest is YearnV3BaseTest {
    using SafeERC20 for IERC20;

    YearnStakingDelegate public yearnStakingDelegate;
    IStrategy public mockStrategy;
    address public testVault;
    address public testGauge;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant OYFI_REWARD_AMOUNT = 1_000_000e18;

    // Addresses
    address public alice;
    address public manager;
    address public wrappedStrategy;

    function setUp() public override {
        super.setUp();

        // create alice who will be lock YFI via the yearnStakingDelegate
        alice = createUser("alice");
        // create manager of the yearnStakingDelegate
        manager = createUser("manager");
        // create an address that will act as a wrapped strategy
        wrappedStrategy = createUser("wrappedStrategy");

        // Deploy vault
        testVault = deployVaultV3("USDC Test Vault", USDC, new address[](0));
        // Deploy gauge
        testGauge = deployGaugeViaFactory(testVault, admin, "USDC Test Vault Gauge");

        // Give alice some YFI
        airdrop(ERC20(ETH_YFI), alice, ALICE_YFI);

        // Give admin some oYFI
        airdrop(ERC20(oYFI), admin, OYFI_REWARD_AMOUNT);

        // Start new rewards
        vm.startPrank(admin);
        IERC20(oYFI).approve(testGauge, OYFI_REWARD_AMOUNT);
        IGauge(testGauge).queueNewRewards(OYFI_REWARD_AMOUNT);
        vm.stopPrank();

        require(IERC20(oYFI).balanceOf(testGauge) == OYFI_REWARD_AMOUNT, "queueNewRewards failed");

        yearnStakingDelegate = new YearnStakingDelegate(ETH_YFI, oYFI, ETH_VE_YFI, admin, manager);
    }

    function testFuzz_constructor(address noAdminRole, address noManagerRole) public {
        vm.assume(noAdminRole != admin);
        // manager role is given to admin and manager
        vm.assume(noManagerRole != manager && noManagerRole != admin);
        // Check for storage variables default values
        assertEq(yearnStakingDelegate.yfi(), ETH_YFI);
        assertEq(yearnStakingDelegate.oYfi(), oYFI);
        assertEq(yearnStakingDelegate.veYfi(), ETH_VE_YFI);
        assertTrue(yearnStakingDelegate.shouldPerpetuallyLock());
        (uint80 treasury, uint80 strategy, uint80 veYfi) = yearnStakingDelegate.rewardSplit();
        assertEq(treasury, 0);
        assertEq(strategy, 1e18);
        assertEq(veYfi, 0);
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
        assertLe(IERC20(oYFI).balanceOf(wrappedStrategy), OYFI_REWARD_AMOUNT / 10, "harvest failed");
        assertApproxEqRel(IERC20(oYFI).balanceOf(wrappedStrategy), OYFI_REWARD_AMOUNT / 10, 0.01e18, "harvest failed");
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
        assertGt(IERC20(oYFI).balanceOf(wrappedStrategy), OYFI_REWARD_AMOUNT / 10, "harvest failed");
        assertApproxEqRel(IERC20(oYFI).balanceOf(wrappedStrategy), OYFI_REWARD_AMOUNT / 10, 0.05e18, "harvest failed");
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
        assertApproxEqRel(IERC20(oYFI).balanceOf(wrappedStrategy), OYFI_REWARD_AMOUNT, 0.01e18, "harvest failed");
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
}

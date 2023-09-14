// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "tokenized-strategy/interfaces/IStrategy.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
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
    uint256 public constant ALICE_YFI = 5000e18;

    function setUp() public override {
        super.setUp();

        // create admin user that will be the owner of the yearnStakingDelegate
        createUser("admin");
        // create alice who will be lock YFI via the yearnStakingDelegate
        createUser("alice");
        // create manager of the yearnStakingDelegate
        createUser("manager");
        // create an address that will act as a wrapped strategy
        createUser("wrappedStrategy");

        // Deploy vault
        testVault = deployVaultV3("USDC Test Vault", USDC, new address[](0));
        // Deploy gauge
        testGauge = deployGaugeViaFactory(testVault, users["admin"], "USDC Test Vault Gauge");

        // Give alice some YFI
        airdrop(ERC20(ETH_YFI), users["alice"], ALICE_YFI);

        // Give admin some oYFI
        airdrop(ERC20(oYFI), users["admin"], 1_000_000e18);

        // Start new rewards
        vm.startPrank(users["admin"]);
        IERC20(oYFI).approve(testGauge, 1_000_000e18);
        IGauge(testGauge).queueNewRewards(1_000_000e18);
        vm.stopPrank();

        require(IERC20(oYFI).balanceOf(testGauge) == 1_000_000e18, "queueNewRewards failed");

        yearnStakingDelegate = new YearnStakingDelegate(ETH_YFI, oYFI, ETH_VE_YFI, users["admin"], users["manager"]);
    }

    function test_constructor(address noAdminRole, address noManagerRole) public {
        vm.assume(noAdminRole != users["admin"]);
        // manager role is given to admin and manager
        vm.assume(noManagerRole != users["manager"] && noManagerRole != users["admin"]);
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
        assertTrue(yearnStakingDelegate.hasRole(yearnStakingDelegate.MANAGER_ROLE(), users["manager"]));
        assertTrue(!yearnStakingDelegate.hasRole(yearnStakingDelegate.MANAGER_ROLE(), noManagerRole));
        assertTrue(yearnStakingDelegate.hasRole(yearnStakingDelegate.DEFAULT_ADMIN_ROLE(), users["admin"]));
        assertTrue(!yearnStakingDelegate.hasRole(yearnStakingDelegate.DEFAULT_ADMIN_ROLE(), noAdminRole));
        // Check for approvals
        assertEq(IERC20(ETH_YFI).allowance(address(yearnStakingDelegate), ETH_VE_YFI), type(uint256).max);
    }

    function test_setAssociatedGauge() public {
        vm.prank(users["manager"]);
        yearnStakingDelegate.setAssociatedGauge(testVault, testGauge);
        require(yearnStakingDelegate.associatedGauge(testVault) == testGauge, "setAssociatedGauge failed");
    }

    function _lockYFI(address user, uint256 amount) internal {
        vm.startPrank(user);
        IERC20(ETH_YFI).approve(address(yearnStakingDelegate), amount);
        yearnStakingDelegate.lockYfi(amount);
        vm.stopPrank();
    }

    function test_lockYFI() public {
        _lockYFI(users["alice"], 1e18);

        assertEq(IERC20(ETH_YFI).balanceOf(address(yearnStakingDelegate)), 0, "lock failed");
        assertEq(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)), 999_999_999_971_481_600, "lock failed");
    }

    function testFuzz_lockYFI_revertsWhenCreatingLockWithLessThanMinAmount(uint256 lockAmount) public {
        vm.assume(lockAmount > 0);
        vm.assume(lockAmount < 1e18);
        vm.startPrank(users["alice"]);
        IERC20(ETH_YFI).approve(address(yearnStakingDelegate), lockAmount);
        vm.expectRevert();
        yearnStakingDelegate.lockYfi(lockAmount);
        vm.stopPrank();
    }

    function testFuzz_lockYFI(uint256 lockAmount) public {
        vm.assume(lockAmount >= 1e18);
        vm.assume(lockAmount < IERC20(ETH_YFI).balanceOf(users["alice"]));
        _lockYFI(users["alice"], lockAmount);

        assertEq(IERC20(ETH_YFI).balanceOf(address(yearnStakingDelegate)), 0, "lock failed");
        assertGt(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)), lockAmount - 1e9, "lock failed");
        assertLe(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)), lockAmount, "lock failed");
    }

    function test_earlyUnlock() public {
        _lockYFI(users["alice"], 1e18);

        vm.startPrank(users["admin"]);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(users["admin"]);
        vm.stopPrank();

        assertEq(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
    }

    function testFuzz_earlyUnlock(uint256 lockAmount) public {
        vm.assume(lockAmount >= 1e18);
        vm.assume(lockAmount < IERC20(ETH_YFI).balanceOf(users["alice"]));
        _lockYFI(users["alice"], lockAmount);

        vm.startPrank(users["admin"]);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(users["admin"]);
        vm.stopPrank();

        assertEq(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
    }

    function test_earlyUnlock_revertsPerpeutalLockEnabled() public {
        _lockYFI(users["alice"], 1e18);

        vm.startPrank(users["admin"]);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockEnabled.selector));
        yearnStakingDelegate.earlyUnlock(users["admin"]);
    }

    function testFuzz_depositToGauge(uint256 vaultBalance) public {
        vm.assume(vaultBalance > 0);
        vm.startPrank(users["manager"]);
        yearnStakingDelegate.setAssociatedGauge(testVault, testGauge);
        vm.stopPrank();

        airdrop(ERC20(testVault), users["wrappedStrategy"], vaultBalance);

        vm.startPrank(users["wrappedStrategy"]);
        IERC20(testVault).approve(address(yearnStakingDelegate), vaultBalance);
        yearnStakingDelegate.depositToGauge(testVault, vaultBalance);
        vm.stopPrank();

        // Check the yearn staking delegate has received the gauge tokens
        require(IERC20(testGauge).balanceOf(address(yearnStakingDelegate)) == vaultBalance, "depositToGauge failed");
        // Check the gauge has received the vault tokens
        require(IERC20(testVault).balanceOf(testGauge) == vaultBalance, "depositToGauge failed");
    }

    function testFuzz_withdrawFromGauge(uint256 vaultBalance) public {
        vm.assume(vaultBalance > 0);
        vm.startPrank(users["manager"]);
        yearnStakingDelegate.setAssociatedGauge(testVault, testGauge);
        vm.stopPrank();

        airdrop(ERC20(testVault), users["wrappedStrategy"], vaultBalance);

        vm.startPrank(users["wrappedStrategy"]);
        IERC20(testVault).approve(address(yearnStakingDelegate), vaultBalance);
        yearnStakingDelegate.depositToGauge(testVault, vaultBalance);
        vm.stopPrank();

        require(IERC20(testGauge).balanceOf(address(yearnStakingDelegate)) == vaultBalance, "depositToGauge failed");
        require(IERC20(testVault).balanceOf(testGauge) == vaultBalance, "depositToGauge failed");

        // Start withdraw process
        vm.startPrank(users["wrappedStrategy"]);
        yearnStakingDelegate.withdrawFromGauge(testVault, vaultBalance);
        vm.stopPrank();

        // Check the yearn staking delegate has released the gauge tokens
        require(IERC20(testGauge).balanceOf(address(yearnStakingDelegate)) == 0, "withdrawFromGauge failed");
        // Check the gauge has released the vault tokens
        require(IERC20(testVault).balanceOf(testGauge) == 0, "withdrawFromGauge failed");
        // Check that wrappedStrategy has received the vault tokens
        require(IERC20(testVault).balanceOf(users["wrappedStrategy"]) == vaultBalance, "withdrawFromGauge failed");
    }

    function test_harvest() public {
        vm.startPrank(users["manager"]);
        yearnStakingDelegate.setAssociatedGauge(testVault, testGauge);
        vm.stopPrank();

        // Deposit to gauge
        airdrop(ERC20(testVault), users["wrappedStrategy"], 1e18);
        vm.startPrank(users["wrappedStrategy"]);
        IERC20(testVault).approve(address(yearnStakingDelegate), 1e18);
        yearnStakingDelegate.depositToGauge(testVault, 1e18);

        vm.warp(block.timestamp + 7 days);

        // Harvest
        yearnStakingDelegate.harvest(testVault);
        vm.stopPrank();

        // Check that the vault has received the rewards
        require(IERC20(oYFI).balanceOf(users["wrappedStrategy"]) == 49_999_999_999_999_999_965_120, "harvest failed");
    }
}

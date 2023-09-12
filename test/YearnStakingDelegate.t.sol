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

        // Give alice some YFI
        airdrop(ERC20(ETH_YFI), users["alice"], 1e18);

        // Deploy vault
        testVault = deployVaultV3("USDC Test Vault", USDC, new address[](0));
        // Deploy gauge
        testGauge = deployGaugeViaFactory(testVault, users["admin"], "USDC Test Vault Gauge");

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

    function test_constructor() public {
        require(yearnStakingDelegate.yfi() == ETH_YFI, "yfi");
        require(yearnStakingDelegate.oYfi() == oYFI, "oYfi");
        require(yearnStakingDelegate.veYfi() == ETH_VE_YFI, "veYfi");
        require(yearnStakingDelegate.hasRole(yearnStakingDelegate.MANAGER_ROLE(), users["manager"]), "manager");
        require(yearnStakingDelegate.hasRole(yearnStakingDelegate.DEFAULT_ADMIN_ROLE(), users["admin"]), "admin");
    }

    function test_setAssociatedGauge() public {
        vm.prank(users["manager"]);
        yearnStakingDelegate.setAssociatedGauge(testVault, testGauge);
        require(yearnStakingDelegate.associatedGauge(testVault) == testGauge, "setAssociatedGauge failed");
    }

    function test_lockYFI() public {
        vm.startPrank(users["alice"]);
        IERC20(ETH_YFI).approve(address(yearnStakingDelegate), 1e18);
        yearnStakingDelegate.lockYfi(1e18);
        vm.stopPrank();

        require(IERC20(ETH_YFI).balanceOf(address(yearnStakingDelegate)) == 0, "lock failed");
        // Slightly less than 1e18 due to rounding
        require(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)) == 999_999_999_971_481_600, "lock failed");
    }

    function test_earlyUnlock() public {
        vm.startPrank(users["alice"]);
        IERC20(ETH_YFI).approve(address(yearnStakingDelegate), 1e18);
        yearnStakingDelegate.lockYfi(1e18);
        vm.stopPrank();

        vm.startPrank(users["admin"]);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(users["admin"]);
        vm.stopPrank();

        require(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)) == 0, "early unlock failed");
    }

    function test_earlyUnlock_revertsPerpeutalLockEnabled() public {
        vm.startPrank(users["alice"]);
        IERC20(ETH_YFI).approve(address(yearnStakingDelegate), 1e18);
        yearnStakingDelegate.lockYfi(1e18);
        vm.stopPrank();

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

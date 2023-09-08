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

contract YearnStakingDelegateTest is YearnV3BaseTest {
    using SafeERC20 for IERC20;

    YearnStakingDelegate public yearnStakingDelegate;

    function setUp() public override {
        super.setUp();

        // create admin user that will be the owner of the yearnStakingDelegate
        createUser("admin");
        // create alice who will be lock YFI via the yearnStakingDelegate
        createUser("alice");
        // create manager of the yearnStakingDelegate
        createUser("manager");

        // Give alice some YFI
        airdrop(ERC20(ETH_YFI), users["alice"], 1e18);
    }

    function test_constructor() public {
        yearnStakingDelegate = new YearnStakingDelegate(ETH_YFI, oYFI, ETH_VE_YFI, users["admin"], users["manager"]);
        require(yearnStakingDelegate.yfi() == ETH_YFI, "yfi");
        require(yearnStakingDelegate.oYfi() == oYFI, "oYfi");
        require(yearnStakingDelegate.veYfi() == ETH_VE_YFI, "veYfi");
        require(yearnStakingDelegate.hasRole(yearnStakingDelegate.MANAGER_ROLE(), users["manager"]), "manager");
        require(yearnStakingDelegate.hasRole(yearnStakingDelegate.DEFAULT_ADMIN_ROLE(), users["admin"]), "admin");
    }

    function test_lockYFI() public {
        yearnStakingDelegate = new YearnStakingDelegate(ETH_YFI, oYFI, ETH_VE_YFI, users["admin"], users["manager"]);

        vm.startPrank(users["alice"]);
        IERC20(ETH_YFI).approve(address(yearnStakingDelegate), 1e18);
        yearnStakingDelegate.lockYfi(1e18);
        vm.stopPrank();

        require(IERC20(ETH_YFI).balanceOf(address(yearnStakingDelegate)) == 0, "lock failed");
        // Slightly less than 1e18 due to rounding
        require(IERC20(ETH_VE_YFI).balanceOf(address(yearnStakingDelegate)) == 999_999_999_971_481_600, "lock failed");
    }

    function test_earlyUnlock() public {
        yearnStakingDelegate = new YearnStakingDelegate(ETH_YFI, oYFI, ETH_VE_YFI, users["admin"], users["manager"]);

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
        yearnStakingDelegate = new YearnStakingDelegate(ETH_YFI, oYFI, ETH_VE_YFI, users["admin"], users["manager"]);

        vm.startPrank(users["alice"]);
        IERC20(ETH_YFI).approve(address(yearnStakingDelegate), 1e18);
        yearnStakingDelegate.lockYfi(1e18);
        vm.stopPrank();

        vm.startPrank(users["admin"]);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockEnabled.selector));
        yearnStakingDelegate.earlyUnlock(users["admin"]);
    }
}

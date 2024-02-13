// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MiniChefV3 } from "src/rewards/MiniChefV3.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { IMiniChefV3Rewarder } from "./../src/interfaces/rewards/IMiniChefV3Rewarder.sol";
import { Errors } from "src/libraries/Errors.sol";

contract MiniChefV3_Test is BaseTest {
    MiniChefV3 public miniChef;
    ERC20Mock public rewardToken;
    ERC20Mock public lpToken;

    // Addresses
    address public alice;
    address public bob;

    function setUp() public override {
        super.setUp();

        alice = createUser("alice");
        bob = createUser("bob");

        rewardToken = new ERC20Mock();
        lpToken = new ERC20Mock();

        miniChef = new MiniChefV3(IERC20(address(rewardToken)), address(this));

        rewardToken.mint(address(this), 1e24); // 1 million tokens for rewards
    }

    function test_constructor() public {
        assertEq(address(miniChef.REWARD_TOKEN()), address(rewardToken), "rewardToken not set");
        assertTrue(miniChef.hasRole(miniChef.DEFAULT_ADMIN_ROLE(), address(this)), "admin role not set");
    }

    function test_poolLength() public {
        assertEq(miniChef.poolLength(), 0, "pool length not 0");
        for (uint160 i = 1; i <= 100; i++) {
            miniChef.add(0, IERC20(address(i)), IMiniChefV3Rewarder(address(0)));
            assertEq(miniChef.poolLength(), i, "pool length not correct");
        }
    }

    function test_pidOfLPToken() public {
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 pid = miniChef.poolLength() - 1;
        assertEq(miniChef.pidOfLPToken(IERC20(lpToken)), pid, "pid not correct");
    }

    function testFuzz_pidOfLPToken_revertWhen_InvalidLPToken(address invalidLpToken) public {
        vm.assume(address(invalidLpToken) != address(lpToken));
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        vm.expectRevert(Errors.InvalidLPToken.selector);
        miniChef.pidOfLPToken(IERC20(invalidLpToken));
    }

    function test_isLPTokenAdded() public {
        assertFalse(miniChef.isLPTokenAdded(IERC20(lpToken)), "lpToken is added");
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        assertTrue(miniChef.isLPTokenAdded(IERC20(lpToken)), "lpToken not added");
    }

    function test_addPool() public {
        uint256 allocPoint = 1000;
        IERC20 newLpToken = IERC20(address(new ERC20Mock()));
        IMiniChefV3Rewarder newRewarder = IMiniChefV3Rewarder(address(0));

        uint256 initialPoolLength = miniChef.poolLength();
        miniChef.add(allocPoint, newLpToken, newRewarder);
        uint256 newPoolLength = miniChef.poolLength();

        assertEq(newPoolLength, initialPoolLength + 1, "Pool length did not increase by 1");
        assertEq(miniChef.getPoolInfo(newPoolLength - 1).allocPoint, allocPoint, "AllocPoint not set correctly");
    }

    function test_addPool_revertWhen_LPTokenAlreadyAdded() public {
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        vm.expectRevert(Errors.LPTokenAlreadyAdded.selector);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
    }

    function test_setPool() public {
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 allocPoint = 500;
        IMiniChefV3Rewarder newRewarder = IMiniChefV3Rewarder(address(0));
        uint256 pid = miniChef.poolLength() - 1;

        miniChef.set(pid, allocPoint, newRewarder, false);

        assertEq(miniChef.getPoolInfo(pid).allocPoint, allocPoint, "AllocPoint not updated correctly");
        assertEq(address(miniChef.rewarder(pid)), address(0), "Rewarder is overwritten");

        miniChef.set(pid, allocPoint, newRewarder, true);
        assertEq(address(miniChef.rewarder(pid)), address(newRewarder), "Rewarder not updated correctly");
    }

    function test_updatePool() public {
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 pid = miniChef.poolLength() - 1;
        miniChef.updatePool(pid);
        assertEq(
            miniChef.getPoolInfo(pid).lastRewardTime, uint64(block.timestamp), "lastRewardTime not updated correctly"
        );
    }

    function test_deposit() public {
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 pid = miniChef.poolLength() - 1;
        uint256 amount = 1e18;
        lpToken.mint(alice, amount);

        vm.startPrank(alice);
        lpToken.approve(address(miniChef), amount);
        uint256 initialUserAmount = miniChef.getUserInfo(pid, alice).amount;
        miniChef.deposit(pid, amount, alice);
        uint256 newUserAmount = miniChef.getUserInfo(pid, alice).amount;

        assertEq(newUserAmount, initialUserAmount + amount, "User amount not updated correctly");
    }

    function test_withdraw() public {
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 pid = miniChef.poolLength() - 1;
        uint256 amount = 1e18;
        lpToken.mint(alice, amount);
        vm.startPrank(alice);
        lpToken.approve(address(miniChef), amount);
        miniChef.deposit(pid, amount, alice);

        uint256 initialUserAmount = miniChef.getUserInfo(pid, alice).amount;
        miniChef.withdraw(pid, amount, alice);
        uint256 newUserAmount = miniChef.getUserInfo(pid, alice).amount;

        assertEq(newUserAmount, initialUserAmount - amount, "User amount not updated correctly after withdrawal");
    }

    function test_withdrawAndHarvest() public {
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        rewardToken.approve(address(miniChef), 10e18);
        miniChef.commitReward(10e18);
        miniChef.setRewardPerSecond(1e15);
        uint256 pid = miniChef.poolLength() - 1;
        uint256 amount = 1e18;
        lpToken.mint(alice, amount);
        vm.startPrank(alice);
        lpToken.approve(address(miniChef), amount);
        miniChef.deposit(pid, amount, alice);

        // Fast forward to accrue rewards
        vm.warp(block.timestamp + 1 days);

        uint256 initialUserAmount = miniChef.getUserInfo(pid, alice).amount;
        uint256 initialRewardBalance = rewardToken.balanceOf(alice);
        miniChef.withdrawAndHarvest(pid, amount, alice);
        uint256 newUserAmount = miniChef.getUserInfo(pid, alice).amount;
        uint256 newRewardBalance = rewardToken.balanceOf(alice);

        assertEq(
            newUserAmount, initialUserAmount - amount, "User amount not updated correctly after withdrawAndHarvest"
        );
        assertTrue(newRewardBalance > initialRewardBalance, "Rewards not harvested correctly after withdrawAndHarvest");
    }

    function test_emergencyWithdraw() public {
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 pid = miniChef.poolLength() - 1;
        uint256 amount = 1e18;
        lpToken.mint(alice, amount);
        vm.startPrank(alice);
        lpToken.approve(address(miniChef), amount);
        miniChef.deposit(pid, amount, alice);
        assertEq(lpToken.balanceOf(alice), 0, "LP tokens not transferred to contract");
        uint256 initialUserAmount = miniChef.getUserInfo(pid, alice).amount;
        assertEq(initialUserAmount, amount, "User amount not set correctly");
        miniChef.emergencyWithdraw(pid, alice);
        uint256 newUserAmount = miniChef.getUserInfo(pid, alice).amount;

        assertEq(newUserAmount, 0, "User amount not set to 0 after emergency withdrawal");
        assertEq(lpToken.balanceOf(alice), amount, "LP tokens not returned to user after emergency withdrawal");
    }

    function test_harvest() public {
        miniChef.setRewardPerSecond(1e15);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        rewardToken.approve(address(miniChef), 10e18);
        miniChef.commitReward(10e18);
        uint256 pid = miniChef.poolLength() - 1;
        uint256 amount = 1e18;
        lpToken.mint(alice, amount);
        vm.startPrank(alice);

        lpToken.approve(address(miniChef), amount);
        miniChef.deposit(pid, amount, alice);

        // Fast forward to accrue rewards
        vm.warp(block.timestamp + 1 days);

        uint256 initialRewardBalance = rewardToken.balanceOf(alice);
        miniChef.harvest(pid, alice);
        uint256 newRewardBalance = rewardToken.balanceOf(alice);

        assertTrue(newRewardBalance > initialRewardBalance, "Rewards not harvested correctly");
    }

    function test_rescue() public {
        miniChef.setRewardPerSecond(1e15);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        rewardToken.approve(address(miniChef), 10e18);
        miniChef.commitReward(10e18);

        lpToken.mint(address(miniChef), 1e18);
        assertEq(lpToken.balanceOf(address(this)), 0, "LP tokens not rescued correctly");
        miniChef.rescue(lpToken, address(this), 1e18);
        assertEq(lpToken.balanceOf(address(this)), 1e18, "LP tokens not rescued correctly");
    }

    function test_rescue_revertWhen_InsufficientBalance() public {
        miniChef.setRewardPerSecond(1e15);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        rewardToken.approve(address(miniChef), 10e18);
        miniChef.commitReward(10e18);

        lpToken.mint(address(miniChef), 1e18);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        miniChef.rescue(lpToken, address(this), 2e18);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MiniChefV3 } from "src/rewards/MiniChefV3.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { IMiniChefV3Rewarder } from "src/interfaces/rewards/IMiniChefV3Rewarder.sol";
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

    function test_add() public {
        uint256 allocPoint = 1000;
        IERC20 newLpToken = IERC20(address(new ERC20Mock()));
        IMiniChefV3Rewarder newRewarder = IMiniChefV3Rewarder(address(0));

        uint256 initialPoolLength = miniChef.poolLength();
        miniChef.add(allocPoint, newLpToken, newRewarder);
        uint256 newPoolLength = miniChef.poolLength();

        assertEq(newPoolLength, initialPoolLength + 1, "Pool length did not increase by 1");
        assertEq(miniChef.getPoolInfo(newPoolLength - 1).allocPoint, allocPoint, "AllocPoint not set correctly");
    }

    function test_add_revertWhen_CallerIsNotAdmin() public {
        vm.expectRevert(_formatAccessControlError(bob, miniChef.DEFAULT_ADMIN_ROLE()));
        vm.startPrank(bob);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
    }

    function test_add_revertWhen_LPTokenAlreadyAdded() public {
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        vm.expectRevert(Errors.LPTokenAlreadyAdded.selector);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
    }

    function test_set() public {
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 allocPoint = 500;
        IMiniChefV3Rewarder newRewarder = IMiniChefV3Rewarder(address(0));
        uint256 pid = miniChef.poolLength() - 1;

        miniChef.set(pid, allocPoint, newRewarder, false);

        assertEq(miniChef.getPoolInfo(pid).allocPoint, allocPoint, "AllocPoint not updated correctly");
        assertEq(address(miniChef.rewarder(pid)), address(0), "Rewarder is overwritten");

        miniChef.set(pid, allocPoint, newRewarder, true);
        assertEq(address(miniChef.rewarder(pid)), address(newRewarder), "Rewarder is not overwritten");
    }

    function test_set_revertWhen_CallerIsNotAdmin() public {
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 pid = miniChef.poolLength() - 1;
        vm.expectRevert(_formatAccessControlError(bob, miniChef.DEFAULT_ADMIN_ROLE()));
        vm.startPrank(bob);
        miniChef.set(pid, 1000, IMiniChefV3Rewarder(address(0)), false);
    }

    function testFuzz_setRewardPerSecond(uint256 rate) public {
        miniChef.setRewardPerSecond(rate);
        assertEq(miniChef.rewardPerSecond(), rate, "Reward per second not set correctly");
    }

    function testFuzz_setRewardPerSecond_revertWhen_CallerIsNotAdmin(uint256 rate) public {
        vm.expectRevert(_formatAccessControlError(bob, miniChef.DEFAULT_ADMIN_ROLE()));
        vm.startPrank(bob);
        miniChef.setRewardPerSecond(rate);
    }

    function testFuzz_commitReward(uint256 rewardCommitment) public {
        rewardToken.mint(address(this), rewardCommitment);
        rewardToken.approve(address(miniChef), rewardCommitment);
        miniChef.commitReward(rewardCommitment);
        assertEq(rewardToken.balanceOf(address(miniChef)), rewardCommitment, "Reward commitment not set correctly");
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

    function test_deposit_passWhen_RewarderIsNotZero() public {
        IMiniChefV3Rewarder rewarder = IMiniChefV3Rewarder(address(0xbeef));
        miniChef.add(1000, lpToken, rewarder);
        uint256 pid = miniChef.poolLength() - 1;
        uint256 amount = 1e18;
        lpToken.mint(alice, amount);

        vm.startPrank(alice);
        lpToken.approve(address(miniChef), amount);
        vm.mockCall(address(rewarder), abi.encodeWithSelector(rewarder.onReward.selector), "");
        vm.expectCall(
            address(rewarder), abi.encodeWithSelector(rewarder.onReward.selector, pid, alice, alice, 0, amount)
        );
        miniChef.deposit(pid, amount, alice);
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

    function test_withdraw_passWhen_RewarderIsNotZero() public {
        IMiniChefV3Rewarder rewarder = IMiniChefV3Rewarder(address(0xbeef));
        vm.mockCall(address(rewarder), abi.encodeWithSelector(rewarder.onReward.selector), "");

        miniChef.add(1000, lpToken, rewarder);
        uint256 pid = miniChef.poolLength() - 1;
        uint256 amount = 1e18;
        lpToken.mint(alice, amount);
        vm.startPrank(alice);
        lpToken.approve(address(miniChef), amount);
        miniChef.deposit(pid, amount, alice);
        vm.expectCall(address(rewarder), abi.encodeWithSelector(rewarder.onReward.selector, pid, alice, alice, 0, 0));
        miniChef.withdraw(pid, amount, alice);
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

    function test_emergencyWithdraw_passWhen_RewarderIsNotZero() public {
        IMiniChefV3Rewarder rewarder = IMiniChefV3Rewarder(address(0xbeef));
        vm.mockCall(address(rewarder), abi.encodeWithSelector(rewarder.onReward.selector), "");

        miniChef.add(1000, lpToken, rewarder);
        uint256 pid = miniChef.poolLength() - 1;
        uint256 amount = 1e18;
        lpToken.mint(alice, amount);
        vm.startPrank(alice);
        lpToken.approve(address(miniChef), amount);
        miniChef.deposit(pid, amount, alice);
        vm.expectCall(address(rewarder), abi.encodeWithSelector(rewarder.onReward.selector, pid, alice, alice, 0, 0));
        miniChef.emergencyWithdraw(pid, alice);
    }

    function test_harvest() public {
        miniChef.setRewardPerSecond(1e15);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 rewardCommitment = 10e25;
        rewardToken.mint(address(this), rewardCommitment);
        rewardToken.approve(address(miniChef), rewardCommitment);
        miniChef.commitReward(rewardCommitment);
        uint256 pid = miniChef.poolLength() - 1;
        uint256 amount = 1e18;
        lpToken.mint(alice, amount);

        vm.startPrank(alice);
        lpToken.approve(address(miniChef), amount);
        miniChef.deposit(pid, amount, alice);

        // Fast forward to accrue rewards
        vm.warp(block.timestamp + 1 days);

        uint256 initialRewardBalance = rewardToken.balanceOf(alice);
        uint256 pendingReward = miniChef.pendingReward(pid, alice);
        uint256 expectedTotalReward = miniChef.rewardPerSecond() * 1 days;
        assertEq(pendingReward, expectedTotalReward, "Pending rewards not accrued correctly");

        miniChef.harvest(pid, alice);
        uint256 newRewardBalance = rewardToken.balanceOf(alice);

        assertGt(newRewardBalance, initialRewardBalance, "Rewards not harvested correctly");
        assertEq(newRewardBalance - initialRewardBalance, expectedTotalReward, "Rewards not accrued correctly");
        assertEq(miniChef.pendingReward(pid, alice), 0, "Pending rewards not set to 0 after harvest");
    }

    function test_harvest_passWhen_UnpaidRewards() public {
        miniChef.setRewardPerSecond(1e15);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 rewardCommitment = 1e18; // Small reward commitment
        rewardToken.mint(address(this), rewardCommitment);
        rewardToken.approve(address(miniChef), rewardCommitment);
        miniChef.commitReward(rewardCommitment);
        uint256 pid = miniChef.poolLength() - 1;
        uint256 amount = 1e18;
        lpToken.mint(alice, amount);

        vm.startPrank(alice);
        lpToken.approve(address(miniChef), amount);
        miniChef.deposit(pid, amount, alice);

        vm.warp(block.timestamp + 1 days);
        uint256 initialRewardBalance = rewardToken.balanceOf(alice);
        miniChef.harvest(pid, alice);
        uint256 newRewardBalance = rewardToken.balanceOf(alice);

        uint256 expectedTotalReward = miniChef.rewardPerSecond() * 1 days;

        assertGt(newRewardBalance, initialRewardBalance, "Rewards not harvested correctly");
        assertEq(newRewardBalance - initialRewardBalance, rewardCommitment, "Could not harvest partial rewards");
        assertGt(miniChef.pendingReward(pid, alice), 0, "Pending rewards does not include unpaid rewards");
        assertEq(
            miniChef.pendingReward(pid, alice),
            expectedTotalReward - rewardCommitment,
            "Pending rewards does not include unpaid rewards"
        );
        assertEq(
            miniChef.getUserInfo(pid, alice).unpaidRewards,
            expectedTotalReward - rewardCommitment,
            "Unpaid rewards not updated correctly"
        );

        vm.stopPrank();
        rewardToken.mint(address(this), expectedTotalReward);
        rewardToken.approve(address(miniChef), expectedTotalReward);
        miniChef.commitReward(expectedTotalReward);

        vm.startPrank(alice);
        miniChef.harvest(pid, alice);
        newRewardBalance = rewardToken.balanceOf(alice);
        assertEq(newRewardBalance - initialRewardBalance, expectedTotalReward, "Rewards not harvested correctly");
        assertEq(miniChef.pendingReward(pid, alice), 0, "Pending rewards not set to 0 after harvest");
        assertEq(miniChef.getUserInfo(pid, alice).unpaidRewards, 0, "Unpaid rewards not set to 0 after harvest");
    }

    function test_harvest_passWhen_RewarderIsNotZero() public {
        IMiniChefV3Rewarder rewarder = IMiniChefV3Rewarder(address(0xbeef));
        vm.mockCall(address(rewarder), abi.encodeWithSelector(rewarder.onReward.selector), "");
        miniChef.add(1000, lpToken, rewarder);
        miniChef.setRewardPerSecond(1e15);
        uint256 rewardCommitment = 1e24;
        rewardToken.mint(address(this), rewardCommitment);
        rewardToken.approve(address(miniChef), rewardCommitment);
        miniChef.commitReward(rewardCommitment);
        uint256 pid = miniChef.poolLength() - 1;
        uint256 amount = 1e18;
        lpToken.mint(alice, amount);
        vm.startPrank(alice);
        lpToken.approve(address(miniChef), amount);
        miniChef.deposit(pid, amount, alice);

        // Fast forward to accrue rewards
        vm.warp(block.timestamp + 1 days);
        uint256 expectedTotalReward = miniChef.rewardPerSecond() * 1 days;

        vm.expectCall(
            address(rewarder),
            abi.encodeWithSelector(rewarder.onReward.selector, pid, alice, alice, expectedTotalReward, amount)
        );
        miniChef.harvest(pid, alice);
    }

    function test_rescue() public {
        miniChef.setRewardPerSecond(1e15);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 rewardCommitment = 10e18;
        rewardToken.mint(address(this), rewardCommitment);
        rewardToken.approve(address(miniChef), rewardCommitment);
        miniChef.commitReward(rewardCommitment);

        lpToken.mint(address(miniChef), 1e18);
        assertEq(lpToken.balanceOf(address(this)), 0, "LP tokens not rescued correctly");
        miniChef.rescue(lpToken, address(this), 1e18);
        assertEq(lpToken.balanceOf(address(this)), 1e18, "LP tokens not rescued correctly");
    }

    function testFuzz_rescue_revertWhen_CallerIsNotAdmin(IERC20 token, address to, uint256 amount) public {
        vm.expectRevert(_formatAccessControlError(bob, miniChef.DEFAULT_ADMIN_ROLE()));
        vm.startPrank(bob);
        miniChef.rescue(token, to, amount);
    }

    function testFuzz_rescue_passWhen_RescueLPToken(uint256 userDepositAmount, uint256 rescueAmount) public {
        userDepositAmount = bound(userDepositAmount, 1, type(uint256).max - 1);
        rescueAmount = bound(rescueAmount, 1, type(uint256).max - userDepositAmount);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));

        lpToken.mint(alice, userDepositAmount);
        vm.startPrank(alice);
        lpToken.approve(address(miniChef), userDepositAmount);
        miniChef.deposit(0, userDepositAmount, alice);
        vm.stopPrank();

        lpToken.mint(address(miniChef), rescueAmount);
        miniChef.rescue(lpToken, address(this), rescueAmount);
        assertEq(lpToken.balanceOf(address(this)), rescueAmount, "LP tokens not rescued correctly");
        assertEq(lpToken.balanceOf(address(miniChef)), userDepositAmount, "User deposit was affected");
    }

    function testFuzz_rescue_revertWhen_InsufficientBalance_RewardToken(
        uint256 rewardCommitment,
        uint256 rescueAmount
    )
        public
    {
        rewardCommitment = bound(rewardCommitment, 1, type(uint128).max - 1);
        rescueAmount = bound(rescueAmount, 1, type(uint256).max - rewardCommitment - 1);
        miniChef.setRewardPerSecond(1e15);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        rewardToken.mint(address(this), rewardCommitment);
        rewardToken.approve(address(miniChef), rewardCommitment);
        miniChef.commitReward(rewardCommitment);

        rewardToken.mint(address(miniChef), rescueAmount);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        miniChef.rescue(rewardToken, address(this), rescueAmount + 1);
    }

    function testFuzz_rescue_revertWhen_InsufficientBalance_RewardTokenIsLPToken(
        uint256 rewardCommitment,
        uint256 userDepositAmount,
        uint256 rescueAmount
    )
        public
    {
        rewardCommitment = bound(rewardCommitment, 1, type(uint128).max);
        userDepositAmount = bound(userDepositAmount, 1, type(uint128).max);
        rescueAmount = bound(rescueAmount, 1, type(uint256).max - rewardCommitment - rewardCommitment - 1);
        miniChef.setRewardPerSecond(1e15);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        rewardToken.mint(address(this), rewardCommitment);
        rewardToken.approve(address(miniChef), rewardCommitment);
        miniChef.commitReward(rewardCommitment);

        lpToken.mint(alice, userDepositAmount);
        vm.startPrank(alice);
        lpToken.approve(address(miniChef), userDepositAmount);
        miniChef.deposit(0, userDepositAmount, alice);
        vm.stopPrank();

        rewardToken.mint(address(miniChef), rescueAmount);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        miniChef.rescue(rewardToken, address(this), rescueAmount + 1);
    }

    function test_rescue_revertWhen_InsufficientBalance() public {
        miniChef.setRewardPerSecond(1e15);
        miniChef.add(1000, lpToken, IMiniChefV3Rewarder(address(0)));
        uint256 rewardCommitment = 10e18;
        rewardToken.mint(address(this), rewardCommitment);
        rewardToken.approve(address(miniChef), rewardCommitment);
        miniChef.commitReward(rewardCommitment);

        rewardToken.mint(address(miniChef), 1e18);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        miniChef.rescue(rewardToken, address(this), 2e18);
    }

    function test_rescue_passWhen_RandomToken() public {
        ERC20Mock randomToken = new ERC20Mock();
        randomToken.mint(address(miniChef), 1e18);
        miniChef.rescue(IERC20(randomToken), address(this), 1e18);
        assertEq(randomToken.balanceOf(address(this)), 1e18, "Random token not rescued correctly");
        assertEq(randomToken.balanceOf(address(miniChef)), 0, "Random token not transferred correctly");
    }
}
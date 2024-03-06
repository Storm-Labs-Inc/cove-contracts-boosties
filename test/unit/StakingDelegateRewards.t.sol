// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { StakingDelegateRewards } from "src/StakingDelegateRewards.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingDelegateRewards_Test is BaseTest {
    address public yearnStakingDelegate;
    address public rewardToken;
    address public stakingToken;
    StakingDelegateRewards public stakingDelegateRewards;

    address public admin;
    address public alice;
    address public aliceReceiver;
    address public bob;
    address public rewardDistributor;

    uint256 public constant REWARD_AMOUNT = 1000e18;

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        alice = createUser("alice");
        aliceReceiver = createUser("aliceReceiver");
        bob = createUser("bob");
        rewardDistributor = createUser("rewardDistributor");

        yearnStakingDelegate = address(new MockYearnStakingDelegate());
        rewardToken = address(new ERC20Mock());
        stakingToken = address(new ERC20Mock());

        vm.prank(admin);
        stakingDelegateRewards = new StakingDelegateRewards(rewardToken, yearnStakingDelegate, admin, admin);
    }

    function _calculateEarned(
        uint256 depositAmount,
        uint256 totalSupply,
        uint256 rewardRate,
        uint256 timeSpentLocked
    )
        internal
        pure
        returns (uint256)
    {
        return (timeSpentLocked * rewardRate * 1e18 / totalSupply) * depositAmount / 1e18;
    }

    function test_constructor() public {
        assertEq(stakingDelegateRewards.rewardToken(), rewardToken);
        assertEq(stakingDelegateRewards.stakingDelegate(), yearnStakingDelegate);
        assertTrue(stakingDelegateRewards.hasRole(stakingDelegateRewards.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(stakingDelegateRewards.hasRole(_TIMELOCK_ROLE, admin));
    }

    function testFuzz_constructor(
        address rewardToken_,
        address stakingDelegate_,
        address deployer,
        address nonDeployer
    )
        public
    {
        vm.assume(rewardToken_ != address(0));
        vm.assume(stakingDelegate_ != address(0));
        vm.assume(deployer != address(0));
        vm.assume(nonDeployer != deployer);

        vm.prank(deployer);
        stakingDelegateRewards = new StakingDelegateRewards(rewardToken_, stakingDelegate_, deployer, deployer);
        assertEq(stakingDelegateRewards.rewardToken(), rewardToken_);
        assertEq(stakingDelegateRewards.stakingDelegate(), stakingDelegate_);
        assertEq(stakingDelegateRewards.hasRole(stakingDelegateRewards.DEFAULT_ADMIN_ROLE(), deployer), true);
        assertEq(stakingDelegateRewards.hasRole(stakingDelegateRewards.DEFAULT_ADMIN_ROLE(), nonDeployer), false);
    }

    function test_constructor_revertWhen_ZeroAddress() public {
        // Check for zero addresses
        address zeroAddress = address(0);
        address nonZeroAddress = address(1);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        new StakingDelegateRewards(zeroAddress, nonZeroAddress, admin, admin);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        new StakingDelegateRewards(nonZeroAddress, zeroAddress, admin, admin);
    }

    function test_addStakingToken() public {
        assertEq(stakingDelegateRewards.rewardDistributors(stakingToken), address(0));
        assertEq(stakingDelegateRewards.rewardsDuration(stakingToken), 0);

        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);
        assertEq(stakingDelegateRewards.rewardDistributors(stakingToken), rewardDistributor);
        assertEq(stakingDelegateRewards.rewardsDuration(stakingToken), 7 days);
    }

    function test_addStakingToken_revertWhen_CallerIsNotStakingDelegate() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyStakingDelegateCanAddStakingToken.selector));
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);
    }

    function test_addStakingToken_revertWhen_StakingTokenAlreadyAdded() public {
        vm.startPrank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        vm.expectRevert(abi.encodeWithSelector(Errors.StakingTokenAlreadyAdded.selector));
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);
        vm.stopPrank();
    }

    function test_notifyRewardAmount() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        assertEq(stakingDelegateRewards.rewardRate(stakingToken), uint256(REWARD_AMOUNT) / 7 days);
        assertEq(stakingDelegateRewards.lastUpdateTime(stakingToken), block.timestamp);
        assertEq(stakingDelegateRewards.periodFinish(stakingToken), block.timestamp + 7 days);
        assertEq(IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)), REWARD_AMOUNT);
    }

    function test_notifyRewardAmount_passWhen_RemainingRewardExists() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        assertEq(stakingDelegateRewards.rewardRate(stakingToken), uint256(REWARD_AMOUNT) / 7 days);
        assertEq(stakingDelegateRewards.lastUpdateTime(stakingToken), block.timestamp);
        assertEq(stakingDelegateRewards.periodFinish(stakingToken), block.timestamp + 7 days);
        assertEq(IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)), REWARD_AMOUNT);
        vm.warp(block.timestamp + 4 days);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        uint256 expectedRewardRate = (uint256(REWARD_AMOUNT) * 3 days / 7 days + uint256(REWARD_AMOUNT)) / 7 days;
        assertEq(stakingDelegateRewards.rewardRate(stakingToken), expectedRewardRate);
        assertEq(stakingDelegateRewards.lastUpdateTime(stakingToken), block.timestamp);
        assertEq(stakingDelegateRewards.periodFinish(stakingToken), block.timestamp + 7 days);

        assertEq(IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)), 2000e18);
    }

    function test_notifyRewardAmount_revertWhen_CallerIsNotRewardDistributor() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyRewardDistributorCanNotifyRewardAmount.selector));
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
    }

    function testFuzz_notifyRewardAmount(uint256 reward) public {
        vm.assume(reward != 0);
        vm.assume(reward >= 7 days);
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        airdrop(IERC20(rewardToken), rewardDistributor, reward);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), reward);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, reward);
        vm.stopPrank();

        assertEq(stakingDelegateRewards.rewardRate(stakingToken), uint256(reward) / 7 days);
        assertEq(stakingDelegateRewards.lastUpdateTime(stakingToken), block.timestamp);
        assertEq(stakingDelegateRewards.periodFinish(stakingToken), block.timestamp + 7 days);
        assertEq(IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)), reward);
    }

    function testFuzz_notifyRewardAmount_revertWhen_RewardRateTooLow(uint256 reward) public {
        vm.assume(reward < 7 days);
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        airdrop(IERC20(rewardToken), rewardDistributor, reward);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), reward);
        vm.expectRevert(abi.encodeWithSelector(Errors.RewardRateTooLow.selector));
        stakingDelegateRewards.notifyRewardAmount(stakingToken, reward);
        vm.stopPrank();
    }

    function test_updateUserBalance() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.updateUserBalance(address(alice), stakingToken, 1e18);
        assertEq(stakingDelegateRewards.totalSupply(stakingToken), 1e18);
        assertEq(stakingDelegateRewards.balanceOf(address(alice), stakingToken), 1e18);
    }

    function test_updateUserBalance_revertWhen_CallerIsNotStakingDelegate() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyStakingDelegateCanUpdateUserBalance.selector));
        stakingDelegateRewards.updateUserBalance(stakingToken, address(alice), 1e18);
    }

    function test_recoverERC20() public {
        address token = address(new ERC20Mock());
        uint256 amount = 1e18;
        airdrop(IERC20(token), address(stakingDelegateRewards), amount);
        assertEq(IERC20(token).balanceOf(address(stakingDelegateRewards)), amount);

        vm.prank(admin);
        stakingDelegateRewards.recoverERC20(token, admin, amount);
        assertEq(IERC20(token).balanceOf(address(stakingDelegateRewards)), 0);
        assertEq(IERC20(token).balanceOf(admin), amount);
    }

    function test_recoverERC20_revertWhen_RescueRewardToken_RescueNotAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.RescueNotAllowed.selector));
        vm.prank(admin);
        stakingDelegateRewards.recoverERC20(rewardToken, admin, 1e18);
    }

    function test_recoverERC20_revertWhen_RescueStakingToken_RescueNotAllowed() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        vm.expectRevert(abi.encodeWithSelector(Errors.RescueNotAllowed.selector));
        vm.prank(admin);
        stakingDelegateRewards.recoverERC20(stakingToken, admin, 1e18);
    }

    function test_recoverERC20_revertWhen_CallerIsNotAdmin() public {
        vm.expectRevert(_formatAccessControlError(alice, stakingDelegateRewards.DEFAULT_ADMIN_ROLE()));
        vm.prank(alice);
        stakingDelegateRewards.recoverERC20(rewardToken, alice, 1e18);
    }

    function test_setRewardsDuration() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        vm.prank(admin);
        stakingDelegateRewards.setRewardsDuration(stakingToken, 1 days);
        assertEq(stakingDelegateRewards.rewardsDuration(stakingToken), 1 days);
    }

    function test_setRewardsDuration_revertWhen_CallerIsNotTimelock() public {
        vm.expectRevert(_formatAccessControlError(alice, _TIMELOCK_ROLE));
        vm.prank(alice);
        stakingDelegateRewards.setRewardsDuration(stakingToken, 1 days);
    }

    function test_setRewardsDuration_revertWhen_PreviousRewardsPeriodNotCompleted() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.PreviousRewardsPeriodNotCompleted.selector));
        stakingDelegateRewards.setRewardsDuration(stakingToken, 1 days);
    }

    function test_setRewardDuration_revertWhen_StakingTokenNotAdded() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.StakingTokenNotAdded.selector));
        stakingDelegateRewards.setRewardsDuration(stakingToken, 1 days);
    }

    function test_setRewardDuration_revertWhen_RewardsDurationCannotBeZero() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.RewardDurationCannotBeZero.selector));
        stakingDelegateRewards.setRewardsDuration(stakingToken, 0);
    }

    function test_getRewardForDuration() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        assertEq(stakingDelegateRewards.getRewardForDuration(stakingToken), 0);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        assertEq(stakingDelegateRewards.getRewardForDuration(stakingToken), REWARD_AMOUNT / 7 days * 7 days);
    }

    function test_lastTimeRewardApplicable() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        assertEq(stakingDelegateRewards.lastTimeRewardApplicable(stakingToken), 0);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();
        uint256 startBlockTimestamp = block.timestamp;

        assertEq(stakingDelegateRewards.lastTimeRewardApplicable(stakingToken), block.timestamp);
        vm.warp(block.timestamp + 4 days);
        assertEq(stakingDelegateRewards.lastTimeRewardApplicable(stakingToken), block.timestamp);
        vm.warp(block.timestamp + 10 days);
        assertEq(stakingDelegateRewards.lastTimeRewardApplicable(stakingToken), startBlockTimestamp + 7 days);
    }

    function test_rewardPerToken() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        assertEq(stakingDelegateRewards.rewardPerToken(stakingToken), 0);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        assertEq(stakingDelegateRewards.rewardPerToken(stakingToken), 0);

        vm.prank(yearnStakingDelegate);
        uint256 depositAmount = 100e18;
        stakingDelegateRewards.updateUserBalance(address(alice), stakingToken, depositAmount);
        assertEq(stakingDelegateRewards.rewardPerToken(stakingToken), 0);
        uint256 lastUpdateTime = block.timestamp;

        vm.warp(block.timestamp + 4 days);
        assertEq(
            stakingDelegateRewards.rewardPerToken(stakingToken),
            (block.timestamp - lastUpdateTime) * (REWARD_AMOUNT / 7 days) * 1e18 / depositAmount
        );
    }

    function test_earned() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        assertEq(stakingDelegateRewards.earned(address(alice), stakingToken), 0);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        assertEq(stakingDelegateRewards.earned(address(alice), stakingToken), 0);

        vm.prank(yearnStakingDelegate);
        uint256 depositAmount = 100e18;
        stakingDelegateRewards.updateUserBalance(address(alice), stakingToken, depositAmount);
        uint256 totalSupply = 100e18;
        assertEq(stakingDelegateRewards.earned(address(alice), stakingToken), 0);
        uint256 lastUpdateTime = block.timestamp;

        vm.warp(block.timestamp + 4 days);
        assertEq(
            stakingDelegateRewards.earned(address(alice), stakingToken),
            _calculateEarned(depositAmount, totalSupply, REWARD_AMOUNT / 7 days, block.timestamp - lastUpdateTime)
        );

        vm.warp(block.timestamp + 3 days);
        assertEq(stakingDelegateRewards.earned(address(alice), stakingToken), REWARD_AMOUNT / 7 days * 7 days);

        vm.warp(block.timestamp + 10 days);
        assertEq(stakingDelegateRewards.earned(address(alice), stakingToken), REWARD_AMOUNT / 7 days * 7 days);
    }

    function test_earned_passWhen_MultipleUsers() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        assertEq(stakingDelegateRewards.earned(address(alice), stakingToken), 0);
        assertEq(stakingDelegateRewards.earned(address(bob), stakingToken), 0);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        assertEq(stakingDelegateRewards.earned(address(alice), stakingToken), 0);
        assertEq(stakingDelegateRewards.earned(address(bob), stakingToken), 0);

        uint256 aliceDepositAmount = 100e18;
        uint256 bobDepositAmount = 200e18;

        vm.startPrank(yearnStakingDelegate);
        stakingDelegateRewards.updateUserBalance(address(alice), stakingToken, aliceDepositAmount);
        stakingDelegateRewards.updateUserBalance(address(bob), stakingToken, bobDepositAmount);
        vm.stopPrank();

        uint256 totalSupply = aliceDepositAmount + bobDepositAmount;
        assertEq(stakingDelegateRewards.earned(address(alice), stakingToken), 0);
        assertEq(stakingDelegateRewards.earned(address(bob), stakingToken), 0);
        uint256 lastUpdateTime = block.timestamp;

        vm.warp(block.timestamp + 4 days);
        assertEq(
            stakingDelegateRewards.earned(address(alice), stakingToken),
            _calculateEarned(aliceDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, block.timestamp - lastUpdateTime)
        );
        assertEq(
            stakingDelegateRewards.earned(address(bob), stakingToken),
            _calculateEarned(bobDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, block.timestamp - lastUpdateTime)
        );

        vm.warp(block.timestamp + 3 days);
        assertEq(
            stakingDelegateRewards.earned(address(alice), stakingToken),
            _calculateEarned(aliceDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );
        assertEq(
            stakingDelegateRewards.earned(address(bob), stakingToken),
            _calculateEarned(bobDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );

        vm.warp(block.timestamp + 10 days);
        assertEq(
            stakingDelegateRewards.earned(address(alice), stakingToken),
            _calculateEarned(aliceDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );
        assertEq(
            stakingDelegateRewards.earned(address(bob), stakingToken),
            _calculateEarned(bobDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );
    }

    function testFuzz_setRewardReceiver(address receiver) public {
        vm.prank(alice);
        stakingDelegateRewards.setRewardReceiver(receiver);
        assertEq(stakingDelegateRewards.rewardReceiver(alice), receiver);
    }

    function test_getReward() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        assertEq(IERC20(rewardToken).balanceOf(address(alice)), 0);
        assertEq(IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)), 0);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        vm.prank(yearnStakingDelegate);
        uint256 depositAmount = 100e18;
        uint256 totalSupply = 100e18;
        stakingDelegateRewards.updateUserBalance(address(alice), stakingToken, depositAmount);
        stakingDelegateRewards.getReward(address(alice), stakingToken);
        assertEq(IERC20(rewardToken).balanceOf(address(alice)), 0);
        uint256 lastUpdateTime = block.timestamp;

        vm.warp(block.timestamp + 4 days);
        stakingDelegateRewards.getReward(address(alice), stakingToken);
        assertEq(
            IERC20(rewardToken).balanceOf(address(alice)),
            _calculateEarned(depositAmount, totalSupply, REWARD_AMOUNT / 7 days, block.timestamp - lastUpdateTime)
        );

        vm.warp(block.timestamp + 3 days);
        stakingDelegateRewards.getReward(address(alice), stakingToken);
        assertEq(
            IERC20(rewardToken).balanceOf(address(alice)),
            _calculateEarned(depositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );

        vm.warp(block.timestamp + 10 days);
        stakingDelegateRewards.getReward(address(alice), stakingToken);

        assertEq(
            IERC20(rewardToken).balanceOf(address(alice)),
            _calculateEarned(depositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );
        assertEq(
            IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)),
            REWARD_AMOUNT - IERC20(rewardToken).balanceOf(address(alice))
        );
    }

    function test_getReward_passWhen_RewardReceiverIsSet() public {
        vm.prank(alice);
        stakingDelegateRewards.setRewardReceiver(aliceReceiver);

        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        assertEq(IERC20(rewardToken).balanceOf(alice), 0);
        assertEq(IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)), 0);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        uint256 depositAmount = 100e18;
        uint256 totalSupply = 100e18;
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.updateUserBalance(alice, stakingToken, depositAmount);
        stakingDelegateRewards.getReward(alice, stakingToken);
        assertEq(IERC20(rewardToken).balanceOf(alice), 0);
        assertEq(IERC20(rewardToken).balanceOf(aliceReceiver), 0);
        uint256 lastUpdateTime = block.timestamp;

        vm.warp(block.timestamp + 4 days);
        stakingDelegateRewards.getReward(alice, stakingToken);
        // Check that receiver got the rewards instead of the user
        assertEq(
            IERC20(rewardToken).balanceOf(aliceReceiver),
            _calculateEarned(depositAmount, totalSupply, REWARD_AMOUNT / 7 days, block.timestamp - lastUpdateTime)
        );
        assertEq(IERC20(rewardToken).balanceOf(alice), 0);

        vm.warp(block.timestamp + 3 days);
        stakingDelegateRewards.getReward(alice, stakingToken);
        // Check that receiver got the rewards instead of the user
        assertEq(
            IERC20(rewardToken).balanceOf(aliceReceiver),
            _calculateEarned(depositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );
        assertEq(IERC20(rewardToken).balanceOf(alice), 0);

        vm.warp(block.timestamp + 10 days);
        stakingDelegateRewards.getReward(address(alice), stakingToken);

        assertEq(
            IERC20(rewardToken).balanceOf(aliceReceiver),
            _calculateEarned(depositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );
        assertEq(
            IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)),
            REWARD_AMOUNT - IERC20(rewardToken).balanceOf(address(aliceReceiver))
        );
    }

    function test_getReward_passWhen_MultipleUsers() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        assertEq(IERC20(rewardToken).balanceOf(address(alice)), 0);
        assertEq(IERC20(rewardToken).balanceOf(address(bob)), 0);
        assertEq(IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)), 0);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        uint256 aliceDepositAmount = 100e18;
        uint256 bobDepositAmount = 200e18;
        uint256 totalSupply = aliceDepositAmount + bobDepositAmount;
        vm.startPrank(yearnStakingDelegate);
        stakingDelegateRewards.updateUserBalance(address(alice), stakingToken, aliceDepositAmount);
        stakingDelegateRewards.updateUserBalance(address(bob), stakingToken, bobDepositAmount);
        vm.stopPrank();
        stakingDelegateRewards.getReward(address(alice), stakingToken);
        stakingDelegateRewards.getReward(address(bob), stakingToken);
        assertEq(IERC20(rewardToken).balanceOf(address(alice)), 0);
        assertEq(IERC20(rewardToken).balanceOf(address(bob)), 0);
        uint256 lastUpdateTime = block.timestamp;

        vm.warp(block.timestamp + 4 days);
        stakingDelegateRewards.getReward(address(alice), stakingToken);
        stakingDelegateRewards.getReward(address(bob), stakingToken);
        assertEq(
            IERC20(rewardToken).balanceOf(address(alice)),
            _calculateEarned(aliceDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, block.timestamp - lastUpdateTime)
        );
        assertEq(
            IERC20(rewardToken).balanceOf(address(bob)),
            _calculateEarned(bobDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, block.timestamp - lastUpdateTime)
        );

        vm.warp(block.timestamp + 3 days);
        stakingDelegateRewards.getReward(address(alice), stakingToken);
        stakingDelegateRewards.getReward(address(bob), stakingToken);
        assertEq(
            IERC20(rewardToken).balanceOf(address(alice)),
            _calculateEarned(aliceDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );
        assertEq(
            IERC20(rewardToken).balanceOf(address(bob)),
            _calculateEarned(bobDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );
        assertEq(
            IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)),
            REWARD_AMOUNT - IERC20(rewardToken).balanceOf(address(alice)) - IERC20(rewardToken).balanceOf(address(bob))
        );
    }

    function test_getReward_passWhen_CalledByUsers() public {
        vm.prank(yearnStakingDelegate);
        stakingDelegateRewards.addStakingToken(stakingToken, rewardDistributor);

        assertEq(IERC20(rewardToken).balanceOf(address(alice)), 0);
        assertEq(IERC20(rewardToken).balanceOf(address(bob)), 0);
        assertEq(IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)), 0);

        airdrop(IERC20(rewardToken), rewardDistributor, REWARD_AMOUNT);
        vm.startPrank(rewardDistributor);
        IERC20(rewardToken).approve(address(stakingDelegateRewards), REWARD_AMOUNT);
        stakingDelegateRewards.notifyRewardAmount(stakingToken, REWARD_AMOUNT);
        vm.stopPrank();

        uint256 aliceDepositAmount = 100e18;
        uint256 bobDepositAmount = 200e18;
        uint256 totalSupply = aliceDepositAmount + bobDepositAmount;
        vm.startPrank(yearnStakingDelegate);
        stakingDelegateRewards.updateUserBalance(address(alice), stakingToken, aliceDepositAmount);
        stakingDelegateRewards.updateUserBalance(address(bob), stakingToken, bobDepositAmount);
        vm.stopPrank();
        vm.prank(alice);
        stakingDelegateRewards.getReward(stakingToken);
        vm.prank(bob);
        stakingDelegateRewards.getReward(stakingToken);
        assertEq(IERC20(rewardToken).balanceOf(address(alice)), 0);
        assertEq(IERC20(rewardToken).balanceOf(address(bob)), 0);
        uint256 lastUpdateTime = block.timestamp;

        vm.warp(block.timestamp + 4 days);
        vm.prank(alice);
        stakingDelegateRewards.getReward(stakingToken);
        vm.prank(bob);
        stakingDelegateRewards.getReward(stakingToken);
        assertEq(
            IERC20(rewardToken).balanceOf(address(alice)),
            _calculateEarned(aliceDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, block.timestamp - lastUpdateTime)
        );
        assertEq(
            IERC20(rewardToken).balanceOf(address(bob)),
            _calculateEarned(bobDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, block.timestamp - lastUpdateTime)
        );

        vm.warp(block.timestamp + 3 days);
        vm.prank(alice);
        stakingDelegateRewards.getReward(stakingToken);
        vm.prank(bob);
        stakingDelegateRewards.getReward(stakingToken);
        assertEq(
            IERC20(rewardToken).balanceOf(address(alice)),
            _calculateEarned(aliceDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );
        assertEq(
            IERC20(rewardToken).balanceOf(address(bob)),
            _calculateEarned(bobDepositAmount, totalSupply, REWARD_AMOUNT / 7 days, 7 days)
        );
        assertEq(
            IERC20(rewardToken).balanceOf(address(stakingDelegateRewards)),
            REWARD_AMOUNT - IERC20(rewardToken).balanceOf(address(alice)) - IERC20(rewardToken).balanceOf(address(bob))
        );
    }

    function test_grantRole_TimelockRole_revertWhen_CallerIsNotTimelock() public {
        vm.prank(admin);
        stakingDelegateRewards.grantRole(DEFAULT_ADMIN_ROLE, alice);
        vm.expectRevert(_formatAccessControlError(alice, _TIMELOCK_ROLE));
        vm.prank(alice);
        stakingDelegateRewards.grantRole(_TIMELOCK_ROLE, alice);
    }
}

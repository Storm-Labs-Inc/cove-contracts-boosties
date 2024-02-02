// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { BaseRewardsGauge } from "src/rewards/BaseRewardsGauge.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BaseRewardsGauge_Test is BaseTest {
    BaseRewardsGauge public baseRewardsGaugeImplementation;
    BaseRewardsGauge public baseRewardsGauge;
    ERC20 public dummyGaugeAsset;
    ERC20 public dummyRewardToken;
    address public admin;
    address public treasury;
    address public alice;
    address public destination;

    function setUp() public override {
        admin = createUser("admin");
        treasury = createUser("treasury");
        alice = createUser("alice");
        // deploy dummy token
        dummyGaugeAsset = new ERC20("dummy", "DUMB");
        vm.label(address(dummyGaugeAsset), "dummyGaugeAsset");
        // deploy dummy reward token
        dummyRewardToken = new ERC20("dummyReward", "DUMBR");
        vm.label(address(dummyRewardToken), "dummyRewardToken");
        // deploy base rewards gauge implementation
        baseRewardsGaugeImplementation = new BaseRewardsGauge();
        vm.label(address(baseRewardsGaugeImplementation), "baseRewardsGaugeImplementation");
        // clone the implementation
        baseRewardsGauge = BaseRewardsGauge(_cloneContract(address(baseRewardsGaugeImplementation)));
        vm.label(address(baseRewardsGauge), "baseRewardsGauge");
        vm.startPrank(admin);
        baseRewardsGauge.initialize(address(dummyGaugeAsset), "");
        // set admin as manager as well
        baseRewardsGauge.grantRole(keccak256("MANAGER_ROLE"), admin);
        vm.stopPrank();
    }

    function test_initialize() public {
        assertTrue(
            baseRewardsGauge.hasRole(baseRewardsGauge.DEFAULT_ADMIN_ROLE(), admin), "admin should have admin role"
        );
    }

    function testFuzz_setRewardsReceiver(address desitnation) public {
        vm.assume(desitnation != address(0));
        baseRewardsGauge.setRewardsReceiver(destination);
        assertEq(
            baseRewardsGauge.rewardsReceiver(address(this)),
            destination,
            "destination should be set as rewards receiver"
        );
    }

    function testFuzz_addReward(address rewardToken, address _distributor) public {
        vm.assume(rewardToken != address(0));
        vm.assume(_distributor != address(0));
        vm.prank(admin);
        baseRewardsGauge.addReward(rewardToken, _distributor);
        (address distributor,,,,) = baseRewardsGauge.rewardData(rewardToken);
        assertEq(distributor, _distributor, "distributor should be set for reward token");
    }

    function test_addReward_multipleRewards() public {
        vm.startPrank(admin);
        uint256 MAX_REWARDS = baseRewardsGauge.MAX_REWARDS();
        for (uint160 i = 0; i < MAX_REWARDS; i++) {
            baseRewardsGauge.addReward(address(i), address(i * 10));
            (address distributor,,,,) = baseRewardsGauge.rewardData(address(i));
            assertEq(distributor, address(i * 10), "distributor should be set for reward token");
        }
    }

    function test_addReward_revertWhen_notManager() public {
        vm.expectRevert(_formatAccessControlError(address(this), keccak256("MANAGER_ROLE")));
        baseRewardsGauge.addReward(address(1), address(2));
    }

    function test_addReward_revertsWhen_maxRewardsReached() public {
        vm.startPrank(admin);
        uint256 MAX_REWARDS = baseRewardsGauge.MAX_REWARDS();
        for (uint160 i = 0; i < MAX_REWARDS; i++) {
            baseRewardsGauge.addReward(address(i), address(i * 10));
        }
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.MaxRewardsReached.selector));
        baseRewardsGauge.addReward(address(8), address(80));
    }

    function test_addReward_revertsWhen_rewardTokenAlreadyAdded() public {
        vm.startPrank(admin);
        baseRewardsGauge.addReward(address(1), address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.RewardTokenAlreadyAdded.selector));
        baseRewardsGauge.addReward(address(1), address(3));
    }

    function testFuzz_setRewardDistributor(address rewardToken, address _distributor0, address _distributor1) public {
        vm.assume(rewardToken != address(0));
        vm.assume(_distributor0 != address(0));
        vm.assume(_distributor1 != address(0) && _distributor1 != _distributor0);
        vm.prank(admin);
        baseRewardsGauge.addReward(rewardToken, _distributor0);
        (address distributor,,,,) = baseRewardsGauge.rewardData(rewardToken);
        assertEq(distributor, _distributor0, "distributor should be set for reward token");
        vm.prank(_distributor0);
        baseRewardsGauge.setRewardDistributor(rewardToken, _distributor1);
        (address updatedDistributor,,,,) = baseRewardsGauge.rewardData(rewardToken);
        assertEq(updatedDistributor, _distributor1, "distributor1 should be updated for reward token");
    }

    function testFuzz_setRewardDistributor_revertWhen_unauthorized(address user) public {
        address distributor = createUser("distributor");
        vm.assume(user != address(0) && user != admin && user != distributor);
        vm.prank(admin);
        baseRewardsGauge.addReward(address(1), distributor);
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.Unauthorized.selector));
        vm.prank(user);
        baseRewardsGauge.setRewardDistributor(address(1), address(2));
    }

    function test_setRewardDistributor_revertWhen_distributorNotSet() public {
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.DistributorNotSet.selector));
        vm.prank(admin);
        baseRewardsGauge.setRewardDistributor(address(1), address(2));
    }

    function test_setRewardDistributor_revertWhen_invalidDistributorAddress() public {
        vm.startPrank(admin);
        baseRewardsGauge.addReward(address(1), address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.InvalidDistributorAddress.selector));
        baseRewardsGauge.setRewardDistributor(address(1), address(0));
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        // add a reward of dummy reward token
        vm.startPrank(admin);
        baseRewardsGauge.addReward(address(dummyRewardToken), admin);
        // address distributor = createUser("distributor");
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(baseRewardsGauge), amount);
        baseRewardsGauge.deposit(amount, alice);
        assertEq(baseRewardsGauge.balanceOf(alice), amount, "alice should have received shares 1:1");
    }

    function testFuzz_depositRewardToken(uint256 rewardAmount) public {
        vm.assume(rewardAmount >= _WEEK);

        airdrop(dummyRewardToken, admin, rewardAmount);
        vm.startPrank(admin);
        baseRewardsGauge.addReward(address(dummyRewardToken), admin);
        dummyRewardToken.approve(address(baseRewardsGauge), rewardAmount);
        baseRewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount);
        (address distributor, uint256 periodFinish, uint256 rate, uint256 lastUpdate, uint256 integral) =
            baseRewardsGauge.rewardData(address(dummyRewardToken));
        assertEq(distributor, admin);
        assertEq(periodFinish, block.timestamp + 1 weeks);
        assertEq(rate, rewardAmount / _WEEK);
        assertEq(lastUpdate, block.timestamp);
        assertEq(integral, 0);
    }

    function testFuzz_claimRewards(uint256 amount, uint256 rewardAmount) public {
        vm.assume(amount > 0 && amount < 1e28);
        vm.assume(rewardAmount >= 1e12 && rewardAmount < type(uint128).max);

        vm.startPrank(admin);
        baseRewardsGauge.addReward(address(dummyRewardToken), admin);
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(baseRewardsGauge), amount);
        baseRewardsGauge.deposit(amount, alice);
        assertEq(baseRewardsGauge.balanceOf(alice), amount, "alice should have received shares 1:1");
        vm.stopPrank();
        // admin deposits reward tokens to the baseRewardsGauge
        vm.startPrank(admin);
        airdrop(dummyRewardToken, admin, rewardAmount);
        dummyRewardToken.approve(address(baseRewardsGauge), rewardAmount);
        baseRewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount);
        vm.stopPrank();
        // alice's claimable rewards should be 0 at this block
        assertEq(
            0,
            baseRewardsGauge.claimableReward(alice, address(dummyRewardToken)),
            "alice should have 0 claimable rewards"
        );
        // warp forward to the next week when the reward period finishes
        vm.warp(block.timestamp + 1 weeks);
        uint256 aliceClaimableRewards = baseRewardsGauge.claimableReward(alice, address(dummyRewardToken));
        assertGt(aliceClaimableRewards, 0);
        assertApproxEqRel(
            rewardAmount,
            aliceClaimableRewards,
            0.005 * 1e18,
            "alice should have claimable rewards equal to the total amount of reward tokens deposited"
        );
        uint256 aliceBalanceBefore = dummyRewardToken.balanceOf(alice);
        // alice claims rewards
        vm.prank(alice);
        baseRewardsGauge.claimRewards(alice, alice);
        // alice's claimable rewards should be 0 after claiming
        assertEq(
            0,
            baseRewardsGauge.claimableReward(alice, address(dummyRewardToken)),
            "alice should have 0 claimable rewards after claiming"
        );
        uint256 newAliceBalance = dummyRewardToken.balanceOf(alice) - aliceBalanceBefore;
        assertGt(newAliceBalance, 0);
        // alices balance should be close to the reward amount
        assertApproxEqRel(
            newAliceBalance,
            rewardAmount,
            0.005 * 1e18,
            "alice should have received the full reward amount minus the adjustment"
        );
        // check that the integral was updated after claiming
        (,,,, uint256 integral) = baseRewardsGauge.rewardData(address(dummyRewardToken));
        assertGt(integral, 0);
        // alices claimed rewards should have increase by the claimed amount
        assertEq(
            baseRewardsGauge.claimedReward(alice, address(dummyRewardToken)),
            newAliceBalance,
            "alice should have claimed rewards equal to the total amount of reward tokens deposited"
        );
        // check that claimable rewards was correct
        assertEq(newAliceBalance, aliceClaimableRewards, "claimable rewards should be equal to the claimed amount");
    }

    function testFuzz_claimRewards_passWhen_IntegralIsZero(uint256 amount, uint256 rewardAmount) public {
        // This test is to verify that the users' rewards may be zero if the integral is zero
        // This happens when the total supply of the gauge is larger than the total rewards by a factor of 1e18
        vm.assume(amount > 1e28);
        vm.assume(rewardAmount > _WEEK && rewardAmount < amount / 1e18);

        vm.startPrank(admin);
        baseRewardsGauge.addReward(address(dummyRewardToken), admin);
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(baseRewardsGauge), amount);
        baseRewardsGauge.deposit(amount, alice);
        assertEq(baseRewardsGauge.balanceOf(alice), amount, "alice should have received shares 1:1");
        vm.stopPrank();
        // admin deposits reward tokens to the baseRewardsGauge
        vm.startPrank(admin);
        airdrop(dummyRewardToken, admin, rewardAmount);
        dummyRewardToken.approve(address(baseRewardsGauge), rewardAmount);
        baseRewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount);
        vm.stopPrank();
        // alice's claimable rewards should be 0 at this block
        assertEq(
            baseRewardsGauge.claimableReward(alice, address(dummyRewardToken)),
            0,
            "alice should have 0 claimable rewards"
        );
        // warp forward to the next week when the reward period finishes
        vm.warp(block.timestamp + 1 weeks);
        // Due to the difference (> 1e18 multiplier) between the amount and rewardAmount, the claimable rewards
        // will be zero
        assertEq(baseRewardsGauge.claimableReward(alice, address(dummyRewardToken)), 0);
        vm.prank(alice);
        baseRewardsGauge.claimRewards(alice, alice);
        // Due to the difference (> 1e18 multiplier) between the amount and rewardAmount, the integral will be zero
        (,,,, uint256 integral) = baseRewardsGauge.rewardData(address(dummyRewardToken));
        assertEq(integral, 0);
        assertEq(dummyRewardToken.balanceOf(alice), 0);
    }

    function test_depositRewardToken_revertWhen_unauthorized(address distributor, address user) public {
        vm.assume(distributor != address(0));
        vm.assume(user != distributor);
        vm.prank(admin);
        baseRewardsGauge.addReward(address(dummyRewardToken), distributor);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.Unauthorized.selector));
        baseRewardsGauge.depositRewardToken(address(dummyRewardToken), 1e20);
    }
}

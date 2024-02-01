// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { BaseRewardsGauge } from "src/rewards/BaseRewardsGauge.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockGauge } from "./mocks/MockGauge.sol";

contract BaseRewardsGauge_Test is BaseTest {
    BaseRewardsGauge public baseRewardsGaugeImplementation;
    BaseRewardsGauge public baseRewardsGauge;
    ERC20 public dummyGaugeAsset;
    ERC20 public dummyRewardToken;
    MockGauge public mockGauge;
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
        // deploy mock yearn gauge token
        mockGauge = new MockGauge(address(dummyGaugeAsset));
        vm.label(address(mockGauge), "mockGauge");
        baseRewardsGaugeImplementation = new BaseRewardsGauge();
        vm.label(address(baseRewardsGaugeImplementation), "baseRewardsGaugeImplementation");
        // clone the rewardForwarder
        baseRewardsGauge = BaseRewardsGauge(_cloneContract(address(baseRewardsGaugeImplementation)));
        vm.label(address(baseRewardsGauge), "baseRewardsGauge");
        bytes memory empty;
        vm.startPrank(admin);
        baseRewardsGauge.initialize(address(mockGauge), empty);
        // set admin as manager as well
        baseRewardsGauge.grantRole(keccak256("MANAGER_ROLE"), admin);
        vm.stopPrank();
    }

    function test_initialize() public {
        require(baseRewardsGauge.hasRole(baseRewardsGauge.DEFAULT_ADMIN_ROLE(), admin), "admin should have admin role");
    }

    function testFuzz_setRewardsReceiver(address desitnation) public {
        vm.assume(desitnation != address(0));
        baseRewardsGauge.setRewardsReceiver(destination);
        require(
            baseRewardsGauge.rewardsReceiver(address(this)) == destination,
            "destination should be set as rewards receiver"
        );
    }

    function testFuzz_addReward(address rewardToken, address _distributor) public {
        vm.assume(rewardToken != address(0));
        vm.assume(_distributor != address(0));
        vm.prank(admin);
        baseRewardsGauge.addReward(rewardToken, _distributor);
        (address distributor,,,,) = baseRewardsGauge.rewardData(rewardToken);
        require(distributor == _distributor, "distributor should be set for reward token");
    }

    function test_addReward_multipleRewards() public {
        vm.startPrank(admin);
        uint256 MAX_REWARDS = baseRewardsGauge.MAX_REWARDS();
        for (uint160 i = 0; i < MAX_REWARDS; i++) {
            baseRewardsGauge.addReward(address(i), address(i * 10));
            (address distributor,,,,) = baseRewardsGauge.rewardData(address(i));
            require(distributor == address(i * 10), "distributor should be set for reward token");
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
        require(distributor == _distributor0, "distributor should be set for reward token");
        vm.prank(_distributor0);
        baseRewardsGauge.setRewardDistributor(rewardToken, _distributor1);
        (address updatedDistributor,,,,) = baseRewardsGauge.rewardData(rewardToken);
        require(updatedDistributor == _distributor1, "distributor1 should be updated for reward token");
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
        dummyGaugeAsset.approve(address(mockGauge), amount);
        mockGauge.deposit(amount, alice);
        // alice deposits mockgauge tokens to the baseRewardsGauge
        mockGauge.approve(address(baseRewardsGauge), mockGauge.balanceOf(alice));
        baseRewardsGauge.deposit(mockGauge.balanceOf(alice), alice);
        assertEq(baseRewardsGauge.balanceOf(alice), amount, "alice should have received shares 1:1");
    }

    function test_depositRewardToken_buh() public {
        uint256 amount = 1e20;
        uint256 rewardAmount = 1e19;
        vm.assume(amount > 0);
        // add a reward of a new dummy token

        vm.startPrank(admin);
        baseRewardsGauge.addReward(address(dummyRewardToken), admin);
        // address distributor = createUser("distributor");
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(mockGauge), amount);
        mockGauge.deposit(amount, alice);
        // alice deposits mockgauge tokens to the baseRewardsGauge
        mockGauge.approve(address(baseRewardsGauge), mockGauge.balanceOf(alice));
        baseRewardsGauge.deposit(mockGauge.balanceOf(alice), alice);
        assertEq(baseRewardsGauge.balanceOf(alice), amount, "alice should have received shares 1:1");
        vm.stopPrank();
        // admin deposits reward tokens to the baseRewardsGauge
        vm.startPrank(admin);
        airdrop(dummyRewardToken, admin, rewardAmount);
        dummyRewardToken.approve(address(baseRewardsGauge), amount);
        // reward amount ==  1e19
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
        // NOTE: not sure why this is not the full amount
        assertEq(
            rewardAmount,
            baseRewardsGauge.claimableReward(alice, address(dummyRewardToken)),
            "alice should have claimable rewards equal to the total amount of reward tokens deposited"
        );
        // check that the claimable rewards are close to the total amount of reward tokens deposited
        assertApproxEqRel(
            rewardAmount,
            baseRewardsGauge.claimableReward(alice, address(dummyRewardToken)),
            1e15, //1e18 is 100% so 1e15 is 0.001%
            "alice should have claimable rewards close to the total amount of reward tokens deposited"
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
        // alices balance should be close to the reward amount
        assertApproxEqRel(
            rewardAmount,
            newAliceBalance,
            1e15, //1e18 is 100% so 1e15 is 0.001%
            "alice should have received close to the full reward amount"
        );
        // alices claimed rewards should have increase by the claimed amount
        assertEq(
            newAliceBalance,
            baseRewardsGauge.claimedReward(alice, address(dummyRewardToken)),
            "alice should have claimed rewards equal to the total amount of reward tokens deposited"
        );
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20RewardsGauge, BaseRewardsGauge } from "src/rewards/ERC20RewardsGauge.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract ERC20RewardsGauge_Test is BaseTest {
    ERC20RewardsGauge public erc20RewardsGaugeImplementation;
    ERC20RewardsGauge public rewardsGauge;
    ERC20 public dummyGaugeAsset;
    ERC20 public dummyRewardToken;
    address public admin;
    address public manager;
    address public pauser;
    address public treasury;
    address public alice;

    function setUp() public override {
        admin = createUser("admin");
        manager = createUser("manager");
        pauser = createUser("pauser");

        treasury = createUser("treasury");
        alice = createUser("alice");
        // deploy dummy token
        dummyGaugeAsset = new ERC20("dummy", "DUMB");
        vm.label(address(dummyGaugeAsset), "dummyGaugeAsset");
        // deploy dummy reward token
        dummyRewardToken = new ERC20("dummyReward", "DUMBR");
        vm.label(address(dummyRewardToken), "dummyRewardToken");
        // deploy base rewards gauge implementation
        erc20RewardsGaugeImplementation = new ERC20RewardsGauge();
        vm.label(address(erc20RewardsGaugeImplementation), "erc20RewardsGaugeImplementation");
        // clone the implementation
        rewardsGauge = ERC20RewardsGauge(_cloneContract(address(erc20RewardsGaugeImplementation)));
        vm.label(address(rewardsGauge), "rewardsGauge");
        vm.startPrank(admin);
        rewardsGauge.initialize(address(dummyGaugeAsset));
        // setup roles
        rewardsGauge.grantRole(rewardsGauge.MANAGER_ROLE(), manager);
        rewardsGauge.renounceRole(rewardsGauge.MANAGER_ROLE(), admin);
        rewardsGauge.grantRole(rewardsGauge.PAUSER_ROLE(), pauser);
        rewardsGauge.renounceRole(rewardsGauge.PAUSER_ROLE(), admin);
        vm.stopPrank();
    }

    function test_initialize() public {
        assertTrue(rewardsGauge.hasRole(rewardsGauge.DEFAULT_ADMIN_ROLE(), admin), "admin should have admin role");
        assertTrue(rewardsGauge.hasRole(rewardsGauge.MANAGER_ROLE(), manager), "manager should have manager role");
        assertTrue(rewardsGauge.hasRole(rewardsGauge.PAUSER_ROLE(), pauser), "pauser should have pauser role");
        assertEq(rewardsGauge.asset(), address(dummyGaugeAsset), "asset should be set");
    }

    function test_initialize_revertWhen_zeroAddress() public {
        ERC20RewardsGauge dummyRewardsGauge =
            ERC20RewardsGauge(_cloneContract(address(erc20RewardsGaugeImplementation)));
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.ZeroAddress.selector));
        dummyRewardsGauge.initialize(address(0));
    }

    function testFuzz_initialize_revetWhen_AlreadyInitialized(address asset_) public {
        vm.assume(asset_ != address(0));
        vm.expectRevert("Initializable: contract is already initialized");
        rewardsGauge.initialize(asset_);
    }

    function test_decimals() public {
        assertEq(rewardsGauge.decimals(), dummyGaugeAsset.decimals(), "decimals should same as underlying asset");
    }

    function testFuzz_setRewardsReceiver(address destination) public {
        vm.assume(destination != address(0));
        rewardsGauge.setRewardsReceiver(destination);
        assertEq(
            rewardsGauge.rewardsReceiver(address(this)), destination, "destination should be set as rewards receiver"
        );
    }

    function testFuzz_addReward(address rewardToken, address _distributor) public {
        vm.assume(rewardToken != address(0));
        vm.assume(_distributor != address(0));
        vm.assume(rewardToken != address(dummyGaugeAsset));
        vm.prank(manager);
        rewardsGauge.addReward(rewardToken, _distributor);
        address distributor = rewardsGauge.getRewardData(rewardToken).distributor;
        assertEq(distributor, _distributor, "distributor should be set for reward token");
    }

    function test_addReward_multipleRewards() public {
        vm.startPrank(manager);
        uint256 MAX_REWARDS = rewardsGauge.MAX_REWARDS();
        for (uint160 i = 1; i <= MAX_REWARDS; i++) {
            rewardsGauge.addReward(address(i), address(i * 10));
            address distributor = rewardsGauge.getRewardData(address(i)).distributor;
            assertEq(distributor, address(i * 10), "distributor should be set for reward token");
        }
    }

    function test_addReward_revertWhen_notManager() public {
        vm.expectRevert(_formatAccessControlError(address(this), rewardsGauge.MANAGER_ROLE()));
        rewardsGauge.addReward(address(1), address(2));
    }

    function test_addReward_revertsWhen_maxRewardsReached() public {
        vm.startPrank(manager);
        uint256 MAX_REWARDS = rewardsGauge.MAX_REWARDS();
        for (uint160 i = 1; i <= MAX_REWARDS; i++) {
            rewardsGauge.addReward(address(i), address(i * 10));
        }
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.MaxRewardsReached.selector));
        rewardsGauge.addReward(address(uint160(MAX_REWARDS + 1)), (address(uint160(MAX_REWARDS + 1) * 10)));
    }

    function test_addReward_revertsWhen_rewardTokenAlreadyAdded() public {
        vm.startPrank(manager);
        rewardsGauge.addReward(address(1), address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.RewardTokenAlreadyAdded.selector));
        rewardsGauge.addReward(address(1), address(3));
    }

    function test_addReward_revertsWhen_rewardTokenZeroAddress() public {
        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.ZeroAddress.selector));
        rewardsGauge.addReward(address(0), address(1));
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.ZeroAddress.selector));
        rewardsGauge.addReward(address(1), address(0));
    }

    function test_addReward_revertsWhen_rewardTokenIsAsset() public {
        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.RewardCannotBeAsset.selector));
        rewardsGauge.addReward(address(dummyGaugeAsset), address(1));
    }

    function testFuzz_setRewardDistributor(address rewardToken, address _distributor0, address _distributor1) public {
        vm.assume(rewardToken != address(0) && rewardToken != address(dummyGaugeAsset));
        vm.assume(_distributor0 != address(0));
        vm.assume(_distributor1 != address(0) && _distributor1 != _distributor0);
        vm.prank(manager);
        rewardsGauge.addReward(rewardToken, _distributor0);
        address distributor = rewardsGauge.getRewardData(rewardToken).distributor;
        assertEq(distributor, _distributor0, "distributor should be set for reward token");
        vm.prank(_distributor0);
        rewardsGauge.setRewardDistributor(rewardToken, _distributor1);
        address updatedDistributor = rewardsGauge.getRewardData(rewardToken).distributor;
        assertEq(updatedDistributor, _distributor1, "distributor1 should be updated for reward token");
    }

    function testFuzz_setRewardDistributor_revertWhen_unauthorized(address user) public {
        address distributor = createUser("distributor");
        vm.assume(user != address(0) && user != manager && user != distributor);
        vm.prank(manager);
        rewardsGauge.addReward(address(1), distributor);
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.Unauthorized.selector));
        vm.prank(user);
        rewardsGauge.setRewardDistributor(address(1), address(2));
    }

    function test_setRewardDistributor_revertWhen_distributorNotSet() public {
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.DistributorNotSet.selector));
        vm.prank(manager);
        rewardsGauge.setRewardDistributor(address(1), address(2));
    }

    function test_setRewardDistributor_revertWhen_invalidDistributorAddress() public {
        vm.startPrank(manager);
        rewardsGauge.addReward(address(1), address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.InvalidDistributorAddress.selector));
        rewardsGauge.setRewardDistributor(address(1), address(0));
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        // add a reward of dummy reward token
        vm.prank(manager);
        rewardsGauge.addReward(address(dummyRewardToken), admin);
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        rewardsGauge.deposit(amount, alice);
        assertEq(rewardsGauge.balanceOf(alice), amount, "alice should have received shares 1:1");
    }

    function testFuzz_deposit_revertsWhen_depositsPaused(uint256 amount) public {
        vm.assume(amount > 0);
        vm.prank(pauser);
        rewardsGauge.pause();
        assertTrue(rewardsGauge.paused(), "deposits should be paused");
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        vm.expectRevert("Pausable: paused");
        rewardsGauge.deposit(amount, alice);
    }

    function test_pause_revertWhen_notPauser() public {
        vm.expectRevert(_formatAccessControlError(address(this), rewardsGauge.PAUSER_ROLE()));
        rewardsGauge.pause();
    }

    function test_unpause_revertWhen_notAdmin() public {
        vm.expectRevert(_formatAccessControlError(address(this), rewardsGauge.DEFAULT_ADMIN_ROLE()));
        rewardsGauge.unpause();
    }

    function testFuzz_unpause(uint256 amount) public {
        vm.assume(amount > 0);
        vm.prank(pauser);
        rewardsGauge.pause();
        assertTrue(rewardsGauge.paused(), "contract should be paused");
        vm.prank(admin);
        rewardsGauge.unpause();
        assertFalse(rewardsGauge.paused(), "contract should be unpaused");
        vm.stopPrank();
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        rewardsGauge.deposit(amount, alice);
        assertEq(rewardsGauge.balanceOf(alice), amount, "alice should have received shares 1:1");
    }

    function testFuzz_depositRewardToken(uint256 rewardAmount) public {
        vm.assume(rewardAmount >= _WEEK);

        airdrop(dummyRewardToken, admin, rewardAmount);
        vm.prank(manager);
        rewardsGauge.addReward(address(dummyRewardToken), admin);
        vm.startPrank(admin);
        dummyRewardToken.approve(address(rewardsGauge), rewardAmount);
        rewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount);
        BaseRewardsGauge.Reward memory rewardData = rewardsGauge.getRewardData(address(dummyRewardToken));
        assertEq(rewardData.distributor, admin);
        assertEq(rewardData.periodFinish, block.timestamp + 1 weeks);
        assertEq(rewardData.rate, rewardAmount / _WEEK);
        assertEq(rewardData.lastUpdate, block.timestamp);
        assertEq(rewardData.integral, 0);
        assertEq(rewardData.leftOver, rewardAmount % _WEEK);
    }

    function testFuzz_depositRewardToken_withPartialRewardRemaining(
        uint256 rewardAmount0,
        uint256 rewardAmount1
    )
        public
    {
        rewardAmount0 = bound(rewardAmount0, _WEEK, type(uint128).max / 2);
        rewardAmount1 = bound(rewardAmount1, _WEEK * 2, type(uint128).max / 2);

        airdrop(dummyRewardToken, admin, rewardAmount0 + rewardAmount1);
        vm.prank(manager);
        rewardsGauge.addReward(address(dummyRewardToken), admin);
        vm.startPrank(admin);
        dummyRewardToken.approve(address(rewardsGauge), rewardAmount0 + rewardAmount1);
        rewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount0);
        BaseRewardsGauge.Reward memory rewardData = rewardsGauge.getRewardData(address(dummyRewardToken));
        assertEq(rewardData.distributor, admin);
        assertEq(rewardData.periodFinish, block.timestamp + 1 weeks);
        assertEq(rewardData.rate, rewardAmount0 / _WEEK);
        assertEq(rewardData.lastUpdate, block.timestamp);
        assertEq(rewardData.integral, 0);
        assertEq(rewardData.leftOver, rewardAmount0 % _WEEK);
        // warp to halfway through the reward period
        vm.warp(block.timestamp + (rewardData.periodFinish / 2));
        // deposit another round of rewards
        rewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount1);

        BaseRewardsGauge.Reward memory newRewardData = rewardsGauge.getRewardData(address(dummyRewardToken));
        assertEq(newRewardData.periodFinish, block.timestamp + 1 weeks, "periodFinish should be updated");
        uint256 remainingTime = rewardData.periodFinish - block.timestamp;
        uint256 leftoverReward = remainingTime * rewardData.rate + rewardData.leftOver;
        uint256 expectedNewRate = (leftoverReward + rewardAmount1) / _WEEK;
        assertEq(newRewardData.rate, expectedNewRate, "rate should be updated");
        assertEq(newRewardData.lastUpdate, block.timestamp, "lastUpdate should be updated");
        assertEq(newRewardData.integral, 0, "integral should still be 0");
        assertEq(newRewardData.leftOver, (leftoverReward + rewardAmount1) % _WEEK, "leftOver should be updated");
    }

    function test_depositRewardToken_revertWhen_Unauthorized(address distributor, address user) public {
        vm.assume(distributor != address(0));
        vm.assume(user != distributor);
        vm.prank(manager);
        rewardsGauge.addReward(address(dummyRewardToken), distributor);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.Unauthorized.selector));
        rewardsGauge.depositRewardToken(address(dummyRewardToken), 1e20);
    }

    function testFuzz_claimRewards(uint256 amount, uint256 rewardAmount) public {
        amount = bound(amount, 1, type(uint128).max);
        rewardAmount = bound(rewardAmount, Math.max(1e9, amount / 1e15), type(uint128).max);

        vm.prank(manager);
        rewardsGauge.addReward(address(dummyRewardToken), admin);
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        rewardsGauge.deposit(amount, alice);
        assertEq(rewardsGauge.balanceOf(alice), amount, "alice should have received shares 1:1");
        vm.stopPrank();
        // admin deposits reward tokens to the rewardsGauge
        vm.startPrank(admin);
        airdrop(dummyRewardToken, admin, rewardAmount);
        dummyRewardToken.approve(address(rewardsGauge), rewardAmount);
        rewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount);
        vm.stopPrank();
        // alice's claimable rewards should be 0 at this block
        assertEq(
            0, rewardsGauge.claimableReward(alice, address(dummyRewardToken)), "alice should have 0 claimable rewards"
        );
        // warp forward to the next week when the reward period finishes
        vm.warp(block.timestamp + 1 weeks);
        uint256 aliceClaimableRewards = rewardsGauge.claimableReward(alice, address(dummyRewardToken));
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
        rewardsGauge.claimRewards(alice, alice);
        // alice's claimable rewards should be 0 after claiming
        assertEq(
            0,
            rewardsGauge.claimableReward(alice, address(dummyRewardToken)),
            "alice should have 0 claimable rewards after claiming"
        );
        uint256 newAliceBalance = dummyRewardToken.balanceOf(alice) - aliceBalanceBefore;
        // alices balance should be close to the reward amount
        assertApproxEqRel(
            rewardAmount,
            newAliceBalance,
            0.005 * 1e18,
            "alice should have received the full reward amount minus the adjustment"
        );
        // check that the integral was updated after claiming
        uint256 integral = rewardsGauge.getRewardData(address(dummyRewardToken)).integral;
        assertGt(integral, 0);
        // alices claimed rewards should have increase by the claimed amount
        assertEq(
            rewardsGauge.claimedReward(alice, address(dummyRewardToken)),
            newAliceBalance,
            "alice should have claimed rewards equal to the total amount of reward tokens deposited"
        );
        // check that claimable rewards was correct
        assertEq(newAliceBalance, aliceClaimableRewards, "claimable rewards should be equal to the claimed amount");
    }

    function testFuzz_claimRewards_passWhen_IntegralIsZero(uint256 amount, uint256 rewardAmount) public {
        // This test is to verify that the users' rewards may be zero if the integral is zero
        // This happens when the total supply of the gauge is larger than the total rewards by a factor of 1e18
        amount = bound(amount, 1e28, type(uint256).max);
        rewardAmount = bound(rewardAmount, _WEEK, amount / 1e18);

        vm.startPrank(manager);
        rewardsGauge.addReward(address(dummyRewardToken), admin);
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        rewardsGauge.deposit(amount, alice);
        assertEq(rewardsGauge.balanceOf(alice), amount, "alice should have received shares 1:1");
        vm.stopPrank();
        // admin deposits reward tokens to the rewardsGauge
        vm.startPrank(admin);
        airdrop(dummyRewardToken, admin, rewardAmount);
        dummyRewardToken.approve(address(rewardsGauge), rewardAmount);
        rewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount);
        vm.stopPrank();
        // alice's claimable rewards should be 0 at this block
        assertEq(
            rewardsGauge.claimableReward(alice, address(dummyRewardToken)), 0, "alice should have 0 claimable rewards"
        );
        // warp forward to the next week when the reward period finishes
        vm.warp(block.timestamp + 1 weeks);
        // Due to the difference (> 1e18 multiplier) between the amount and rewardAmount, the claimable rewards
        // will be zero
        assertEq(rewardsGauge.claimableReward(alice, address(dummyRewardToken)), 0);
        vm.prank(alice);
        rewardsGauge.claimRewards(alice, alice);
        // Due to the difference (> 1e18 multiplier) between the amount and rewardAmount, the integral will be zero
        uint256 integral = rewardsGauge.getRewardData(address(dummyRewardToken)).integral;
        assertEq(integral, 0);
        assertEq(dummyRewardToken.balanceOf(alice), 0);
    }

    function testFuzz_claimRewards_multipleRewards(uint256 amount, uint256[8] memory rewardAmounts) public {
        amount = bound(amount, 1, type(uint128).max);
        for (uint256 i = 0; i < rewardAmounts.length; i++) {
            // lower than 1e14 will run but the dust is more than acceptable
            rewardAmounts[i] = bound(rewardAmounts[i], Math.max(1e9, amount / 1e15), type(uint128).max);
        }

        // create 8 reward tokens and airdrop the respective amounts
        vm.startPrank(manager);
        address[] memory dummyRewardTokens = new address[](8);
        for (uint256 i = 0; i < 8; i++) {
            if (i == 0) {
                dummyRewardTokens[i] = address(dummyRewardToken);
            } else {
                ERC20 rewardToken = new ERC20("dummy", "DUMB");
                string memory rewardTokenLabel = string(abi.encodePacked("dummyRewardToken-", Strings.toString(i)));
                vm.label(address(rewardToken), rewardTokenLabel);
                dummyRewardTokens[i] = address(rewardToken);
            }
            airdrop(ERC20(dummyRewardTokens[i]), admin, rewardAmounts[i]);
            rewardsGauge.addReward(dummyRewardTokens[i], admin);
        }
        vm.stopPrank();

        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        rewardsGauge.deposit(amount, alice);
        assertEq(rewardsGauge.balanceOf(alice), amount, "alice should have received shares 1:1");
        vm.stopPrank();

        // admin deposits reward tokens to the rewardsGauge
        vm.startPrank(admin);
        for (uint256 i = 0; i < 8; i++) {
            ERC20(dummyRewardTokens[i]).approve(address(rewardsGauge), rewardAmounts[i]);
            rewardsGauge.depositRewardToken(dummyRewardTokens[i], rewardAmounts[i]);
            // alice's claimable rewards should be 0 at this block
            assertEq(
                0, rewardsGauge.claimableReward(alice, dummyRewardTokens[i]), "alice should have 0 claimable rewards"
            );
        }
        vm.stopPrank();

        // warp forward to the next week when the reward period finishes
        vm.warp(block.timestamp + 1 weeks);

        // alice's claimableRewards for each reward token
        uint256[8] memory aliceClaimableRewards;

        for (uint256 i = 0; i < 8; i++) {
            uint256 aliceClaimableReward = rewardsGauge.claimableReward(alice, dummyRewardTokens[i]);
            assertGt(aliceClaimableReward, 0);
            assertApproxEqRel(
                rewardAmounts[i],
                aliceClaimableReward,
                0.005 * 1e18,
                "alice should have claimable rewards equal to the total amount of reward tokens deposited"
            );
            aliceClaimableRewards[i] = aliceClaimableReward;
        }
        // alice's balance of all tokens before claim rewards
        uint256[8] memory aliceBalancesBefore;
        for (uint256 i = 0; i < 8; i++) {
            aliceBalancesBefore[i] = ERC20(dummyRewardTokens[i]).balanceOf(alice);
        }

        // alice claims rewards
        vm.prank(alice);
        rewardsGauge.claimRewards(alice, alice);

        for (uint256 i = 0; i < 8; i++) {
            // alice's claimable rewards should be 0 after claiming
            assertEq(
                0,
                rewardsGauge.claimableReward(alice, dummyRewardTokens[i]),
                "alice should have 0 claimable rewards after claiming"
            );

            uint256 newAliceBalance = ERC20(dummyRewardTokens[i]).balanceOf(alice) - aliceBalancesBefore[i];
            // alices balance should be close to the reward amount
            assertApproxEqRel(
                newAliceBalance,
                rewardAmounts[i],
                0.005 * 1e18,
                "alice should have received the full reward amount minus the adjustment"
            );
            // check that the integral was updated after claiming
            uint256 integral = rewardsGauge.getRewardData(dummyRewardTokens[i]).integral;
            assertGt(integral, 0);
            // alices claimed rewards should have increase by the claimed amount
            assertEq(
                rewardsGauge.claimedReward(alice, dummyRewardTokens[i]),
                newAliceBalance,
                "alice should have claimed rewards equal to the total amount of reward tokens deposited"
            );
            // check that claimable rewards was correct
            assertEq(
                newAliceBalance, aliceClaimableRewards[i], "claimable rewards should be equal to the claimed amount"
            );
        }
    }

    function testFuzz_claimRewards_multipleUsers(uint256[10] memory amounts, uint256 rewardAmount) public {
        uint256 totalAmount = 0;
        address[10] memory depositors;
        for (uint256 i = 0; i < amounts.length; i++) {
            depositors[i] = createUser(string(abi.encodePacked("user-", Strings.toString(i))));
            // Bound user amounts to a reasonable range
            // If the difference between the lowest and the total amount is too large, the
            // claimable rewards will be zero
            amounts[i] = bound(amounts[i], 1e15, 1e26);
            totalAmount += amounts[i];
        }
        // lower reward amounts will run but the relative diff from expected becomes large (> 0.5%) due to
        // small numbers
        rewardAmount = bound(rewardAmount, 1e13, type(uint128).max);
        uint256[10] memory usersShareOfTotalReward;
        for (uint256 i = 0; i < amounts.length; i++) {
            usersShareOfTotalReward[i] = (amounts[i] * rewardAmount) / totalAmount;
        }

        vm.startPrank(manager);
        rewardsGauge.addReward(address(dummyRewardToken), admin);

        // each user gets some mockgauge tokens by depositing dummy token
        for (uint256 i = 0; i < amounts.length; i++) {
            airdrop(dummyGaugeAsset, depositors[i], amounts[i]);
            vm.startPrank(depositors[i]);
            dummyGaugeAsset.approve(address(rewardsGauge), amounts[i]);
            rewardsGauge.deposit(amounts[i], depositors[i]);
            assertEq(rewardsGauge.balanceOf(depositors[i]), amounts[i], "user should have received shares 1:1");
            vm.stopPrank();
        }
        // admin deposits reward tokens to the rewardsGauge
        vm.startPrank(admin);
        airdrop(dummyRewardToken, admin, rewardAmount);
        dummyRewardToken.approve(address(rewardsGauge), rewardAmount);
        rewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount);
        vm.stopPrank();
        // depositors claimable rewards should be 0 at this block
        for (uint256 i = 0; i < amounts.length; i++) {
            assertEq(
                0,
                rewardsGauge.claimableReward(depositors[i], address(dummyRewardToken)),
                "user should have 0 claimable rewards"
            );
        }

        // warp forward to the next week when the reward period finishes
        vm.warp(block.timestamp + 1 weeks);

        // depositors claimableRewards for each reward token
        uint256[10] memory depositorsClaimableRewards;
        uint256 totalClaimableRewards;
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 depositorsClaimableReward = rewardsGauge.claimableReward(depositors[i], address(dummyRewardToken));
            assertGt(depositorsClaimableReward, 0);
            assertApproxEqRel(
                usersShareOfTotalReward[i],
                depositorsClaimableReward,
                0.005 * 1e18,
                "user should have claimable rewards equal to their share of the reward amount"
            );
            depositorsClaimableRewards[i] = depositorsClaimableReward;
            totalClaimableRewards += depositorsClaimableReward;
        }
        assertApproxEqRel(
            rewardAmount,
            totalClaimableRewards,
            0.005 * 1e18,
            "total claimable rewards should be equal to the total amount of reward tokens deposited"
        );

        // depositors balance of all tokens before claim rewards
        uint256[10] memory depositorsBalancesBefore;
        for (uint256 i = 0; i < amounts.length; i++) {
            depositorsBalancesBefore[i] = dummyRewardToken.balanceOf(depositors[i]);
        }

        for (uint256 i = 0; i < amounts.length; i++) {
            // all depositors claim rewards
            vm.prank(depositors[i]);
            rewardsGauge.claimRewards(depositors[i], depositors[i]);
            // depositors claimable rewards should be 0 after claiming
            assertEq(
                0,
                rewardsGauge.claimableReward(depositors[i], address(dummyRewardToken)),
                "user should have 0 claimable rewards after claiming"
            );
            uint256 newDepositorBalance = dummyRewardToken.balanceOf(depositors[i]) - depositorsBalancesBefore[i];
            // depositors balance should be close to their share of reward amount
            assertApproxEqRel(
                newDepositorBalance,
                usersShareOfTotalReward[i],
                0.005 * 1e18,
                "user should have received their share of the reward amount"
            );
            // check that depositors claimed reward increased by the correct amount
            assertEq(
                rewardsGauge.claimedReward(depositors[i], address(dummyRewardToken)),
                newDepositorBalance,
                "user should have claimed rewards equal to their actual amount received"
            );
            // check that claimable rewards was correct
            assertEq(
                newDepositorBalance,
                depositorsClaimableRewards[i],
                "claimable rewards should be equal to the claimed amount"
            );
        }
        // check that the integral was updated after claiming
        uint256 integral = rewardsGauge.getRewardData(address(dummyRewardToken)).integral;
        assertGt(integral, 0);
    }

    function testFuzz_claimRewards_noReceiverProvided(uint256 amount, uint256 rewardAmount) public {
        vm.assume(amount > 0 && amount < 1e28);
        vm.assume(rewardAmount >= 1e12 && rewardAmount < type(uint128).max);

        vm.startPrank(manager);
        rewardsGauge.addReward(address(dummyRewardToken), admin);
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        rewardsGauge.deposit(amount, alice);
        assertEq(rewardsGauge.balanceOf(alice), amount, "alice should have received shares 1:1");
        vm.stopPrank();
        // admin deposits reward tokens to the rewardsGauge
        vm.startPrank(admin);
        airdrop(dummyRewardToken, admin, rewardAmount);
        dummyRewardToken.approve(address(rewardsGauge), rewardAmount);
        rewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount);
        vm.stopPrank();
        // alice's claimable rewards should be 0 at this block
        assertEq(
            0, rewardsGauge.claimableReward(alice, address(dummyRewardToken)), "alice should have 0 claimable rewards"
        );
        // warp forward to the next week when the reward period finishes
        vm.warp(block.timestamp + 1 weeks);
        uint256 aliceClaimableRewards = rewardsGauge.claimableReward(alice, address(dummyRewardToken));
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
        // claim rewards without providing a receiver
        rewardsGauge.claimRewards(alice, address(0));
        // alice's claimable rewards should be 0 after claiming
        assertEq(
            0,
            rewardsGauge.claimableReward(alice, address(dummyRewardToken)),
            "alice should have 0 claimable rewards after claiming"
        );
        uint256 newAliceBalance = dummyRewardToken.balanceOf(alice) - aliceBalanceBefore;
        // alices balance should be close to the reward amount
        assertApproxEqRel(
            newAliceBalance,
            rewardAmount,
            0.005 * 1e18,
            "alice should have received the full reward amount minus the adjustment"
        );
        // check that the integral was updated after claiming
        uint256 integral = rewardsGauge.getRewardData(address(dummyRewardToken)).integral;
        assertGt(integral, 0);
        // alices claimed rewards should have increase by the claimed amount
        assertEq(
            rewardsGauge.claimedReward(alice, address(dummyRewardToken)),
            newAliceBalance,
            "alice should have claimed rewards equal to the total amount of reward tokens deposited"
        );
        // check that claimable rewards was correct
        assertEq(newAliceBalance, aliceClaimableRewards, "claimable rewards should be equal to the claimed amount");
    }

    function test_claimRewards_revertWhen_claimForAnotherUser() public {
        uint256 amount = 1e20;
        uint256 rewardAmount = 1e19;
        address bob = createUser("bob");
        vm.startPrank(manager);
        rewardsGauge.addReward(address(dummyRewardToken), admin);
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        rewardsGauge.deposit(amount, alice);
        vm.stopPrank();
        // receiver deposits reward tokens to the rewardsGauge
        vm.startPrank(admin);
        airdrop(dummyRewardToken, admin, rewardAmount);
        dummyRewardToken.approve(address(rewardsGauge), rewardAmount);
        rewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount);
        vm.stopPrank();
        // warp forward to the next week when the reward period finishes
        vm.warp(block.timestamp + 1 weeks);

        // user attempts to claim rewards alice's rewards
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.CannotRedirectForAnotherUser.selector));
        rewardsGauge.claimRewards(alice, bob);
    }

    function test_claimRewards_revertWhen_rewardAmountTooLow() public {
        uint256 amount = 1e20;
        uint256 rewardAmount = 1;
        vm.prank(manager);
        rewardsGauge.addReward(address(dummyRewardToken), admin);
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        rewardsGauge.deposit(amount, alice);
        vm.stopPrank();
        // receiver deposits reward tokens to the rewardsGauge
        vm.startPrank(admin);
        airdrop(dummyRewardToken, admin, rewardAmount);
        dummyRewardToken.approve(address(rewardsGauge), rewardAmount);
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.RewardAmountTooLow.selector));
        rewardsGauge.depositRewardToken(address(dummyRewardToken), rewardAmount);
        vm.stopPrank();
    }
}

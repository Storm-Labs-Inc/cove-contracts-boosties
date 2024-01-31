// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { RewardForwarder } from "src/rewards/RewardForwarder.sol";
import { MockBaseRewardsGauge } from "test/mocks/MockBaseRewardsGauge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RewardForwarder_Test is BaseTest {
    RewardForwarder public rewardForwarderImplementation;
    RewardForwarder public rewardForwarder;
    ERC20 public token;
    address public admin;
    address public treasury;
    address public destination;

    function setUp() public override {
        admin = createUser("admin");
        treasury = createUser("treasury");
        // deploy dummy token
        token = new ERC20("dummy", "DUMB");
        vm.label(address(token), "token");
        // deploy dummy reward receiver
        destination = address(new MockBaseRewardsGauge());
        vm.label(destination, "destination");
        rewardForwarderImplementation = new RewardForwarder();
        vm.label(address(rewardForwarderImplementation), "rewardForwarderImpl");
        // clone the rewardForwarder
        rewardForwarder = RewardForwarder(_cloneContract(address(rewardForwarderImplementation)));
        vm.label(address(rewardForwarder), "rewardForwarder");
        rewardForwarder.initialize(admin, treasury, destination);
    }

    function test_initialize() public {
        assertEq(rewardForwarder.rewardDestination(), destination);
        assertEq(rewardForwarder.treasury(), treasury);
        require(rewardForwarder.hasRole(rewardForwarder.DEFAULT_ADMIN_ROLE(), admin), "admin should have admin role");
    }

    function test_initialize_revertWhen_zeroDestination() public {
        RewardForwarder dummyRewardForwarder = RewardForwarder(_cloneContract(address(rewardForwarderImplementation)));
        vm.expectRevert(abi.encodeWithSelector(RewardForwarder.ZeroAddress.selector));
        dummyRewardForwarder.initialize(admin, treasury, address(0));
    }

    function test_approveRewardToken() public {
        // create dummy token
        rewardForwarder.approveRewardToken(address(token));
        assertEq(token.allowance(address(rewardForwarder), destination), type(uint256).max);
    }

    function test_setTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0) && newTreasury != treasury);
        vm.prank(admin);
        rewardForwarder.setTreasury(newTreasury);
        assertEq(rewardForwarder.treasury(), newTreasury);
    }

    function test_setTreasury_revertWhen_notAdmin() public {
        vm.expectRevert(_formatAccessControlError(address(this), rewardForwarder.DEFAULT_ADMIN_ROLE()));
        rewardForwarder.setTreasury(address(1));
    }

    function test_setTreasuryBps(uint256 bps) public {
        vm.assume(bps <= 10_000);
        vm.prank(admin);
        rewardForwarder.setTreasuryBps(address(token), bps);
        assertEq(rewardForwarder.treasuryBps(address(token)), bps);
    }

    function test_setTreasuryBps_revertWhen_invalidTreasuryBps(uint256 bps) public {
        vm.assume(bps > 10_000);
        vm.expectRevert(abi.encodeWithSelector(RewardForwarder.InvalidTreasuryBps.selector));
        vm.prank(admin);
        rewardForwarder.setTreasuryBps(address(token), bps);
        assertEq(rewardForwarder.treasuryBps(address(token)), 0);
    }

    function test_setTreasuryBps_revertWhen_notAdmin() public {
        vm.expectRevert(_formatAccessControlError(address(this), rewardForwarder.DEFAULT_ADMIN_ROLE()));
        rewardForwarder.setTreasuryBps(address(token), 1000);
    }

    function test_forwardRewardToken() public {
        airdrop(IERC20(token), address(rewardForwarder), 1000);
        vm.prank(admin);
        // set treasury split
        rewardForwarder.setTreasuryBps(address(token), 1000);
        // approve reward token
        rewardForwarder.approveRewardToken(address(token));
        // forward reward token
        rewardForwarder.forwardRewardToken(address(token));
        assertEq(token.balanceOf(treasury), 100);
        assertEq(token.balanceOf(destination), 900);
    }
}

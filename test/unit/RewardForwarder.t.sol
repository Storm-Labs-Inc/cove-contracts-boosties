// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { RewardForwarder } from "src/rewards/RewardForwarder.sol";
import { MockERC20RewardsGauge } from "test/mocks/MockERC20RewardsGauge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Errors } from "src/libraries/Errors.sol";

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
        destination = address(new MockERC20RewardsGauge());
        vm.label(destination, "destination");
        rewardForwarderImplementation = new RewardForwarder();
        vm.label(address(rewardForwarderImplementation), "rewardForwarderImpl");
        // clone the rewardForwarder
        rewardForwarder = RewardForwarder(_cloneContract(address(rewardForwarderImplementation)));
        vm.label(address(rewardForwarder), "rewardForwarder");
        rewardForwarder.initialize(destination);
    }

    function test_initialize() public {
        assertEq(rewardForwarder.rewardDestination(), destination);
    }

    function test_initialize_revertWhen_zeroDestination() public {
        RewardForwarder dummyRewardForwarder = RewardForwarder(_cloneContract(address(rewardForwarderImplementation)));
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        dummyRewardForwarder.initialize(address(0));
    }

    function test_approveRewardToken() public {
        // create dummy token
        rewardForwarder.approveRewardToken(address(token));
        assertEq(token.allowance(address(rewardForwarder), destination), type(uint256).max);
    }

    function test_forwardRewardToken() public {
        airdrop(IERC20(token), address(rewardForwarder), 1000);

        // approve reward token
        rewardForwarder.approveRewardToken(address(token));
        // so the entire balance should be forwarded to the destination
        assertEq(token.balanceOf(destination), 1000);

        airdrop(IERC20(token), address(rewardForwarder), 1000);

        rewardForwarder.forwardRewardToken(address(token));
        assertEq(token.balanceOf(destination), 2000);
    }
}

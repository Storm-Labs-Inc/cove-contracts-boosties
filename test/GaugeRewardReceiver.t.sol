// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { GaugeRewardReceiver } from "src/GaugeRewardReceiver.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { MockGauge } from "./mocks/MockGauge.sol";
import { MockStakingDelegateRewards } from "./mocks/MockStakingDelegateRewards.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GaugeRewardReceiverTest is BaseTest {
    using ClonesWithImmutableArgs for address;

    address public gaugeRewardReceiverImpl;
    address public gaugeRewardReceiver;
    address public mockGauge;
    address public mockToken;
    address public mockStakingDelegateRewards;

    address public constant TEST_ADDRESS_1 = 0x1111111111111111111111111111111111111111;
    address public constant TEST_ADDRESS_2 = 0x2222222222222222222222222222222222222222;
    address public constant TEST_ADDRESS_3 = 0x3333333333333333333333333333333333333333;
    address public constant TEST_ADDRESS_4 = 0x4444444444444444444444444444444444444444;

    function setUp() public override {
        gaugeRewardReceiverImpl = address(new GaugeRewardReceiver());
        mockToken = address(new ERC20Mock());
        vm.label(mockToken, "mockToken");
        mockGauge = address(new MockGauge(mockToken));
        vm.label(mockGauge, "mockGauge");
        mockStakingDelegateRewards = address(new MockStakingDelegateRewards(mockToken, TEST_ADDRESS_1));
        vm.label(mockStakingDelegateRewards, "mockStakingDelegateRewards");
    }

    function _deployCloneWithArgs(
        address stakingDelegate,
        address gauge,
        address rewardToken,
        address stakingDelegateRewards
    )
        internal
        returns (address)
    {
        return
            gaugeRewardReceiverImpl.clone(abi.encodePacked(stakingDelegate, gauge, rewardToken, stakingDelegateRewards));
    }

    function test_initialize_revertWhen_IsImplementation() public {
        vm.expectRevert("Initializable: contract is already initialized");
        GaugeRewardReceiver(gaugeRewardReceiverImpl).initialize();
    }

    function test_clone() public {
        address stakingDelegate = TEST_ADDRESS_1;
        address gauge = mockGauge;
        address rewardToken = mockToken;
        address stakingDelegateRewards = mockStakingDelegateRewards;
        gaugeRewardReceiver = _deployCloneWithArgs(stakingDelegate, gauge, rewardToken, stakingDelegateRewards);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).stakingDelegate(), stakingDelegate);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).gauge(), gauge);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).rewardToken(), rewardToken);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).stakingDelegateRewards(), stakingDelegateRewards);
    }

    function testFuzz_clone(
        address stakingDelegate,
        address gauge,
        address rewardToken,
        address stakingDelegateRewards
    )
        public
    {
        gaugeRewardReceiver = _deployCloneWithArgs(stakingDelegate, gauge, rewardToken, stakingDelegateRewards);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).stakingDelegate(), stakingDelegate);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).gauge(), gauge);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).rewardToken(), rewardToken);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).stakingDelegateRewards(), stakingDelegateRewards);
    }

    function test_initialize() public {
        address stakingDelegate = TEST_ADDRESS_1;
        address gauge = mockGauge;
        address rewardToken = mockToken;
        address stakingDelegateRewards = mockStakingDelegateRewards;
        gaugeRewardReceiver = _deployCloneWithArgs(stakingDelegate, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize();
        assertEq(IERC20(rewardToken).allowance(address(gaugeRewardReceiver), stakingDelegateRewards), type(uint256).max);
    }

    function test_harvest() public {
        address stakingDelegate = TEST_ADDRESS_1;
        address gauge = mockGauge;
        address rewardToken = mockToken;
        address stakingDelegateRewards = mockStakingDelegateRewards;
        address swapAndLock = TEST_ADDRESS_2;
        address treasury = TEST_ADDRESS_3;

        gaugeRewardReceiver = _deployCloneWithArgs(stakingDelegate, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize();

        ERC20Mock(rewardToken).mint(gauge, 100e18);
        vm.prank(stakingDelegate);
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            swapAndLock, treasury, YearnStakingDelegate.RewardSplit(1e17, 2e17, 7e17)
        );

        assertEq(IERC20(rewardToken).balanceOf(treasury), 1e17 * 100e18 / 1e18);
        assertEq(IERC20(rewardToken).balanceOf(stakingDelegateRewards), 2e17 * 100e18 / 1e18);
        assertEq(IERC20(rewardToken).balanceOf(swapAndLock), 7e17 * 100e18 / 1e18);
    }

    function test_harvest_revertWhen_NotAuthorized() public {
        address stakingDelegate = TEST_ADDRESS_1;
        address gauge = mockGauge;
        address rewardToken = mockToken;
        address stakingDelegateRewards = mockStakingDelegateRewards;
        address swapAndLock = TEST_ADDRESS_2;
        address treasury = TEST_ADDRESS_3;

        gaugeRewardReceiver = _deployCloneWithArgs(stakingDelegate, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize();

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthorized.selector));
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            swapAndLock, treasury, YearnStakingDelegate.RewardSplit(1e17, 2e17, 7e17)
        );
    }

    function test_harvest_revertWhen_InvalidRewardSplit() public {
        address stakingDelegate = TEST_ADDRESS_1;
        address gauge = mockGauge;
        address rewardToken = mockToken;
        address stakingDelegateRewards = mockStakingDelegateRewards;
        address swapAndLock = TEST_ADDRESS_2;
        address treasury = TEST_ADDRESS_3;

        gaugeRewardReceiver = _deployCloneWithArgs(stakingDelegate, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize();

        vm.prank(stakingDelegate);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardSplit.selector));
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            swapAndLock, treasury, YearnStakingDelegate.RewardSplit(1e17, 2e17, 8e17)
        );
    }

    function test_harvest_passWhen_NoRewards() public {
        address stakingDelegate = TEST_ADDRESS_1;
        address gauge = mockGauge;
        address rewardToken = mockToken;
        address stakingDelegateRewards = mockStakingDelegateRewards;
        address swapAndLock = TEST_ADDRESS_2;
        address treasury = TEST_ADDRESS_3;

        gaugeRewardReceiver = _deployCloneWithArgs(stakingDelegate, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize();

        vm.prank(stakingDelegate);
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            swapAndLock, treasury, YearnStakingDelegate.RewardSplit(1e17, 2e17, 7e17)
        );

        assertEq(IERC20(rewardToken).balanceOf(treasury), 0);
        assertEq(IERC20(rewardToken).balanceOf(stakingDelegateRewards), 0);
        assertEq(IERC20(rewardToken).balanceOf(swapAndLock), 0);
    }
}

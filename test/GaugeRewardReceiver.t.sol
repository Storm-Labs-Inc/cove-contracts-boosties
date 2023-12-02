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
    address public gauge;
    address public rewardToken;
    address public stakingDelegateRewards;

    address public constant STAKING_DELEGATE = 0x1111111111111111111111111111111111111111;
    address public constant SWAP_AND_LOCK = 0x2222222222222222222222222222222222222222;
    address public constant TREASURY = 0x3333333333333333333333333333333333333333;

    function setUp() public override {
        gaugeRewardReceiverImpl = address(new GaugeRewardReceiver());
        rewardToken = address(new ERC20Mock());
        vm.label(rewardToken, "rewardToken");
        gauge = address(new MockGauge(rewardToken));
        vm.label(gauge, "gauge");
        stakingDelegateRewards = address(new MockStakingDelegateRewards(rewardToken, STAKING_DELEGATE));
        vm.label(stakingDelegateRewards, "stakingDelegateRewards");
    }

    function _deployCloneWithArgs(
        address stakingDelegateAddress,
        address gaugeAddress,
        address rewardTokenAddress,
        address stakingDelegateRewardsAddress
    )
        internal
        returns (address)
    {
        return gaugeRewardReceiverImpl.clone(
            abi.encodePacked(stakingDelegateAddress, gaugeAddress, rewardTokenAddress, stakingDelegateRewardsAddress)
        );
    }

    function test_initialize_revertWhen_IsImplementation() public {
        vm.expectRevert("Initializable: contract is already initialized");
        GaugeRewardReceiver(gaugeRewardReceiverImpl).initialize();
    }

    function test_clone() public {
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).stakingDelegate(), STAKING_DELEGATE);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).gauge(), gauge);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).rewardToken(), rewardToken);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).stakingDelegateRewards(), stakingDelegateRewards);
    }

    function testFuzz_clone(
        address _stakingDelegate,
        address _gauge,
        address _rewardToken,
        address _stakingDelegateRewards
    )
        public
    {
        gaugeRewardReceiver = _deployCloneWithArgs(_stakingDelegate, _gauge, _rewardToken, _stakingDelegateRewards);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).stakingDelegate(), _stakingDelegate);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).gauge(), _gauge);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).rewardToken(), _rewardToken);
        assertEq(GaugeRewardReceiver(gaugeRewardReceiver).stakingDelegateRewards(), _stakingDelegateRewards);
    }

    function test_initialize() public {
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize();
        assertEq(IERC20(rewardToken).allowance(address(gaugeRewardReceiver), stakingDelegateRewards), type(uint256).max);
    }

    function test_harvest() public {
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize();

        uint256 totalRewardAmount = 100e18;
        YearnStakingDelegate.RewardSplit memory rewardSplit = YearnStakingDelegate.RewardSplit(1e17, 2e17, 7e17);
        ERC20Mock(rewardToken).mint(gauge, totalRewardAmount);
        vm.prank(STAKING_DELEGATE);
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(SWAP_AND_LOCK, TREASURY, rewardSplit);

        uint256 expectedTreasuryAmount = rewardSplit.treasury * totalRewardAmount / 1e18;
        uint256 expectedSwapAndLockAmount = rewardSplit.lock * totalRewardAmount / 1e18;
        uint256 expectedStrategyAmount = totalRewardAmount - expectedTreasuryAmount - expectedSwapAndLockAmount;

        assertEq(IERC20(rewardToken).balanceOf(gaugeRewardReceiver), 0);
        assertEq(IERC20(rewardToken).balanceOf(TREASURY), expectedTreasuryAmount);
        assertEq(IERC20(rewardToken).balanceOf(stakingDelegateRewards), expectedStrategyAmount);
        assertEq(IERC20(rewardToken).balanceOf(SWAP_AND_LOCK), expectedSwapAndLockAmount);
    }

    function testFuzz_harvest(uint256 amount, uint80 treasurySplit, uint80 strategySplit) public {
        vm.assume(amount < type(uint256).max / 1e18);
        vm.assume(uint256(treasurySplit) + strategySplit < 1e18);
        uint80 lockSplit = 1e18 - treasurySplit - strategySplit;

        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize();

        ERC20Mock(rewardToken).mint(gauge, amount);
        vm.prank(STAKING_DELEGATE);
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            SWAP_AND_LOCK, TREASURY, YearnStakingDelegate.RewardSplit(treasurySplit, strategySplit, lockSplit)
        );

        uint256 expectedTreasuryAmount = treasurySplit * amount / 1e18;
        uint256 expectedSwapAndLockAmount = lockSplit * amount / 1e18;
        uint256 expectedStrategyAmount = amount - expectedTreasuryAmount - expectedSwapAndLockAmount;

        assertEq(IERC20(rewardToken).balanceOf(gaugeRewardReceiver), 0);
        assertEq(IERC20(rewardToken).balanceOf(TREASURY), expectedTreasuryAmount);
        assertEq(IERC20(rewardToken).balanceOf(stakingDelegateRewards), expectedStrategyAmount);
        assertEq(IERC20(rewardToken).balanceOf(SWAP_AND_LOCK), expectedSwapAndLockAmount);
    }

    function test_harvest_revertWhen_NotAuthorized() public {
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize();

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthorized.selector));
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            SWAP_AND_LOCK, TREASURY, YearnStakingDelegate.RewardSplit(1e17, 2e17, 7e17)
        );
    }

    function test_harvest_revertWhen_InvalidRewardSplit() public {
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize();

        vm.prank(STAKING_DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardSplit.selector));
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            SWAP_AND_LOCK, TREASURY, YearnStakingDelegate.RewardSplit(1e17, 2e17, 8e17)
        );
    }

    function test_harvest_passWhen_NoRewards() public {
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize();

        vm.prank(STAKING_DELEGATE);
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            SWAP_AND_LOCK, TREASURY, YearnStakingDelegate.RewardSplit(1e17, 2e17, 7e17)
        );

        assertEq(IERC20(rewardToken).balanceOf(TREASURY), 0);
        assertEq(IERC20(rewardToken).balanceOf(stakingDelegateRewards), 0);
        assertEq(IERC20(rewardToken).balanceOf(SWAP_AND_LOCK), 0);
    }
}

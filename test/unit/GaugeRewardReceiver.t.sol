// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { GaugeRewardReceiver } from "src/GaugeRewardReceiver.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { Errors } from "src/libraries/Errors.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { MockGauge } from "test/mocks/MockGauge.sol";
import { MockStakingDelegateRewards } from "test/mocks/MockStakingDelegateRewards.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";

contract GaugeRewardReceiver_Test is BaseTest {
    using ClonesWithImmutableArgs for address;

    address public gaugeRewardReceiverImpl;
    address public gaugeRewardReceiver;
    address public gauge;
    address public rewardToken;
    address public stakingDelegateRewards;
    address public coveYfiRewardForwarder;
    address public admin;

    address public constant STAKING_DELEGATE = 0x1111111111111111111111111111111111111111;
    address public constant SWAP_AND_LOCK = 0x2222222222222222222222222222222222222222;
    address public constant TREASURY = 0x3333333333333333333333333333333333333333;

    function setUp() public override {
        admin = createUser("admin");
        coveYfiRewardForwarder = createUser("coveYfiRewardForwarder");
        gaugeRewardReceiverImpl = address(new GaugeRewardReceiver());
        rewardToken = address(new ERC20Mock());
        vm.label(rewardToken, "rewardToken");
        gauge = address(new MockGauge(address(0)));
        MockGauge(gauge).setRewardToken(rewardToken);
        vm.label(gauge, "gauge");
        stakingDelegateRewards = address(new MockStakingDelegateRewards(rewardToken));
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
        GaugeRewardReceiver(gaugeRewardReceiverImpl).initialize(address(0));
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
        GaugeRewardReceiver(gaugeRewardReceiver).initialize(admin);
        assertEq(IERC20(rewardToken).allowance(address(gaugeRewardReceiver), stakingDelegateRewards), type(uint256).max);
    }

    function test_harvest() public {
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize(admin);

        uint256 totalRewardAmount = 100e18;
        IYearnStakingDelegate.RewardSplit memory rewardSplit =
            IYearnStakingDelegate.RewardSplit(0.1e18, 0.2e18, 0.3e18, 0.4e18);
        ERC20Mock(rewardToken).mint(gauge, totalRewardAmount);
        vm.prank(STAKING_DELEGATE);
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(SWAP_AND_LOCK, TREASURY, coveYfiRewardForwarder, rewardSplit);

        uint256 expectedTreasuryAmount = rewardSplit.treasury * totalRewardAmount / 1e18;
        uint256 expectedSwapAndLockAmount = rewardSplit.lock * totalRewardAmount / 1e18;
        uint256 expectedStrategyAmount = totalRewardAmount - expectedTreasuryAmount - expectedSwapAndLockAmount;

        assertEq(IERC20(rewardToken).balanceOf(gaugeRewardReceiver), 0);
        assertEq(IERC20(rewardToken).balanceOf(TREASURY), expectedTreasuryAmount);
        assertEq(IERC20(rewardToken).balanceOf(stakingDelegateRewards), expectedStrategyAmount);
        assertEq(IERC20(rewardToken).balanceOf(SWAP_AND_LOCK), expectedSwapAndLockAmount);
    }

    function testFuzz_harvest(uint256 amount, uint64 treasurySplit, uint64 coveYfiSplit, uint64 strategySplit) public {
        vm.assume(amount < type(uint256).max / 1e18);
        vm.assume(uint256(treasurySplit) + strategySplit + coveYfiSplit < 1e18);
        uint64 lockSplit = 1e18 - treasurySplit - strategySplit;

        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize(admin);

        ERC20Mock(rewardToken).mint(gauge, amount);
        vm.prank(STAKING_DELEGATE);
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            SWAP_AND_LOCK,
            TREASURY,
            coveYfiRewardForwarder,
            IYearnStakingDelegate.RewardSplit(treasurySplit, coveYfiSplit, strategySplit, lockSplit)
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
        GaugeRewardReceiver(gaugeRewardReceiver).initialize(admin);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthorized.selector));
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            SWAP_AND_LOCK,
            TREASURY,
            coveYfiRewardForwarder,
            IYearnStakingDelegate.RewardSplit(0.1e18, 0.2e18, 0.3e18, 0.4e18)
        );
    }

    function test_harvest_revertWhen_InvalidRewardSplit() public {
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize(admin);

        vm.prank(STAKING_DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardSplit.selector));
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            SWAP_AND_LOCK,
            TREASURY,
            coveYfiRewardForwarder,
            IYearnStakingDelegate.RewardSplit(0.1e18, 0.2e18, 0.3e18, 0.5e18)
        );
    }

    function test_harvest_passWhen_NoRewards() public {
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize(admin);

        vm.prank(STAKING_DELEGATE);
        GaugeRewardReceiver(gaugeRewardReceiver).harvest(
            SWAP_AND_LOCK,
            TREASURY,
            coveYfiRewardForwarder,
            IYearnStakingDelegate.RewardSplit(0.1e18, 0.2e18, 0.3e18, 0.4e18)
        );

        assertEq(IERC20(rewardToken).balanceOf(TREASURY), 0);
        assertEq(IERC20(rewardToken).balanceOf(stakingDelegateRewards), 0);
        assertEq(IERC20(rewardToken).balanceOf(SWAP_AND_LOCK), 0);
    }

    function testFuzz_rescue(uint256 amount) public {
        vm.assume(amount != 0);
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize(admin);

        ERC20Mock rescueToken = new ERC20Mock();
        rescueToken.mint(gaugeRewardReceiver, amount);
        vm.prank(admin);
        GaugeRewardReceiver(gaugeRewardReceiver).rescue(rescueToken, admin, amount);

        assertEq(rescueToken.balanceOf(gaugeRewardReceiver), 0);
        assertEq(rescueToken.balanceOf(admin), amount);
    }

    function test_rescue_revertWhen_CannotRescueRewardToken() public {
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize(admin);

        ERC20Mock(rewardToken).mint(gaugeRewardReceiver, 100e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.CannotRescueRewardToken.selector));
        vm.prank(admin);
        GaugeRewardReceiver(gaugeRewardReceiver).rescue(IERC20(rewardToken), admin, 100e18);
    }

    function testFuzz_rescue_revertWhen_CallerIsNotTheAdmin(address a) public {
        vm.assume(a != admin);
        gaugeRewardReceiver = _deployCloneWithArgs(STAKING_DELEGATE, gauge, rewardToken, stakingDelegateRewards);
        GaugeRewardReceiver(gaugeRewardReceiver).initialize(admin);

        ERC20Mock(rewardToken).mint(gaugeRewardReceiver, 100e18);
        vm.expectRevert(_formatAccessControlError(a, DEFAULT_ADMIN_ROLE));
        vm.prank(a);
        GaugeRewardReceiver(gaugeRewardReceiver).rescue(IERC20(rewardToken), address(0), 100e18);
    }
}

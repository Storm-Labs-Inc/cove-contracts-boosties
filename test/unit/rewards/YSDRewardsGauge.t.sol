// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { YSDRewardsGauge } from "src/rewards/YSDRewardsGauge.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { BaseRewardsGauge } from "src/rewards/BaseRewardsGauge.sol";
import { MockStakingDelegateRewards } from "test/mocks/MockStakingDelegateRewards.sol";
import { YearnGaugeStrategy } from "src/strategies/YearnGaugeStrategy.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract YSDRewardsGauge_Test is BaseTest {
    YSDRewardsGauge public rewardsGaugeImplementation;
    YSDRewardsGauge public rewardsGauge;
    YearnGaugeStrategy public strategy;
    MockYearnStakingDelegate public ysd;
    ERC20 public dummyGaugeAsset;
    ERC20 public dummyRewardToken;
    address public admin;
    address public alice;

    function setUp() public override {
        admin = createUser("admin");
        alice = createUser("alice");
        // deploy dummy token
        dummyGaugeAsset = new ERC20("dummy", "DUMB");
        vm.label(address(dummyGaugeAsset), "dummyGaugeAsset");
        // deploy dummy reward token
        dummyRewardToken = new ERC20("dummyReward", "DUMBR");
        vm.label(address(dummyRewardToken), "dummyRewardToken");
        // deploy Mock Yearn Staking Delegate
        ysd = MockYearnStakingDelegate(new MockYearnStakingDelegate());
        vm.label(address(ysd), "ysd");
        rewardsGaugeImplementation = new YSDRewardsGauge();
        vm.label(address(rewardsGaugeImplementation), "rewardsGauge");
        // clone the implementation
        rewardsGauge = YSDRewardsGauge(_cloneContract(address(rewardsGaugeImplementation)));
        vm.label(address(rewardsGauge), "rewardsGauge");
        vm.prank(admin);

        // Mock YearnGaugeStrategy for establishing max deposit limit
        strategy = YearnGaugeStrategy(createUser("strategy"));
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(YearnGaugeStrategy.maxTotalAssets.selector),
            abi.encode(type(uint256).max)
        );
        vm.mockCall(address(strategy), abi.encodeWithSelector(IERC4626.totalAssets.selector), abi.encode(0));

        rewardsGauge.initialize(address(dummyGaugeAsset), address(ysd), address(strategy));
    }

    function test_initialize() public {
        assertEq(rewardsGauge.asset(), address(dummyGaugeAsset), "asset was not set correctly");
        assertEq(rewardsGauge.yearnStakingDelegate(), address(ysd), "ysd was not set correctly");
        // check allowance on init
        assertEq(
            IERC20(dummyGaugeAsset).allowance(address(rewardsGauge), address(ysd)),
            type(uint256).max,
            "allowance was not set"
        );
    }

    function test_initialize_revertWhen_CallingInheritedInitialize() public {
        YSDRewardsGauge clone = YSDRewardsGauge(_cloneContract(address(rewardsGaugeImplementation)));
        vm.expectRevert(YSDRewardsGauge.InvalidInitialization.selector);
        clone.initialize(address(dummyGaugeAsset));
    }

    function test_initialize_revertWhen_ZeroAddress() public {
        YSDRewardsGauge clone = YSDRewardsGauge(_cloneContract(address(rewardsGaugeImplementation)));
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.ZeroAddress.selector));
        clone.initialize(address(dummyGaugeAsset), address(0), address(0xbeef));
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.ZeroAddress.selector));
        clone.initialize(address(dummyGaugeAsset), address(0xbeef), address(0));
    }

    function test_setStakingDelegateRewardsReceiver() public {
        // create mock MockStakingDelegateRewards
        MockStakingDelegateRewards mockStakingDelegateRewards =
            new MockStakingDelegateRewards(address(dummyRewardToken));
        // set mock contract as the receiver
        ysd.setGaugeStakingRewards(address(mockStakingDelegateRewards));
        vm.prank(admin);
        rewardsGauge.setStakingDelegateRewardsReceiver(address(2));
        assertEq(mockStakingDelegateRewards.receiver(), address(2), "receiver was not set");
    }

    function test_setStakingDelegateRewardsReceiver_revertWhen_notAdmin() public {
        vm.expectRevert(_formatAccessControlError(address(this), rewardsGauge.DEFAULT_ADMIN_ROLE()));
        rewardsGauge.setStakingDelegateRewardsReceiver(address(2));
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        rewardsGauge.deposit(amount, alice);
        assertEq(ysd.balanceOf(address(rewardsGauge), address(dummyGaugeAsset)), amount, "balance was not updated");
        assertEq(dummyGaugeAsset.balanceOf(alice), 0, "assets were not taken");
        assertEq(
            dummyGaugeAsset.balanceOf(address(ysd)), rewardsGauge.totalAssets(), "totalAssets reported incorrectly"
        );
        assertEq(rewardsGauge.balanceOf(alice), amount, "shares were not given for deposit");
    }

    function testFuzz_deposit_revertWhen_MaxTotalAssetsExceeded(uint256 amount) public {
        vm.assume(amount > 0);
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        vm.mockCall(
            address(strategy), abi.encodeWithSelector(YearnGaugeStrategy.maxTotalAssets.selector), abi.encode(0)
        );
        vm.expectRevert(YSDRewardsGauge.MaxTotalAssetsExceeded.selector);
        rewardsGauge.deposit(amount, alice);
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount > 0);
        amount = bound(amount, 0, type(uint256).max - 1); // avoid overflow in ERC4626._convertToShares
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        rewardsGauge.deposit(amount, alice);
        rewardsGauge.redeem(rewardsGauge.balanceOf(alice), alice, alice);
        assertEq(ysd.balanceOf(address(rewardsGauge), address(dummyGaugeAsset)), 0, "balance was not updated");
        assertEq(rewardsGauge.balanceOf(alice), 0, "shares were not given for deposit");
        assertEq(dummyGaugeAsset.balanceOf(alice), amount, "assets were not given back");
    }

    function testFuzz_withdraw_revertsWhen_noSpenderAllowance(uint256 amount) public {
        amount = bound(amount, 1, (type(uint256).max - 1) / 2); // avoid overflow in ERC4626._convertToShares
        // create bob
        address bob = createUser("bob");
        // alice and bob gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        airdrop(dummyGaugeAsset, bob, amount);
        // alice deposits
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        rewardsGauge.deposit(amount, alice);
        // bob deposits
        vm.startPrank(bob);
        dummyGaugeAsset.approve(address(rewardsGauge), type(uint256).max);
        rewardsGauge.deposit(amount, bob);
        // bob tries to redeem alice's shares
        uint256 shares = rewardsGauge.balanceOf(alice);
        vm.expectRevert("ERC20: insufficient allowance");
        rewardsGauge.redeem(shares, bob, alice);
    }
}

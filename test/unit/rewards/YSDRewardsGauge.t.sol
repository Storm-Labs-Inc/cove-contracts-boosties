// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { YSDRewardsGauge } from "src/rewards/YSDRewardsGauge.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { BaseRewardsGauge } from "src/rewards/BaseRewardsGauge.sol";
import { MockStakingDelegateRewards } from "test/mocks/MockStakingDelegateRewards.sol";
import { YearnGaugeStrategy } from "src/strategies/YearnGaugeStrategy.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";

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

        // Mock YearnGaugeStrategy for establishing max deposit limit
        strategy = YearnGaugeStrategy(createUser("strategy"));
        vm.prank(admin);
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

    function test_initialize_revertWhen_ZeroAddress() public {
        YSDRewardsGauge clone = YSDRewardsGauge(_cloneContract(address(rewardsGaugeImplementation)));
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.ZeroAddress.selector));
        clone.initialize(address(0), address(0xbeef), address(0xbeef));
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.ZeroAddress.selector));
        clone.initialize(address(0xbeef), address(0), address(0xbeef));
        vm.expectRevert(abi.encodeWithSelector(BaseRewardsGauge.ZeroAddress.selector));
        clone.initialize(address(0xbeef), address(0xbeef), address(0));
    }

    function testFuzz_initialize_revetWhen_AlreadyInitialized(address asset_, address ysd_, address strategy_) public {
        vm.assume(asset_ != address(0) && ysd_ != address(0) && strategy_ != address(0));
        vm.expectRevert("Initializable: contract is already initialized");
        rewardsGauge.initialize(asset_, ysd_, strategy_);
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
        vm.expectRevert(_formatAccessControlError(address(this), DEFAULT_ADMIN_ROLE));
        rewardsGauge.setStakingDelegateRewardsReceiver(address(2));
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        // set availableDepositLimit to max
        vm.mockCall(
            address(ysd),
            abi.encodeWithSelector(IYearnStakingDelegate.availableDepositLimit.selector, address(dummyGaugeAsset)),
            abi.encode(type(uint256).max)
        );
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
        // set availableDepositLimit to 0
        vm.mockCall(
            address(ysd),
            abi.encodeWithSelector(IYearnStakingDelegate.availableDepositLimit.selector, address(dummyGaugeAsset)),
            abi.encode(0)
        );
        vm.expectRevert("ERC4626: deposit more than max");
        rewardsGauge.deposit(amount, alice);
    }

    function testFuzz_deposit_revertWhen_Paused(uint256 amount) public {
        vm.assume(amount > 0);
        airdrop(dummyGaugeAsset, alice, amount);
        vm.prank(admin);
        rewardsGauge.pause();
        vm.startPrank(alice);
        dummyGaugeAsset.approve(address(rewardsGauge), amount);
        vm.expectRevert("ERC4626: deposit more than max");
        rewardsGauge.deposit(amount, alice);
    }

    function test_maxDeposit() public {
        // set availableDepositLimit to max
        vm.mockCall(
            address(ysd),
            abi.encodeWithSelector(IYearnStakingDelegate.availableDepositLimit.selector, address(dummyGaugeAsset)),
            abi.encode(type(uint256).max)
        );
        assertEq(rewardsGauge.maxDeposit(address(0)), type(uint256).max, "maxDeposit was not set correctly");

        vm.prank(admin);
        // pause
        rewardsGauge.pause();
        assertEq(rewardsGauge.maxDeposit(address(0)), 0, "maxDeposit was not set correctly");
    }

    function test_maxMint() public {
        // set availableDepositLimit to max
        vm.mockCall(
            address(ysd),
            abi.encodeWithSelector(IYearnStakingDelegate.availableDepositLimit.selector, address(dummyGaugeAsset)),
            abi.encode(type(uint256).max)
        );
        assertEq(rewardsGauge.maxMint(address(0)), type(uint256).max, "maxMint was not set correctly");

        vm.prank(admin);
        // pause
        rewardsGauge.pause();
        assertEq(rewardsGauge.maxMint(address(0)), 0, "maxMint was not set correctly");
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount > 0);
        amount = bound(amount, 0, type(uint256).max - 1); // avoid overflow in ERC4626._convertToShares
        // alice gets some mockgauge tokens by depositing dummy token
        airdrop(dummyGaugeAsset, alice, amount);
        // set availableDepositLimit to max
        vm.mockCall(
            address(ysd),
            abi.encodeWithSelector(IYearnStakingDelegate.availableDepositLimit.selector, address(dummyGaugeAsset)),
            abi.encode(type(uint256).max)
        );
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
        // set availableDepositLimit to max
        vm.mockCall(
            address(ysd),
            abi.encodeWithSelector(IYearnStakingDelegate.availableDepositLimit.selector, address(dummyGaugeAsset)),
            abi.encode(type(uint256).max)
        );
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

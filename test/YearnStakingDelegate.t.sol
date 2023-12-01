// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { IStrategy } from "@tokenized-strategy/interfaces/IStrategy.sol";
import { ISnapshotDelegateRegistry } from "src/interfaces/deps/snapshot/ISnapshotDelegateRegistry.sol";
import { IYfiRewardPool } from "src/interfaces/deps/yearn/veYFI/IYfiRewardPool.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

contract YearnStakingDelegateTest is YearnV3BaseTest {
    using SafeERC20 for IERC20;

    YearnStakingDelegate public yearnStakingDelegate;
    IStrategy public mockStrategy;
    address public testVault;
    address public testGauge;
    address public stakingRewards;
    address public swapAndLock;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 10e18;
    uint256 public constant YFI_MAX_SUPPLY = 36_666e18;

    // Addresses
    address public alice;
    address public manager;
    address public wrappedStrategy;
    address public treasury;

    CurveRouterSwapper.CurveSwapParams internal _routerParams;

    function setUp() public override {
        super.setUp();

        // create alice who will be lock YFI via the yearnStakingDelegate
        alice = createUser("alice");
        // create manager of the yearnStakingDelegate
        manager = createUser("manager");
        // create an address that will act as a wrapped strategy
        wrappedStrategy = createUser("wrappedStrategy");
        // create an address that will act as a treasury
        treasury = createUser("treasury");

        // Deploy vault
        testVault = deployVaultV3("USDC Test Vault", MAINNET_USDC, new address[](0));
        // Deploy gauge
        testGauge = deployGaugeViaFactory(testVault, admin, "USDC Test Vault Gauge");

        // Give admin some dYFI
        airdrop(ERC20(MAINNET_DYFI), admin, DYFI_REWARD_AMOUNT);

        // Start new rewards
        vm.startPrank(admin);
        IERC20(MAINNET_DYFI).approve(testGauge, DYFI_REWARD_AMOUNT);
        IGauge(testGauge).queueNewRewards(DYFI_REWARD_AMOUNT);
        vm.stopPrank();

        if (IERC20(MAINNET_DYFI).balanceOf(testGauge) != DYFI_REWARD_AMOUNT) {
            revert Errors.QueueNewRewardsFailed();
        }

        address receiver = setUpGaugeRewardReceiverImplementation(admin);
        yearnStakingDelegate = new YearnStakingDelegate(receiver, treasury, admin, manager);
        stakingRewards = setUpStakingDelegateRewards(admin, MAINNET_DYFI, address(yearnStakingDelegate));
        swapAndLock = setUpSwapAndLock(admin, address(yearnStakingDelegate), stakingRewards);

        // Setup approvals for YFI spending
        vm.startPrank(alice);
        IERC20(MAINNET_YFI).approve(MAINNET_VE_YFI, type(uint256).max);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), type(uint256).max);
        vm.stopPrank();
    }

    function testFuzz_constructor(address noAdminRole, address noManagerRole) public {
        vm.assume(noAdminRole != admin);
        // manager role is given to admin and manager
        vm.assume(noManagerRole != manager && noManagerRole != admin);
        // Check for storage variables default values
        assertEq(yearnStakingDelegate.yfi(), MAINNET_YFI);
        assertEq(yearnStakingDelegate.dYfi(), MAINNET_DYFI);
        assertEq(yearnStakingDelegate.veYfi(), MAINNET_VE_YFI);
        assertTrue(yearnStakingDelegate.shouldPerpetuallyLock());
        (uint80 treasurySplit, uint80 strategySplit, uint80 veYfiSplit) =
            yearnStakingDelegate.gaugeRewardSplit(testGauge);
        assertEq(treasurySplit, 0);
        assertEq(strategySplit, 0);
        assertEq(veYfiSplit, 0);
        // Check for roles
        assertTrue(yearnStakingDelegate.hasRole(yearnStakingDelegate.MANAGER_ROLE(), manager));
        assertTrue(!yearnStakingDelegate.hasRole(yearnStakingDelegate.MANAGER_ROLE(), noManagerRole));
        assertTrue(yearnStakingDelegate.hasRole(yearnStakingDelegate.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(!yearnStakingDelegate.hasRole(yearnStakingDelegate.DEFAULT_ADMIN_ROLE(), noAdminRole));
        // Check for approvals
        assertEq(IERC20(MAINNET_YFI).allowance(address(yearnStakingDelegate), MAINNET_VE_YFI), type(uint256).max);
    }

    function _setGaugeRewards() internal {
        vm.prank(manager);
        yearnStakingDelegate.addGaugeRewards(testGauge, stakingRewards);
    }

    function _setRewardSplit(address gauge, uint80 treasurySplit, uint80 strategySplit, uint80 veYfiSplit) internal {
        vm.prank(admin);
        yearnStakingDelegate.setRewardSplit(gauge, treasurySplit, strategySplit, veYfiSplit);
    }

    function _lockYfiForYSD(uint256 amount) internal {
        airdrop(ERC20(MAINNET_YFI), alice, amount);
        vm.prank(alice);
        yearnStakingDelegate.lockYfi(amount);
    }

    function _lockYfiForUser(address user, uint256 amount, uint256 duration) internal {
        airdrop(ERC20(MAINNET_YFI), user, amount);
        vm.startPrank(user);
        IERC20(MAINNET_YFI).approve(MAINNET_VE_YFI, amount);
        IVotingYFI(MAINNET_VE_YFI).modify_lock(amount, block.timestamp + duration, address(user));
        vm.stopPrank();
    }

    function test_lockYFI() public {
        _lockYfiForYSD(1e18);
        assertEq(IERC20(MAINNET_YFI).balanceOf(address(yearnStakingDelegate)), 0, "lock failed");
        assertEq(
            IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), 999_999_999_971_481_600, "lock failed"
        );
    }

    function test_lockYFI_revertWhen_WithZeroAmount() public {
        uint256 lockAmount = 0;
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        vm.prank(alice);
        yearnStakingDelegate.lockYfi(lockAmount);
    }

    function test_lockYFI_revertWhen_PerpetualLockDisabled() public {
        vm.prank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        uint256 lockAmount = 1e18;
        airdrop(ERC20(MAINNET_YFI), alice, lockAmount);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockDisabled.selector));
        yearnStakingDelegate.lockYfi(lockAmount);
    }

    function testFuzz_lockYFI_revertWhen_CreatingLockWithLessThanMinAmount(uint256 lockAmount) public {
        vm.assume(lockAmount > 0);
        vm.assume(lockAmount < 1e18);
        airdrop(ERC20(MAINNET_YFI), alice, lockAmount);
        vm.prank(alice);
        vm.expectRevert();
        yearnStakingDelegate.lockYfi(lockAmount);
    }

    function testFuzz_lockYFI(uint256 lockAmount) public {
        vm.assume(lockAmount >= 1e18);
        vm.assume(lockAmount <= YFI_MAX_SUPPLY);
        _lockYfiForYSD(lockAmount);

        assertEq(IERC20(MAINNET_YFI).balanceOf(address(yearnStakingDelegate)), 0, "lock failed");
        assertGt(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), lockAmount - 1e9, "lock failed");
        assertLe(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), lockAmount, "lock failed");
    }

    function test_earlyUnlock() public {
        _lockYfiForYSD(1e18);

        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(admin);
        vm.stopPrank();

        assertEq(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
    }

    function testFuzz_earlyUnlock(uint256 lockAmount) public {
        vm.assume(lockAmount >= 1e18);
        vm.assume(lockAmount <= YFI_MAX_SUPPLY);
        _lockYfiForYSD(lockAmount);

        vm.startPrank(admin);
        yearnStakingDelegate.setPerpetualLock(false);
        yearnStakingDelegate.earlyUnlock(admin);
        vm.stopPrank();

        assertEq(IERC20(MAINNET_VE_YFI).balanceOf(address(yearnStakingDelegate)), 0, "early unlock failed");
    }

    function test_earlyUnlock_revertWhen_PerpeutalLockEnabled() public {
        _lockYfiForYSD(1e18);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.PerpetualLockEnabled.selector));
        yearnStakingDelegate.earlyUnlock(admin);
    }

    function _depositGaugeTokensToYSD(address from, uint256 amount) internal {
        airdrop(ERC20(testGauge), from, amount);
        vm.startPrank(from);
        IERC20(testGauge).approve(address(yearnStakingDelegate), amount);
        yearnStakingDelegate.deposit(testGauge, amount);
        vm.stopPrank();
    }

    function testFuzz_depositToGauge(uint256 vaultBalance) public {
        vm.assume(vaultBalance > 0);

        _depositGaugeTokensToYSD(wrappedStrategy, vaultBalance);

        // Check the yearn staking delegate has received the gauge tokens
        assertEq(IERC20(testGauge).balanceOf(address(yearnStakingDelegate)), vaultBalance, "depositToGauge failed");
        // Check the gauge has received the vault tokens
        assertEq(IERC20(testVault).balanceOf(testGauge), vaultBalance, "depositToGauge failed");
    }

    function testFuzz_depositToGauge_revertWhen_NoAssociatedGauge(uint256 vaultBalance) public {
        vm.assume(vaultBalance > 0);

        airdrop(ERC20(testVault), wrappedStrategy, vaultBalance);

        vm.startPrank(wrappedStrategy);
        IERC20(testVault).approve(address(yearnStakingDelegate), vaultBalance);
        vm.expectRevert(abi.encodeWithSelector(Errors.NoAssociatedGauge.selector));
        yearnStakingDelegate.deposit(testVault, vaultBalance);
        vm.stopPrank();
    }

    function testFuzz_withdrawFromGauge(uint256 vaultBalance) public {
        vm.assume(vaultBalance > 0);

        _depositGaugeTokensToYSD(wrappedStrategy, vaultBalance);

        // Start withdraw process
        vm.startPrank(wrappedStrategy);
        yearnStakingDelegate.withdraw(testVault, vaultBalance);
        vm.stopPrank();

        // Check the yearn staking delegate has released the gauge tokens
        assertEq(IERC20(testGauge).balanceOf(address(yearnStakingDelegate)), 0, "withdrawFromGauge failed");
        // Check the gauge has released the vault tokens
        assertEq(IERC20(testVault).balanceOf(testGauge), 0, "withdrawFromGauge failed");
        // Check that wrappedStrategy has received the vault tokens
        assertEq(IERC20(testVault).balanceOf(wrappedStrategy), vaultBalance, "withdrawFromGauge failed");
    }

    function test_harvest_revertWhen_NoAssociatedGauge() public {
        vm.startPrank(wrappedStrategy);
        vm.expectRevert(abi.encodeWithSelector(Errors.NoAssociatedGauge.selector));
        yearnStakingDelegate.harvest(testVault);
        vm.stopPrank();
    }

    function test_harvest_passWhen_NoVeYFI() public {
        _depositGaugeTokensToYSD(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        uint256 rewardAmount = yearnStakingDelegate.harvest(testVault);

        // Check that the vault has received the rewards
        // expect to be close to 10% of the rewards, giving 90% as the penalty
        assertEq(rewardAmount, IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy), "harvest did not return correct value");
        assertLe(
            IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy),
            DYFI_REWARD_AMOUNT / 10,
            "harvested reward amount is incorrect"
        );
        assertApproxEqRel(
            IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy),
            DYFI_REWARD_AMOUNT / 10,
            0.01e18,
            "harvested reward amount is incorrect"
        );
    }

    function test_harvest_passWhen_SomeVeYFI() public {
        _lockYfiForYSD(1e18);
        _depositGaugeTokensToYSD(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        uint256 rewardAmount = yearnStakingDelegate.harvest(testVault);

        // Check that the vault has received the rewards
        // expect to be higher than 10% of the rewards due to the 1 YFI locked
        assertEq(rewardAmount, IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy), "harvest did not return correct value");
        assertGt(
            IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy),
            DYFI_REWARD_AMOUNT / 10,
            "harvested reward amount is incorrect"
        );
        assertApproxEqRel(
            IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy),
            DYFI_REWARD_AMOUNT / 10,
            0.05e18,
            "harvested reward amount is incorrect"
        );
    }

    function test_harvest_passWhen_LargeVeYFI() public {
        _lockYfiForYSD(ALICE_YFI);
        _depositGaugeTokensToYSD(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Harvest
        vm.prank(wrappedStrategy);
        uint256 rewardAmount = yearnStakingDelegate.harvest(testVault);

        // Check that the vault has received the rewards
        // expect to be close to 100% of the rewards
        assertEq(rewardAmount, IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy), "harvest did not return correct value");
        assertApproxEqRel(
            IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy), DYFI_REWARD_AMOUNT, 0.01e18, "harvest failed"
        );
    }

    function test_harvest_passWhen_WithVeYfiSplit() public {
        _lockYfiForYSD(1e18);
        _setRewardSplit(testGauge, 0.3e18, 0.3e18, 0.4e18);
        _depositGaugeTokensToYSD(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);

        // Reward amount is slightly higher than 1e18 due to Alice locking 1e18 YFI as veYFI.
        uint256 actualRewardAmount = 1_016_092_352_451_786_806;

        // Calculate split amounts strategy split amount
        uint256 estimatedStrategySplit = actualRewardAmount * 0.3e18 / 1e18;
        uint256 estimatedTreasurySplit = actualRewardAmount * 0.3e18 / 1e18;
        uint256 estimatedVeYfiSplit = actualRewardAmount * 0.4e18 / 1e18;

        // Harvest
        vm.prank(wrappedStrategy);
        uint256 rewardAmount = yearnStakingDelegate.harvest(testVault);

        uint256 strategyDYfiBalance = IERC20(MAINNET_DYFI).balanceOf(wrappedStrategy);
        assertEq(rewardAmount, strategyDYfiBalance, "harvest did not return correct value");
        assertEq(strategyDYfiBalance, estimatedStrategySplit, "strategy split is incorrect");

        uint256 treasuryBalance = IERC20(MAINNET_DYFI).balanceOf(treasury);
        assertEq(treasuryBalance, estimatedTreasurySplit, "treausry split is incorrect");

        uint256 swapAndLockBalance = IERC20(MAINNET_DYFI).balanceOf(address(swapAndLock));
        assertEq(swapAndLockBalance, estimatedVeYfiSplit, "veYfi split is incorrect");
    }

    function test_claimBoostRewards() public {
        _lockYfiForYSD(10e18);
        _setRewardSplit(testGauge, 0.3e18, 0.3e18, 0.4e18);
        _depositGaugeTokensToYSD(wrappedStrategy, 1e18);
        vm.warp(block.timestamp + 14 days);
        // Alice claims dYFI rewards without any boost
        IGauge(testGauge).getReward(alice);
        // YSD claims dYFI rewards Alice was penalized for
        yearnStakingDelegate.claimBoostRewards();
        assertEq(IERC20(MAINNET_DYFI).balanceOf(treasury), 36_395_783_852_751_212, "claimBoostRewards failed");
    }

    function test_claimExitRewards() public {
        // Reward pool needs to be checkpointed first independently
        IYfiRewardPool(MAINNET_YFI_REWARD_POOL).checkpoint_token();
        IYfiRewardPool(MAINNET_YFI_REWARD_POOL).checkpoint_total_supply();
        // Lock YFI for YSD
        _lockYfiForYSD(10e18);
        // Lock YFI for the user
        _lockYfiForUser(alice, 10e18, 8 * 52 weeks);
        // Another user early exits
        vm.prank(alice);
        IVotingYFI(MAINNET_VE_YFI).withdraw();
        // Advance to the next epoch
        vm.warp(block.timestamp + 2 weeks);
        // Claim exit rewards
        yearnStakingDelegate.claimExitRewards();
        // Assert the treasury balance is increased by the expected amount
        assertEq(IERC20(MAINNET_YFI).balanceOf(treasury), 66_005_769_070_969_234, "claimBoostRewards failed");
    }

    function test_setSnapshotDelegate() public {
        vm.startPrank(manager);
        yearnStakingDelegate.setSnapshotDelegate("veyfi.eth", manager);
        vm.stopPrank();

        assertEq(
            ISnapshotDelegateRegistry(MAINNET_SNAPSHOT_DELEGATE_REGISTRY).delegation(
                address(yearnStakingDelegate), "veyfi.eth"
            ),
            manager,
            "setSnapshotDelegate failed"
        );
    }

    function test_setSnapshotDelegate_revertWhen_ZeroAddress() public {
        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        yearnStakingDelegate.setSnapshotDelegate("veyfi.eth", address(0));
        vm.stopPrank();
    }

    function testFuzz_setTreasury(address newTreasury) public {
        vm.assume(newTreasury != address(0));
        vm.startPrank(admin);
        yearnStakingDelegate.setTreasury(newTreasury);
        vm.stopPrank();

        assertEq(yearnStakingDelegate.treasury(), newTreasury, "setTreasury failed");
    }

    function test_setTreasury_revertWhen_ZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        yearnStakingDelegate.setTreasury(address(0));
        vm.stopPrank();
    }

    function testFuzz_setRewardSplit(uint80 a, uint80 b) public {
        // Workaround for vm.assume max tries
        vm.assume(uint256(a) + b <= 1e18);
        uint80 c = 1e18 - a - b;
        vm.prank(admin);
        yearnStakingDelegate.setRewardSplit(testGauge, a, b, c);
        (uint80 treasurySplit, uint80 strategySplit, uint80 lockSplit) =
            yearnStakingDelegate.gaugeRewardSplit(testGauge);
        assertEq(treasurySplit, a, "setRewardSplit failed, treasury split is incorrect");
        assertEq(strategySplit, b, "setRewardSplit failed, strategy split is incorrect");
        assertEq(lockSplit, c, "setRewardSplit failed, lock split is incorrect");
    }

    function testFuzz_setRewardSplit_revertWhen_InvalidRewardSplit(uint80 a, uint80 b, uint80 c) public {
        vm.assume(uint256(a) + b + c != 1e18);
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRewardSplit.selector));
        yearnStakingDelegate.setRewardSplit(testGauge, a, b, c);
        vm.stopPrank();
    }
}

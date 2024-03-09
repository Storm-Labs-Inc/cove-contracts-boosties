// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "test/utils/YearnV3BaseTest.t.sol";
import { IStrategy } from "tokenized-strategy/interfaces/IStrategy.sol";
import { IVault } from "yearn-vaults-v3/interfaces/IVault.sol";
import { IYearnGaugeStrategy } from "src/interfaces/IYearnGaugeStrategy.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { StakingDelegateRewards } from "src/StakingDelegateRewards.sol";
import { SwapAndLock } from "src/SwapAndLock.sol";
import { AggregatorV3Interface } from "src/interfaces/deps/chainlink/AggregatorV3Interface.sol";
import { DYFIRedeemer } from "src/DYFIRedeemer.sol";
import { BaseRewardsGauge } from "src/rewards/BaseRewardsGauge.sol";
import { ERC20RewardsGauge } from "src/rewards/ERC20RewardsGauge.sol";
import { YSDRewardsGauge } from "src/rewards/YSDRewardsGauge.sol";
import { CoveYFI } from "src/CoveYFI.sol";
import { CoveToken } from "src/governance/CoveToken.sol";
import { RewardForwarder } from "src/rewards/RewardForwarder.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { CoveYearnGaugeFactory } from "src/registries/CoveYearnGaugeFactory.sol";

contract YearnGaugeStrategy_IntegrationTest is YearnV3BaseTest {
    using SafeERC20 for IERC20;

    IYearnGaugeStrategy public yearnGaugeStrategy;
    YearnStakingDelegate public yearnStakingDelegate;
    StakingDelegateRewards public stakingDelegateRewards;
    SwapAndLock public swapAndLock;
    DYFIRedeemer public dYfiRedeemer;
    IVault public vault;
    BaseRewardsGauge public erc20RewardsGauge;
    address public baseRewardForwarder;
    YSDRewardsGauge public ysdRewardsGauge;
    address public ysdRewardForwarder;
    CoveYFI public coveYfi;
    RewardForwarder public coveYfiRewardForwarder;
    ERC20RewardsGauge public coveYfiRewardsGauge;
    CoveToken public coveToken;
    CoveYearnGaugeFactory public coveYearnGaugeFactory;

    // Addresses
    address public alice;
    address public gauge;
    address public treasury;
    address public rewardDistributor;
    address public gaugeRewardReceiver;

    function setUp() public override {
        super.setUp();
        //// generic ////
        alice = createUser("alice");
        treasury = createUser("treasury");
        vault = IVault(MAINNET_WETH_YETH_POOL_VAULT);
        gauge = MAINNET_WETH_YETH_POOL_GAUGE;
        rewardDistributor = createUser("rewardDistributor");

        // Deploy Contracts

        // Deploy clone implementations
        address erc20RewardsGaugeImplementation = address(new ERC20RewardsGauge());
        address ysdRewardsGaugeImplementation = address(new YSDRewardsGauge());
        address rewardForwarderImplementation = address(new RewardForwarder());

        //// gauge rewards  ////
        {
            gaugeRewardReceiver = setUpGaugeRewardReceiverImplementation(admin);
            yearnStakingDelegate =
                YearnStakingDelegate(new YearnStakingDelegate(gaugeRewardReceiver, treasury, admin, admin, admin));
            vm.label(address(yearnStakingDelegate), "yearnStakingDelegate");
            vm.label(yearnStakingDelegate.gaugeRewardReceivers(gauge), "gaugeRewardReceiver");
            stakingDelegateRewards =
                StakingDelegateRewards(setUpStakingDelegateRewards(admin, MAINNET_DYFI, address(yearnStakingDelegate)));
            swapAndLock = SwapAndLock(setUpSwapAndLock(admin, address(yearnStakingDelegate)));
            dYfiRedeemer = new DYFIRedeemer(admin);
            vm.label(address(dYfiRedeemer), "dYfiRedeemer");
            coveYfi = new CoveYFI(address(yearnStakingDelegate), admin);
            vm.label(address(coveYfi), "coveYfi");
            coveYfiRewardsGauge = ERC20RewardsGauge(_cloneContract(erc20RewardsGaugeImplementation));
            coveYfiRewardsGauge.initialize(address(coveYfi));
            coveYfiRewardForwarder = RewardForwarder(_cloneContract(rewardForwarderImplementation));
            coveYfiRewardForwarder.initialize(address(coveYfiRewardsGauge));
            coveYfiRewardsGauge.addReward(MAINNET_YFI, address(coveYfiRewardForwarder));
            coveYfiRewardsGauge.addReward(MAINNET_DYFI, address(coveYfiRewardForwarder));
            vm.label(address(coveYfiRewardForwarder), "coveYfiRewardForwarder");
            // Admin transactions for setup
            vm.startPrank(admin);
            // sets gauge as reward and a 100% split to the strategy
            swapAndLock.setDYfiRedeemer(address(dYfiRedeemer));
            yearnStakingDelegate.addGaugeRewards(gauge, address(stakingDelegateRewards));
            yearnStakingDelegate.setSwapAndLock(address(swapAndLock));
            yearnStakingDelegate.setCoveYfiRewardForwarder(address(coveYfiRewardForwarder));
            vm.stopPrank();
        }

        //// wrapped strategy ////
        {
            yearnGaugeStrategy =
                setUpWrappedStrategy("Yearn Gauge Strategy", gauge, address(yearnStakingDelegate), MAINNET_CURVE_ROUTER);
            vm.startPrank(tpManagement);
            // setting CurveRouterSwapper params for harvest rewards swapping
            CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
            // [token_from, pool, token_to, pool, ...]
            curveSwapParams.route[0] = MAINNET_YFI;
            curveSwapParams.route[1] = MAINNET_ETH_YFI_POOL;
            curveSwapParams.route[2] = MAINNET_WETH;
            curveSwapParams.route[3] = MAINNET_WETH_YETH_POOL;
            curveSwapParams.route[4] = MAINNET_WETH_YETH_POOL; // expect the lp token back

            // i, j, swap_type, pool_type, n_coins
            // YFI -> WETH
            curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2];
            // ETH -> weth/yeth pool lp token, swap type is 4 to notify the swap router to call add_liquidity()
            curveSwapParams.swapParams[1] = [uint256(0), 0, 4, 1, 2];
            // set params for harvest rewards swapping
            yearnGaugeStrategy.setHarvestSwapParams(curveSwapParams);
            yearnGaugeStrategy.setMaxTotalAssets(type(uint256).max);
            vm.stopPrank();
        }

        // Reward Gauges
        {
            vm.startPrank(admin);
            // CoveToken
            coveToken = new CoveToken(admin);
            // RewardsGauges
            coveYearnGaugeFactory = new CoveYearnGaugeFactory(
                admin,
                address(yearnStakingDelegate),
                address(coveToken),
                address(rewardForwarderImplementation),
                address(erc20RewardsGaugeImplementation),
                address(ysdRewardsGaugeImplementation),
                admin,
                admin,
                admin
            );
            vm.label(address(coveYearnGaugeFactory), "coveYearnGaugeFactory");
            coveYearnGaugeFactory.deployCoveGauges(address(yearnGaugeStrategy));
            CoveYearnGaugeFactory.GaugeInfo memory gaugeInfo = coveYearnGaugeFactory.getGaugeInfo(address(gauge));
            erc20RewardsGauge = BaseRewardsGauge(gaugeInfo.autoCompoundingGauge);
            vm.label(address(erc20RewardsGauge), "erc20RewardsGauge");
            erc20RewardsGauge.grantRole(MANAGER_ROLE, tpManagement);
            baseRewardForwarder = erc20RewardsGauge.getRewardData(address(coveToken)).distributor;
            vm.label(baseRewardForwarder, "baseRewardForwarder");
            ysdRewardsGauge = YSDRewardsGauge(gaugeInfo.nonAutoCompoundingGauge);
            vm.label(address(ysdRewardsGauge), "ysdRewardsGauge");
            ysdRewardsGauge.grantRole(MANAGER_ROLE, tpManagement);
            ysdRewardForwarder = ysdRewardsGauge.getRewardData(address(coveToken)).distributor;
            vm.label(ysdRewardForwarder, "ysdRewardForwarder");
            // Setup Cove token to be given as a reward
            vm.label(address(coveToken), "coveToken");
            coveToken.grantRole(keccak256("MINTER_ROLE"), admin);
            coveToken.addAllowedSender(address(baseRewardForwarder));
            coveToken.addAllowedSender(address(erc20RewardsGauge));
            coveToken.addAllowedSender(address(ysdRewardForwarder));
            coveToken.addAllowedSender(address(ysdRewardsGauge));
            vm.stopPrank();
        }

        // Setup approvals for YFI spending
        vm.startPrank(alice);
        IERC20(MAINNET_YFI).approve(MAINNET_VE_YFI, type(uint256).max);
        IERC20(MAINNET_YFI).approve(address(yearnStakingDelegate), type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Mock the price feed for yfi/eth to be latest timestamp to prevent price too old error
    function _mockChainlinkPriceFeedTimestamp() internal {
        (uint80 roundID, int256 price, uint256 startedAt,, uint80 answeredInRound) =
            AggregatorV3Interface(MAINNET_YFI_ETH_PRICE_FEED).latestRoundData();
        vm.mockCall(
            MAINNET_YFI_ETH_PRICE_FEED,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundID, price, startedAt, block.timestamp, answeredInRound)
        );
    }

    /// @dev redeems all dYFI held by the strategy for YFI
    function _massRedeemStrategyDYfi() internal {
        address[] memory holders = new address[](1);
        holders[0] = address(yearnGaugeStrategy);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = IERC20(MAINNET_DYFI).balanceOf(address(yearnGaugeStrategy));
        dYfiRedeemer.massRedeem(holders, amounts);
    }

    // Need a special function to airdrop to the gauge since it relies on totalSupply for calculation
    function _airdropGaugeTokens(address user, uint256 amount) internal {
        airdrop(ERC20(address(vault)), user, amount);
        vm.startPrank(user);
        IERC20(vault).approve(address(gauge), amount);
        IGauge(gauge).deposit(amount, user);
        vm.stopPrank();
    }

    function _setGaugeRewardSplit(
        uint64 treasurySplit,
        uint64 coveYfiSplit,
        uint64 strategySplit,
        uint64 veYfiSplit
    )
        internal
    {
        vm.prank(admin);
        yearnStakingDelegate.setGaugeRewardSplit(gauge, treasurySplit, coveYfiSplit, strategySplit, veYfiSplit);
    }

    function _lockYfiForYSD(uint256 amount) internal {
        airdrop(ERC20(MAINNET_YFI), alice, amount);
        vm.prank(alice);
        yearnStakingDelegate.lockYfi(amount);
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        uint256 expectedShares = yearnGaugeStrategy.previewDeposit(amount);
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);
        // check for expected changes
        assertEq(yearnGaugeStrategy.balanceOf(alice), expectedShares, "Deposit was not successful");
        assertEq(
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            amount,
            "yearn staking delegate deposit failed"
        );
        assertEq(yearnGaugeStrategy.totalSupply(), expectedShares, "totalSupply did not update correctly");
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        uint256 expectedShares = yearnGaugeStrategy.previewDeposit(amount);
        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);

        vm.prank(alice);
        yearnGaugeStrategy.withdraw(expectedShares, alice, alice);
        assertEq(yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge), 0, "depositToGauge failed");
        assertEq(
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            0,
            "yearn staking delegate withdraw failed"
        );
        assertEq(yearnGaugeStrategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
        assertEq(yearnGaugeStrategy.balanceOf(alice), 0, "Withdraw was not successful");
    }

    function testFuzz_withdraw_withYSDGauge(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // deposit into rewards gauge happens
        airdrop(ERC20(gauge), alice, amount);
        vm.startPrank(alice);
        ERC20(gauge).approve(address(ysdRewardsGauge), amount);
        ysdRewardsGauge.deposit(amount, alice);
        vm.stopPrank();

        vm.startPrank(alice);
        ysdRewardsGauge.redeem(ysdRewardsGauge.balanceOf(alice), alice, alice);
        assertEq(yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge), 0, "depositToGauge failed");
        assertEq(
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            0,
            "yearn staking delegate withdraw failed"
        );
        assertEq(yearnGaugeStrategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
        assertEq(yearnGaugeStrategy.balanceOf(alice), 0, "Withdraw was not successful");
    }

    function testFuzz_harvest_passWhen_RewardRateZero(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < 1.7e4); // Small deposits do not accrue enough rewards to harvest

        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Gauge rewards are currently active, warp block forward to accrue rewards
        vm.warp(block.timestamp + 2 weeks);

        // yearn staking delegate harvests available rewards
        vm.prank(admin);
        assertEq(yearnStakingDelegate.harvest(gauge), 0);
    }

    function testFuzz_harvest_revertWhen_RewardRateTooLow(uint256 amount) public {
        vm.assume(amount >= 1.8e5);
        vm.assume(amount < 1e10); // Small deposits do not accrue enough rewards to harvest

        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Gauge rewards are currently active, warp block forward to accrue rewards
        vm.warp(block.timestamp + 2 weeks);

        // yearn staking delegate harvests available rewards
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.RewardRateTooLow.selector));
        yearnStakingDelegate.harvest(gauge);
    }

    function testFuzz_report_staking_rewards_profit(uint256 amount) public {
        vm.assume(amount > 3e10); // Minimum deposit size is required to farm sufficient dYFI emission
        vm.assume(amount < 100_000_000_000 * 1e18); // limit deposit size to 100k ETH/yETH LP token

        vm.prank(tpManagement);
        yearnGaugeStrategy.setDYfiRedeemer(address(dYfiRedeemer));

        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);
        vm.startPrank(alice);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        IERC20(yearnGaugeStrategy).approve(address(erc20RewardsGauge), shares);
        erc20RewardsGauge.deposit(shares, alice);
        vm.stopPrank();
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Gauge rewards are currently active, warp block forward to accrue rewards
        vm.warp(block.timestamp + 2 weeks);

        // yearn staking delegate harvests available rewards
        vm.prank(admin);
        yearnStakingDelegate.harvest(gauge);

        // Staking Delegate Rewards contract has accrued rewards and needs time to unlock them
        uint256 stakingDelegateperiodFinish = stakingDelegateRewards.periodFinish(gauge);
        vm.warp(stakingDelegateperiodFinish);

        // manager calls report on the wrapped strategy
        vm.prank(tpManagement);
        yearnGaugeStrategy.report();
        assertGt(IERC20(MAINNET_DYFI).balanceOf(address(yearnGaugeStrategy)), 0, "dYfi rewards should be received");

        // manager calls report on the wrapped strategy
        _mockChainlinkPriceFeedTimestamp();

        // Call massRedeem() to swap received DYfi for Yfi
        _massRedeemStrategyDYfi();

        vm.prank(tpManagement);
        (uint256 profit,) = yearnGaugeStrategy.report();
        assertGt(profit, 0, "profit should be greater than 0");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(yearnGaugeStrategy)).profitMaxUnlockTime());

        // manager calls report
        _mockChainlinkPriceFeedTimestamp();
        vm.prank(tpManagement);
        yearnGaugeStrategy.report();

        uint256 afterTotalAssets = yearnGaugeStrategy.totalAssets();
        assertEq(
            afterTotalAssets,
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            "all assets should be deployed"
        );
        assertEq(afterTotalAssets, beforeTotalAssets + profit, "report did not increase total assets");
        // User withdraws
        vm.startPrank(alice);
        erc20RewardsGauge.redeem(shares, alice, alice);
        yearnGaugeStrategy.redeem(shares, alice, alice);
        assertGt(IERC20(gauge).balanceOf(alice), amount, "profit not given to user on withdraw");
    }

    function testFuzz_report_staking_rewards_profit_erc20RewardsGauge_reward(uint256 amount, uint256 reward) public {
        vm.assume(amount > 3e10); // Minimum deposit size is required to farm sufficient dYFI emission
        vm.assume(amount < 100_000_000_000 * 1e18); // limit deposit size to 100k ETH/yETH LP token
        reward = bound(reward, Math.max(1e9, amount / 1e15), 1_000_000_000 ether);
        vm.assume(reward > _WEEK);
        // Mint coveToken to be given as reward
        vm.prank(admin);
        coveToken.transfer(address(baseRewardForwarder), reward);
        RewardForwarder(baseRewardForwarder).forwardRewardToken(address(coveToken));

        vm.prank(tpManagement);
        yearnGaugeStrategy.setDYfiRedeemer(address(dYfiRedeemer));

        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);
        vm.startPrank(alice);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        IERC20(yearnGaugeStrategy).approve(address(erc20RewardsGauge), shares);
        erc20RewardsGauge.deposit(shares, alice);
        vm.stopPrank();
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Gauge rewards and BaseRewardsGauge rewards are currently active, warp block forward to accrue rewards
        vm.warp(block.timestamp + 1 weeks);

        assertApproxEqRel(
            reward,
            erc20RewardsGauge.claimableReward(alice, address(coveToken)),
            0.005 * 1e18,
            "alice should have claimable rewards equal to the total amount of reward tokens deposited"
        );

        // yearn staking delegate harvests available rewards
        vm.prank(admin);
        yearnStakingDelegate.harvest(gauge);

        // Staking Delegate Rewards contract has accrued rewards and needs time to unlock them
        uint256 stakingDelegateperiodFinish = stakingDelegateRewards.periodFinish(gauge);
        vm.warp(stakingDelegateperiodFinish);

        // manager calls report on the wrapped strategy
        vm.prank(tpManagement);
        yearnGaugeStrategy.report();
        assertGt(IERC20(MAINNET_DYFI).balanceOf(address(yearnGaugeStrategy)), 0, "dYfi rewards should be received");

        // manager calls report on the wrapped strategy
        _mockChainlinkPriceFeedTimestamp();

        // Call massRedeem() to swap received DYfi for Yfi
        _massRedeemStrategyDYfi();

        vm.prank(tpManagement);
        (uint256 profit,) = yearnGaugeStrategy.report();
        assertGt(profit, 0, "profit should be greater than 0");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(yearnGaugeStrategy)).profitMaxUnlockTime());

        // manager calls report
        _mockChainlinkPriceFeedTimestamp();
        vm.prank(tpManagement);
        yearnGaugeStrategy.report();

        uint256 afterTotalAssets = yearnGaugeStrategy.totalAssets();
        assertEq(
            afterTotalAssets,
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            "all assets should be deployed"
        );
        assertEq(afterTotalAssets, beforeTotalAssets + profit, "report did not increase total assets");
        // User withdraws
        vm.startPrank(alice);
        erc20RewardsGauge.redeem(shares, alice, alice);
        yearnGaugeStrategy.redeem(shares, alice, alice);
        assertGt(IERC20(gauge).balanceOf(alice), amount, "profit not given to user on withdraw");
        uint256 coveBalanceBefore = IERC20(address(coveToken)).balanceOf(alice);
        erc20RewardsGauge.claimRewards(alice, alice);
        assertApproxEqRel(
            coveBalanceBefore + reward,
            IERC20(address(coveToken)).balanceOf(alice),
            0.005 * 1e18,
            "reward not given to user on claim"
        );
    }

    function testFuzz_report_staking_rewards_profit_ysdRewardsGauge_reward(uint256 amount, uint256 reward) public {
        vm.assume(amount > 1.1e13); // Minimum deposit size is required to farm sufficient dYFI emission
        vm.assume(amount < 100_000_000_000 * 1e18); // limit deposit size to 100k ETH/yETH LP token
        reward = bound(reward, Math.max(1e9, amount / 1e15), 1_000_000_000 ether);
        // Mint coveToken to be given as reward
        vm.prank(admin);
        coveToken.transfer(address(ysdRewardForwarder), reward);
        RewardForwarder(ysdRewardForwarder).forwardRewardToken(address(coveToken));

        airdrop(ERC20(gauge), alice, amount);
        vm.startPrank(alice);
        IGauge(gauge).approve(address(ysdRewardsGauge), amount);
        ysdRewardsGauge.deposit(amount, alice);
        vm.stopPrank();

        // Gauge rewards and BaseRewardsGauge rewards are currently active, warp block forward to accrue rewards
        vm.warp(block.timestamp + 2 weeks);

        assertApproxEqRel(
            reward,
            ysdRewardsGauge.claimableReward(alice, address(coveToken)),
            0.005 * 1e18,
            "alice should have claimable rewards equal to the total amount of reward tokens deposited"
        );

        uint256 coveBalanceBefore = IERC20(address(coveToken)).balanceOf(alice);
        vm.prank(alice);
        ysdRewardsGauge.claimRewards(alice, alice);
        assertApproxEqRel(
            coveBalanceBefore + reward,
            IERC20(address(coveToken)).balanceOf(alice),
            0.005 * 1e18,
            "reward gauge cove reward not given to user on claim"
        );

        // yearn staking delegate harvests available rewards
        vm.prank(admin);
        uint256 totalRewardAmount = yearnStakingDelegate.harvest(gauge);

        // Staking Delegate Rewards contract has accrued rewards and needs time to unlock them
        uint256 stakingDelegateperiodFinish = stakingDelegateRewards.periodFinish(gauge);
        vm.warp(stakingDelegateperiodFinish);

        vm.startPrank(alice);
        // Get rewards gained by YearnStakingDelegate harvest and forwarded to the rewards forwarder
        stakingDelegateRewards.getReward(address(ysdRewardsGauge), gauge);
        // Forward the earned dYFI to the rewardsGauge
        RewardForwarder(ysdRewardForwarder).forwardRewardToken(address(MAINNET_DYFI));
        // Warp forward 1 week for the rewards to be claimable
        uint256 periodFinish = ysdRewardsGauge.getRewardData(MAINNET_DYFI).periodFinish;
        vm.warp(periodFinish);
        uint256 dYFIBalanceBefore = IERC20(MAINNET_DYFI).balanceOf(alice);
        ysdRewardsGauge.claimRewards(alice, alice);
        assertApproxEqRel(
            dYFIBalanceBefore + totalRewardAmount,
            IERC20(address(MAINNET_DYFI)).balanceOf(alice),
            0.005 * 1e18,
            "reward gauge dYFI reward not given to user on claim"
        );
        uint256 shares = ysdRewardsGauge.balanceOf(alice);
        ysdRewardsGauge.redeem(shares, alice, alice);
        assertEq(IERC20(gauge).balanceOf(alice), amount, "shares not given back to user on withdraw");
    }

    function test_report_staking_rewards_profit_reward_split() public {
        // non-fuzzing for amount to ensure reward calculation
        uint256 amount = 10e18;
        // Set the reward split for treasury and swap and lock
        _setGaugeRewardSplit(0.1e18, 0.2e18, 0.3e18, 0.4e18);

        vm.prank(tpManagement);
        yearnGaugeStrategy.setDYfiRedeemer(address(dYfiRedeemer));

        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Gauge rewards are currently active, warp block forward to accrue rewards
        vm.warp(block.timestamp + 2 weeks);

        _mockChainlinkPriceFeedTimestamp();
        // yearn staking delegate harvests available rewards
        vm.prank(admin);
        uint256 totalRewardAmount = yearnStakingDelegate.harvest(gauge);

        // Calculate split amounts strategy split amount
        {
            uint256 estimatedTreasurySplit = totalRewardAmount * 0.1e18 / 1e18;
            uint256 estimatedForwarderSplit = totalRewardAmount * 0.2e18 / 1e18;
            uint256 estimatedVeYfiSplit = totalRewardAmount * 0.4e18 / 1e18;
            uint256 estimatedUserSplit =
                totalRewardAmount - estimatedTreasurySplit - estimatedForwarderSplit - estimatedVeYfiSplit;

            uint256 treasuryBalance = IERC20(MAINNET_DYFI).balanceOf(treasury);
            assertEq(treasuryBalance, estimatedTreasurySplit, "treausry split is incorrect");

            uint256 forwarderBalance = IERC20(MAINNET_DYFI).balanceOf(address(coveYfiRewardForwarder));
            assertEq(forwarderBalance, estimatedForwarderSplit, "forwarder split is incorrect");

            uint256 strategyDYfiBalance = IERC20(MAINNET_DYFI).balanceOf(address(stakingDelegateRewards));
            assertEq(strategyDYfiBalance, estimatedUserSplit, "strategy split is incorrect");

            uint256 swapAndLockBalance = IERC20(MAINNET_DYFI).balanceOf(address(swapAndLock));
            assertEq(swapAndLockBalance, estimatedVeYfiSplit, "veYfi split is incorrect");
        }

        // Staking Delegate Rewards contract has accrued rewards and needs time to unlock them
        uint256 stakingDelegateperiodFinish = stakingDelegateRewards.periodFinish(gauge);
        vm.warp(stakingDelegateperiodFinish);

        // manager calls report on the wrapped strategy
        vm.prank(tpManagement);
        yearnGaugeStrategy.report();
        assertGt(IERC20(MAINNET_DYFI).balanceOf(address(yearnGaugeStrategy)), 0, "dYfi rewards should be received");

        // manager calls report on the wrapped strategy
        _mockChainlinkPriceFeedTimestamp();

        // Call massRedeem() to swap received DYfi for Yfi
        _massRedeemStrategyDYfi();

        vm.prank(tpManagement);
        (uint256 profit,) = yearnGaugeStrategy.report();
        assertGt(profit, 0, "profit should be greater than 0");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(yearnGaugeStrategy)).profitMaxUnlockTime());

        // manager calls report
        _mockChainlinkPriceFeedTimestamp();
        vm.prank(tpManagement);
        yearnGaugeStrategy.report();

        uint256 afterTotalAssets = yearnGaugeStrategy.totalAssets();
        assertEq(
            afterTotalAssets,
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            "all assets should be deployed"
        );
        assertEq(afterTotalAssets, beforeTotalAssets + profit, "report did not increase total assets");

        // User withdraws
        vm.prank(alice);
        yearnGaugeStrategy.redeem(shares, alice, alice);
        assertGt(IERC20(gauge).balanceOf(alice), 10e18, "profit not given to user on withdraw");
    }

    function testFuzz_withdraw_duringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        uint256 expectedShares = yearnGaugeStrategy.previewDeposit(amount);
        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);

        // shutdown strategy
        vm.prank(tpManagement);
        yearnGaugeStrategy.shutdownStrategy();

        vm.prank(alice);
        yearnGaugeStrategy.withdraw(expectedShares, alice, alice);
        assertEq(yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge), 0, "depositToGauge failed");
        assertEq(
            yearnStakingDelegate.balanceOf(address(yearnGaugeStrategy), gauge),
            0,
            "yearn staking delegate withdraw failed"
        );
        assertEq(yearnGaugeStrategy.totalSupply(), 0, "totalSupply did not update correctly");
        assertEq(IERC20(gauge).balanceOf(alice), amount, "asset was not returned on withdraw");
        assertEq(yearnGaugeStrategy.balanceOf(alice), 0, "Withdraw was not successful");
    }

    function testFuzz_deposit_duringShutdown(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < type(uint128).max);

        // shutdown strategy
        vm.prank(tpManagement);
        yearnGaugeStrategy.shutdownStrategy();
        // deposit into strategy happens
        _airdropGaugeTokens(alice, amount);
        vm.startPrank(alice);
        IERC20(yearnGaugeStrategy.asset()).safeApprove(address(yearnGaugeStrategy), amount);
        // TokenizedStrategy.maxDeposit() returns 0 on shutdown
        vm.expectRevert("ERC4626: deposit more than max");
        yearnGaugeStrategy.deposit(amount, alice);
    }

    function testFuzz_withdraw_duringShutdownReport(uint256 amount) public {
        vm.assume(amount > 1e16); // Minimum deposit size is required to farm dYFI emission
        vm.assume(amount < 100_000_000_000 * 1e18); // limit deposit size to 100k ETH/yETH LP token

        vm.prank(tpManagement);
        yearnGaugeStrategy.setDYfiRedeemer(address(dYfiRedeemer));

        // deposit into strategy happens
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, amount, gauge);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, amount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, amount, "preview redeem should return deposit amount");

        // Gauge rewards are currently active, warp block forward to accrue rewards
        vm.warp(block.timestamp + 2 weeks);

        // yearn staking delegate harvests available rewards
        vm.prank(admin);
        yearnStakingDelegate.harvest(gauge);

        // Staking Delegate Rewards contract has accrued rewards and needs time to unlock them
        uint256 stakingDelegateperiodFinish = stakingDelegateRewards.periodFinish(gauge);
        vm.warp(stakingDelegateperiodFinish);

        // shutdown strategy
        vm.prank(tpManagement);
        yearnGaugeStrategy.shutdownStrategy();

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(yearnGaugeStrategy)).profitMaxUnlockTime());

        // manager calls report on the wrapped strategy
        vm.prank(tpManagement);
        yearnGaugeStrategy.report();
        assertGt(IERC20(MAINNET_DYFI).balanceOf(address(yearnGaugeStrategy)), 0, "dYfi rewards should be received");

        // manager calls report on the wrapped strategy
        _mockChainlinkPriceFeedTimestamp();

        // Call massRedeem() to swap received DYfi for Yfi
        _massRedeemStrategyDYfi();

        vm.prank(tpManagement);
        (uint256 profit,) = yearnGaugeStrategy.report();
        assertGt(profit, 0, "profit should be greater than 0");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(yearnGaugeStrategy)).profitMaxUnlockTime());

        // manager calls report
        vm.prank(tpManagement);
        yearnGaugeStrategy.report();

        uint256 afterTotalAssets = yearnGaugeStrategy.totalAssets();
        assertEq(afterTotalAssets, beforeTotalAssets + profit, "report did not increase total assets");

        // User withdraws
        vm.prank(alice);
        yearnGaugeStrategy.redeem(shares, alice, alice);
        assertGt(IERC20(gauge).balanceOf(alice), amount, "profit not given to user on withdraw");
    }

    function test_report_boosted_profit() public {
        _lockYfiForYSD(1e18); // locks veYfi for alice
        // deposit into strategy happens
        uint256 userDepositAmount = 1e18;
        mintAndDepositIntoStrategy(yearnGaugeStrategy, alice, userDepositAmount, gauge);
        uint256 shares = yearnGaugeStrategy.balanceOf(alice);
        uint256 beforeTotalAssets = yearnGaugeStrategy.totalAssets();
        uint256 beforePreviewRedeem = yearnGaugeStrategy.previewRedeem(shares);
        assertEq(beforeTotalAssets, userDepositAmount, "total assets should be equal to deposit amount");
        assertEq(beforePreviewRedeem, userDepositAmount, "preview redeem should return deposit amount");

        address bob = createUser("bob");
        _airdropGaugeTokens(bob, userDepositAmount);

        // Gauge rewards are currently active, warp block forward to accrue rewards
        vm.warp(block.timestamp + 14 days);

        // yearn staking delegate harvests available rewards
        vm.prank(admin);
        uint256 totalRewardAmount = yearnStakingDelegate.harvest(gauge);
        assertGt(totalRewardAmount, 0, "harvest failed");
        vm.prank(bob);
        IGauge(gauge).getReward(bob);
        uint256 nonBoostedRewardAmount = IERC20(MAINNET_DYFI).balanceOf(bob);
        assertGt(nonBoostedRewardAmount, 0, "harvest failed");
        assertGt(totalRewardAmount, nonBoostedRewardAmount, "veYfi boost failed");
        // Check that the vault has received the rewards
        assertEq(
            totalRewardAmount,
            IERC20(MAINNET_DYFI).balanceOf(address(stakingDelegateRewards)),
            "harvest did not return correct value"
        );
    }

    function testFuzz_report_staking_rewards_profit_mulitple_users(uint256 amount0, uint256 amount1) public {
        IYearnGaugeStrategy gaugeStrategy = yearnGaugeStrategy;
        // first deposit will always be a large amount
        uint256 initialDeposit = 10e18;
        vm.assume(amount0 < type(uint128).max && amount1 < type(uint128).max);
        address bob = createUser("bob");
        address charlie = createUser("charlie");

        vm.prank(tpManagement);
        yearnGaugeStrategy.setDYfiRedeemer(address(dYfiRedeemer));

        // deposit into strategy happens
        mintAndDepositIntoStrategy(gaugeStrategy, alice, initialDeposit, gauge);
        uint256 beforeTotalAssets = gaugeStrategy.totalAssets();
        uint256 beforeDeployedAssets = yearnStakingDelegate.balanceOf(address(gaugeStrategy), gauge);
        // Gauge rewards are currently active, warp block forward to accrue rewards
        vm.warp(block.timestamp + 2 weeks);

        // yearn staking delegate harvests available rewards
        vm.prank(admin);
        yearnStakingDelegate.harvest(gauge);

        // Staking Delegate Rewards contract has accrued rewards and needs time to unlock them
        uint256 stakingDelegateperiodFinish = stakingDelegateRewards.periodFinish(gauge);
        vm.warp(stakingDelegateperiodFinish);

        // manager calls report on the wrapped strategy
        vm.prank(tpManagement);
        yearnGaugeStrategy.report();
        assertGt(IERC20(MAINNET_DYFI).balanceOf(address(yearnGaugeStrategy)), 0, "dYfi rewards should be received");

        // manager calls report on the wrapped strategy
        _mockChainlinkPriceFeedTimestamp();

        // Call massRedeem() to swap received DYfi for Yfi
        _massRedeemStrategyDYfi();

        vm.prank(tpManagement);
        (uint256 profit,) = gaugeStrategy.report();
        assertGt(profit, 0, "profit should be greater than 0");

        // warp blocks forward to profit locking is finished
        vm.warp(block.timestamp + IStrategy(address(gaugeStrategy)).profitMaxUnlockTime());

        // calculate the minimum amount that can be deposited to result in at least 1 share
        vm.assume(amount0 * gaugeStrategy.totalSupply() > gaugeStrategy.totalAssets());

        // Test multiple users interaction
        mintAndDepositIntoStrategy(gaugeStrategy, bob, amount0, gauge);
        uint256 afterBobDeployedAssets = yearnStakingDelegate.balanceOf(address(gaugeStrategy), gauge);
        assertEq(
            afterBobDeployedAssets, beforeDeployedAssets + amount0 + profit, "all of bob's deposit should be deployed"
        );

        // manager calls report
        _mockChainlinkPriceFeedTimestamp();
        vm.prank(tpManagement);
        gaugeStrategy.report();

        // Test multiple users interaction, deposit is require to result in at least one shar
        vm.assume(amount1 * gaugeStrategy.totalSupply() > gaugeStrategy.totalAssets());
        mintAndDepositIntoStrategy(gaugeStrategy, charlie, amount1, gauge);
        uint256 afterCharlieDeployedAssets = yearnStakingDelegate.balanceOf(address(gaugeStrategy), gauge);
        assertEq(
            afterCharlieDeployedAssets, afterBobDeployedAssets + amount1, "all of Charlie's deposit should be deployed"
        );

        uint256 afterTotalAssets = gaugeStrategy.totalAssets();
        // Profit should only be compared to assets deposited before profit was reported+unlocked
        assertEq(
            afterTotalAssets - amount0 - amount1, beforeTotalAssets + profit, "report did not increase total assets"
        );
        // All assets should be deployed if there has been a report() since the deposit
        assertEq(
            afterTotalAssets,
            yearnStakingDelegate.balanceOf(address(gaugeStrategy), gauge),
            "all assets should be deployed"
        );
    }

    // receive function for testing flashloans
    receive() external payable { }
}

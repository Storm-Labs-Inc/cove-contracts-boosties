// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { CurveRouterSwapper, ICurveRouter } from "src/swappers/CurveRouterSwapper.sol";
import { IWrappedYearnV3AssetSwapStrategy } from "src/interfaces/IWrappedYearnV3AssetSwapStrategy.sol";
import { StrategyAssetSwap } from "src/strategies/StrategyAssetSwap.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockChainLinkOracle } from "./mocks/MockChainLinkOracle.sol";

contract WrappedStrategyAssetSwapperStaticPricesTest is YearnV3BaseTest {
    // Oracle Addresses
    address public constant CHAINLINK_DAI_USD_MAINNET = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public constant CHAINLINK_USDC_USD_MAINNET = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 1000e18;

    // Contracts
    YearnStakingDelegate public yearnStakingDelegate;
    IWrappedYearnV3AssetSwapStrategy public wrappedYearnV3AssetSwapStrategy;
    IVault public deployedVault;
    MockChainLinkOracle public mockDAIOracle;

    // Addresses
    address public alice;
    address public treasury;
    address public manager;
    address public deployedGauge;

    // Curve router parameters
    CurveRouterSwapper.CurveSwapParams internal _assetDeployParams;
    CurveRouterSwapper.CurveSwapParams internal _assetFreeParams;

    function setUp() public override {
        super.setUp();

        // Create users
        alice = createUser("alice");
        treasury = createUser("treasury");
        manager = createUser("manager");

        // Deploy mock vault to be used as underlying yield source for wrapped strategy
        {
            deployedVault = IVault(deployVaultV3("DAI Vault", MAINNET_DAI, new address[](0)));
            deployedGauge = deployGaugeViaFactory(address(deployedVault), admin, "DAI Test Vault Gauge");
        }

        // Deploy YearnStakingDelegate
        {
            yearnStakingDelegate = YearnStakingDelegate(setUpYearnStakingDelegate(treasury, admin, manager));
            // Give alice some YFI
            airdrop(ERC20(MAINNET_YFI), alice, ALICE_YFI);
            // Give admin some dYFI
            airdrop(ERC20(MAINNET_DYFI), admin, DYFI_REWARD_AMOUNT);
            // Start new rewards
            vm.startPrank(admin);
            IERC20(MAINNET_DYFI).approve(deployedGauge, DYFI_REWARD_AMOUNT);
            IGauge(deployedGauge).queueNewRewards(DYFI_REWARD_AMOUNT);
            require(IERC20(MAINNET_DYFI).balanceOf(deployedGauge) == DYFI_REWARD_AMOUNT, "queueNewRewards failed");
            yearnStakingDelegate.setAssociatedGauge(address(deployedVault), deployedGauge);
            vm.stopPrank();
        }

        // Deploy wrapped strategy with different asset than the underlying vault
        wrappedYearnV3AssetSwapStrategy = setUpWrappedStrategyAssetSwap(
            "Wrapped YearnV3 USDC -> DAI Strategy (Asset Swap with Oracle)",
            MAINNET_USDC,
            address(deployedVault),
            address(yearnStakingDelegate),
            MAINNET_DYFI,
            MAINNET_CURVE_ROUTER,
            // specifies that we want to use static prices
            false
        );
        vm.startPrank(users["tpManagement"]);
        // set the oracle for USDC and DAI
        // strategy.setOracle(MAINNET_DAI, CHAINLINK_DAI_USD_MAINNET);
        // strategy.setOracle(MAINNET_USDC, CHAINLINK_USDC_USD_MAINNET);
        {
            // set the swap parameters
            // [token_from, pool, token_to, pool, ...]
            _assetDeployParams.route[0] = MAINNET_USDC;
            _assetDeployParams.route[1] = MAINNET_CRV3POOL;
            _assetDeployParams.route[2] = MAINNET_DAI;
            _assetDeployParams.swapParams[0] = [uint256(1), 0, 1, 1, 2];

            // [token_from, pool, token_to, pool, ...]
            _assetFreeParams.route[0] = MAINNET_DAI;
            _assetFreeParams.route[1] = MAINNET_CRV3POOL;
            _assetFreeParams.route[2] = MAINNET_USDC;
            _assetFreeParams.swapParams[0] = [uint256(0), 1, 1, 1, 2];

            // set the swap tolerance
            StrategyAssetSwap.SwapTolerance memory swapTolerance =
                StrategyAssetSwap.SwapTolerance({ slippageTolerance: 99_500, timeTolerance: 1 days });

            wrappedYearnV3AssetSwapStrategy.setSwapParameters(_assetDeployParams, _assetFreeParams, swapTolerance);
        }
        vm.stopPrank();
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount < 1e13);
        airdrop(ERC20(MAINNET_USDC), alice, amount);
        vm.prank(alice);
        // deposit into strategy happens
        uint256 minAmountFromCurve = ICurveRouter(MAINNET_CURVE_ROUTER).get_dy(
            _assetDeployParams.route, _assetDeployParams.swapParams, amount, _assetDeployParams.pools
        );
        depositIntoStrategy(wrappedYearnV3AssetSwapStrategy, alice, amount);
        // check for expected changes
        assertGe(deployedVault.balanceOf(deployedGauge), minAmountFromCurve, "depositToGauge failed");
        uint128 userBalance = IYearnStakingDelegate(address(yearnStakingDelegate)).userInfo(
            address(wrappedYearnV3AssetSwapStrategy), address(deployedVault)
        ).balance;
        assertGe(userBalance, minAmountFromCurve, "userInfo in ysd not updated correctly");
        assertGe(deployedVault.totalSupply(), minAmountFromCurve, "vault total_supply did not update correctly");
        assertGe(wrappedYearnV3AssetSwapStrategy.balanceOf(alice), amount, "Deposit was not successful");
    }

    function testFuzz_deposit_revertWhen_slippageIsHigh(uint256 amount) public {
        vm.assume(amount > 1e14);
        vm.assume(amount < 1e40);
        airdrop(ERC20(MAINNET_USDC), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(wrappedYearnV3AssetSwapStrategy), amount);
        vm.expectRevert("Slippage");
        wrappedYearnV3AssetSwapStrategy.deposit(amount, alice);
    }

    function testFuzz_deposit_revertWhen_depositTooBig(uint256 amount) public {
        vm.assume(amount > 1e40);
        airdrop(ERC20(MAINNET_USDC), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(wrappedYearnV3AssetSwapStrategy), amount);
        vm.expectRevert();
        wrappedYearnV3AssetSwapStrategy.deposit(amount, alice);
    }

    function test_redeem(uint256 amount) public {
        vm.assume(amount > 1e8);
        // limit fuzzing to 10 million (pool slippage is too great otherwise)
        vm.assume(amount < 1e13);

        airdrop(ERC20(MAINNET_USDC), alice, amount);

        // deposit into strategy happens
        uint256 shares = depositIntoStrategy(wrappedYearnV3AssetSwapStrategy, alice, amount);

        // withdraw from strategy happens
        // allow for 4 BPS of loss due to non-changing value of yearn vault but loss due to swap
        vm.startPrank(alice);
        wrappedYearnV3AssetSwapStrategy.redeem(shares, alice, alice, 4);
        // check for expected changes
        assertEq(deployedVault.balanceOf(deployedGauge), 0, "withdrawFromGauge failed");
        uint128 userBalance = IYearnStakingDelegate(address(yearnStakingDelegate)).userInfo(
            address(wrappedYearnV3AssetSwapStrategy), address(deployedVault)
        ).balance;
        assertEq(userBalance, 0, "userInfo in ysd not updated correctly");
        assertEq(
            deployedVault.balanceOf(wrappedYearnV3AssetSwapStrategy.yearnStakingDelegate()),
            0,
            "vault shares not taken from delegate"
        );
        assertEq(deployedVault.totalSupply(), 0, "vault total_supply did not update correctly");
        assertEq(wrappedYearnV3AssetSwapStrategy.balanceOf(alice), 0, "Withdraw was not successful");
        assertApproxEqRel(
            ERC20(MAINNET_USDC).balanceOf(alice), amount, 0.004e18, "user balance should be deposit amount after redeem"
        );
    }

    function test_withdraw(uint256 amount) public {
        vm.assume(amount > 1e8);
        // limit fuzzing to 10 million (pool slippage is too great otherwise)
        vm.assume(amount < 1e13);

        airdrop(ERC20(MAINNET_USDC), alice, amount);
        ERC20(MAINNET_USDC).approve(address(wrappedYearnV3AssetSwapStrategy), amount);

        // deposit into strategy happens
        uint256 shares = depositIntoStrategy(wrappedYearnV3AssetSwapStrategy, alice, amount);
        // convert shares to expected amount
        uint256 withdrawAmount = wrappedYearnV3AssetSwapStrategy.convertToAssets(shares);

        // withdraw from strategy happens
        // allow for 4 BPS of loss due to non-changing value of yearn vault but loss due to swap
        vm.startPrank(alice);
        wrappedYearnV3AssetSwapStrategy.withdraw(withdrawAmount, alice, alice, 4);
        // check for expected changes
        assertEq(deployedVault.balanceOf(deployedGauge), 0, "withdrawFromGauge failed");
        uint128 userBalance = IYearnStakingDelegate(address(yearnStakingDelegate)).userInfo(
            address(wrappedYearnV3AssetSwapStrategy), address(deployedVault)
        ).balance;
        assertEq(userBalance, 0, "userInfo in ysd not updated correctly");
        assertEq(
            deployedVault.balanceOf(wrappedYearnV3AssetSwapStrategy.yearnStakingDelegate()),
            0,
            "vault shares not taken from delegate"
        );
        assertEq(deployedVault.totalSupply(), 0, "vault total_supply did not update correctly");
        assertEq(wrappedYearnV3AssetSwapStrategy.balanceOf(alice), 0, "Withdraw was not successful");
        assertApproxEqRel(
            ERC20(MAINNET_USDC).balanceOf(alice),
            amount,
            0.004e18,
            "user balance should be deposit amount after withdraw"
        );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "src/interfaces/deps/yearn/tokenized-strategy/IStrategy.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { CurveRouterSwapper, ICurveRouter } from "src/swappers/CurveRouterSwapper.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { WrappedYearnV3StrategyAssetSwap } from "src/strategies/WrappedYearnV3StrategyAssetSwap.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ICurveBasePool } from "../src/interfaces/deps/curve/ICurveBasePool.sol";
import { MockChainLinkOracle } from "./mocks/MockChainLinkOracle.sol";
import { Errors } from "src/libraries/Errors.sol";

contract WrappedStrategyAssetSwapperStaticPricesTest is YearnV3BaseTest {
    // Oracle Addresses
    address public constant CHAINLINK_DAI_USD_MAINNET = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public constant CHAINLINK_USDC_USD_MAINNET = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 1000e18;

    // Contract Addresses
    YearnStakingDelegate public yearnStakingDelegate;
    WrappedYearnV3StrategyAssetSwap public strategy;
    IVault public deployedVault;
    MockChainLinkOracle public mockDAIOracle;
    address public testGauge;

    // User Addresses
    address public alice;
    address public treasury;
    address public manager;

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
            testGauge = deployGaugeViaFactory(address(deployedVault), admin, "DAI Test Vault Gauge");
        }

        // Deploy YearnStakingDelegate
        {
            yearnStakingDelegate = YearnStakingDelegate(setUpYearnStakingDelegate(treasury, admin, manager));
            // Give alice some YFI
            airdrop(ERC20(MAINNET_YFI), alice, ALICE_YFI);
            // Give admin some dYFI
            airdrop(ERC20(dYFI), admin, DYFI_REWARD_AMOUNT);
            // Start new rewards
            vm.startPrank(admin);
            IERC20(dYFI).approve(testGauge, DYFI_REWARD_AMOUNT);
            IGauge(testGauge).queueNewRewards(DYFI_REWARD_AMOUNT);
            require(IERC20(dYFI).balanceOf(testGauge) == DYFI_REWARD_AMOUNT, "queueNewRewards failed");
            yearnStakingDelegate.setAssociatedGauge(address(deployedVault), testGauge);
            vm.stopPrank();
        }

        // Deploy wrapped strategy with different asset than the underlying vault
        strategy = WrappedYearnV3StrategyAssetSwap(
            address(
                setUpWrappedStrategyAssetSwap(
                    "Wrapped YearnV3 USDC -> DAI Strategy (Asset Swap with Oracle)",
                    MAINNET_USDC,
                    address(deployedVault),
                    address(yearnStakingDelegate),
                    dYFI,
                    MAINNET_CURVE_ROUTER,
                    // specifies that we want to use static prices
                    false
                )
            )
        );
        vm.startPrank(users["tpManagement"]);
        // set the oracle for USDC and DAI
        strategy.setOracle(MAINNET_DAI, CHAINLINK_DAI_USD_MAINNET);
        strategy.setOracle(MAINNET_USDC, CHAINLINK_USDC_USD_MAINNET);
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

            strategy.setSwapParameters(_assetDeployParams, _assetFreeParams, 99_500, 1 days);
        }
        vm.stopPrank();
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 1e13);
        airdrop(ERC20(MAINNET_USDC), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);
        // deposit into strategy happens
        uint256 minAmountFromCurve = ICurveRouter(MAINNET_CURVE_ROUTER).get_dy(
            _assetDeployParams.route, _assetDeployParams.swapParams, amount, _assetDeployParams.pools
        );
        IWrappedYearnV3Strategy(address(strategy)).deposit(amount, alice);
        // check for expected changes

        vm.stopPrank();
        assertEq(ERC20(MAINNET_USDC).balanceOf(alice), 0, "alice still has USDC");
        assertApproxEqRel(
            ERC20(MAINNET_DAI).balanceOf(address(deployedVault)),
            minAmountFromCurve,
            0.001e18,
            "vault did not receive correct amount of DAI"
        );
        assertApproxEqRel(
            ERC20(testGauge).balanceOf(address(yearnStakingDelegate)),
            minAmountFromCurve,
            0.001e18,
            "vault shares not given to delegate"
        );
        uint256 creditedBalance = uint256(
            IYearnStakingDelegate(address(yearnStakingDelegate)).userInfo(address(strategy), address(deployedVault))
                .balance
        );
        assertApproxEqRel(
            creditedBalance, minAmountFromCurve, 0.001e18, "vault shares in delegate not credited to strategy"
        );
        assertEq(deployedVault.totalSupply(), creditedBalance, "vault total_supply did not update correctly");
        assertEq(IWrappedYearnV3Strategy(address(strategy)).balanceOf(alice), amount, "Deposit was not successful");
    }

    function testFuzz_deposit_revertWhen_slippageIsHigh(uint256 amount) public {
        vm.assume(amount > 1e14);
        vm.assume(amount < 1e40);
        airdrop(ERC20(MAINNET_USDC), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);
        vm.expectRevert("Slippage");
        IWrappedYearnV3Strategy(address(strategy)).deposit(amount, alice);
    }

    function testFuzz_deposit_revertWhen_depositTooBig(uint256 amount) public {
        vm.assume(amount > 1e40);
        airdrop(ERC20(MAINNET_USDC), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);
        vm.expectRevert();
        IWrappedYearnV3Strategy(address(strategy)).deposit(amount, alice);
    }

    function test_redeem(uint256 amount) public {
        vm.assume(amount > 1e8);
        // limit fuzzing to 10 million (pool slippage is too great otherwise)
        vm.assume(amount < 1e13);

        IWrappedYearnV3Strategy _strategy = IWrappedYearnV3Strategy(address(strategy));
        airdrop(ERC20(MAINNET_USDC), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);

        // deposit into strategy happens
        uint256 shares = _strategy.deposit(amount, alice);

        // withdraw from strategy happens
        // allow for 4 BPS of loss due to non-changing value of yearn vault but loss due to swap
        _strategy.redeem(shares, alice, alice, 4);
        // check for expected changes
        assertEq(deployedVault.balanceOf(testGauge), 0, "withdrawFromGauge failed");
        uint128 userBalance = IYearnStakingDelegate(address(yearnStakingDelegate)).userInfo(
            address(_strategy), address(deployedVault)
        ).balance;
        assertEq(userBalance, 0, "userInfo in ysd not updated correctly");
        assertEq(deployedVault.balanceOf(strategy.yearnStakingDelegate()), 0, "vault shares not taken from delegate");
        assertEq(deployedVault.totalSupply(), 0, "vault total_supply did not update correctly");
        assertEq(_strategy.balanceOf(alice), 0, "Withdraw was not successful");
        assertApproxEqRel(
            ERC20(MAINNET_USDC).balanceOf(alice), amount, 0.004e18, "user balance should be deposit amount after redeem"
        );
    }

    function test_withdraw(uint256 amount) public {
        vm.assume(amount > 1e8);
        // limit fuzzing to 10 million (pool slippage is too great otherwise)
        vm.assume(amount < 1e13);

        IWrappedYearnV3Strategy _strategy = IWrappedYearnV3Strategy(address(strategy));
        airdrop(ERC20(MAINNET_USDC), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);

        // deposit into strategy happens
        uint256 shares = _strategy.deposit(amount, alice);
        // convert shares to expected amount
        uint256 withdrawAmount = _strategy.convertToAssets(shares);

        // withdraw from strategy happens
        // allow for 4 BPS of loss due to non-changing value of yearn vault but loss due to swap
        _strategy.withdraw(withdrawAmount, alice, alice, 4);
        // check for expected changes
        assertEq(deployedVault.balanceOf(testGauge), 0, "withdrawFromGauge failed");
        uint128 userBalance = IYearnStakingDelegate(address(yearnStakingDelegate)).userInfo(
            address(_strategy), address(deployedVault)
        ).balance;
        assertEq(userBalance, 0, "userInfo in ysd not updated correctly");
        assertEq(deployedVault.balanceOf(strategy.yearnStakingDelegate()), 0, "vault shares not taken from delegate");
        assertEq(deployedVault.totalSupply(), 0, "vault total_supply did not update correctly");
        assertEq(_strategy.balanceOf(alice), 0, "Withdraw was not successful");
        assertApproxEqRel(
            ERC20(MAINNET_USDC).balanceOf(alice),
            amount,
            0.004e18,
            "user balance should be deposit amount after withdraw"
        );
    }
}

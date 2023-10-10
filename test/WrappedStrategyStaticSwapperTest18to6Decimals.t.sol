// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "src/interfaces/deps/yearn/tokenized-strategy/IStrategy.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { WrappedYearnV3StrategyAssetSwapStatic } from "../src/strategies/WrappedYearnV3StrategyAssetSwapStatic.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { CurveRouterSwapper, ICurveRouter } from "src/swappers/CurveRouterSwapper.sol";
import { ERC20, IERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { ICurveBasePool } from "../src/interfaces/deps/curve/ICurveBasePool.sol";
import { Errors } from "src/libraries/Errors.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

contract WrappedStrategyStaticSwapperTest is YearnV3BaseTest {
    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 1000e18;

    // Contract Addresses
    WrappedYearnV3StrategyAssetSwapStatic public strategy;
    YearnStakingDelegate public yearnStakingDelegate;
    IVault public deployedVault;
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

        alice = createUser("alice");
        treasury = createUser("treasury");
        manager = createUser("manager");

        // Deploy mock vault to be used as underlying yield source for wrapped strategy
        {
            deployedVault = IVault(deployVaultV3("USC Vault", MAINNET_USDC, new address[](0)));
            testGauge = deployGaugeViaFactory(address(deployedVault), admin, "USDC Test Vault Gauge");
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

        // The underlying vault accepts DAI, while the wrapped strategy accepts USDC
        strategy = WrappedYearnV3StrategyAssetSwapStatic(
            address(
                setUpWrappedStrategyStaticSwapper(
                    "Wrapped YearnV3 DAI -> USDC Strategy (Asset Swap with Static Slippage)",
                    MAINNET_DAI,
                    address(deployedVault),
                    address(yearnStakingDelegate),
                    dYFI,
                    MAINNET_CURVE_ROUTER
                )
            )
        );
        vm.startPrank(users["tpManagement"]);
        {
            // set the swap parameters
            // [token_from, pool, token_to, pool, ...]
            _assetDeployParams.route[0] = MAINNET_DAI;
            _assetDeployParams.route[1] = MAINNET_CRV3POOL;
            _assetDeployParams.route[2] = MAINNET_USDC;
            _assetDeployParams.swapParams[0] = [uint256(0), 1, 1, 1, 2];

            // [token_from, pool, token_to, pool, ...]
            _assetFreeParams.route[0] = MAINNET_USDC;
            _assetFreeParams.route[1] = MAINNET_CRV3POOL;
            _assetFreeParams.route[2] = MAINNET_DAI;
            _assetFreeParams.swapParams[0] = [uint256(1), 0, 1, 1, 2];

            strategy.setSwapParameters(_assetDeployParams, _assetFreeParams, 99_500);
        }
        vm.stopPrank();
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 1e18);
        vm.assume(amount < 1e25);
        airdrop(ERC20(MAINNET_DAI), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_DAI).approve(address(strategy), amount);
        // deposit into strategy happens
        uint256 minAmountFromCurve = ICurveRouter(MAINNET_CURVE_ROUTER).get_dy(
            _assetDeployParams.route, _assetDeployParams.swapParams, amount, _assetDeployParams.pools
        );
        IWrappedYearnV3Strategy(address(strategy)).deposit(amount, alice);
        // check for expected changes

        vm.stopPrank();
        assertEq(ERC20(MAINNET_DAI).balanceOf(alice), 0, "alice still has USDC");
        assertApproxEqRel(
            ERC20(MAINNET_USDC).balanceOf(address(deployedVault)),
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
        vm.assume(amount > 1e26);
        vm.assume(amount < 1e40);
        airdrop(ERC20(MAINNET_DAI), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_DAI).approve(address(strategy), amount);
        vm.expectRevert("Slippage");
        IWrappedYearnV3Strategy(address(strategy)).deposit(amount, alice);
    }

    function testFuzz_deposit_revertWhen_depositTooBig(uint256 amount) public {
        vm.assume(amount > 1e40);
        airdrop(ERC20(MAINNET_DAI), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_DAI).approve(address(strategy), amount);
        vm.expectRevert();
        IWrappedYearnV3Strategy(address(strategy)).deposit(amount, alice);
    }

    function test_deposit_revertWhen_slippageIsHigh() public {
        uint256 amount = 1e20; // 100 DAI
        airdrop(ERC20(MAINNET_DAI), alice, amount);
        vm.prank(users["tpManagement"]);
        strategy.setSwapParameters(_assetDeployParams, _assetFreeParams, 100_000);
        vm.startPrank(alice);
        ERC20(MAINNET_DAI).approve(address(strategy), amount);
        // deposit into strategy happens
        vm.expectRevert("Slippage");
        IWrappedYearnV3Strategy(address(strategy)).deposit(amount, alice);
    }

    function test_redeem(uint256 amount) public {
        vm.assume(amount > 1e18);
        // limit fuzzing to 10 million (pool slippage is too great otherwise)
        vm.assume(amount < 1e25);

        IWrappedYearnV3Strategy _strategy = IWrappedYearnV3Strategy(address(strategy));
        airdrop(ERC20(MAINNET_DAI), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_DAI).approve(address(strategy), amount);

        // deposit into strategy happens
        uint256 shares = _strategy.deposit(amount, alice);

        // withdraw from strategy happens
        // allow for 4 BPS of loss due to non-changeing value of yearn vault but small decrease in assets due to swap
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
            ERC20(MAINNET_DAI).balanceOf(alice), amount, 0.004e18, "user balance should be deposit amount after redeem"
        );
    }

    function test_withdraw(uint256 amount) public {
        vm.assume(amount > 1e18);
        // limit fuzzing to 10 million (pool slippage is too great otherwise)
        vm.assume(amount < 1e25);

        IWrappedYearnV3Strategy _strategy = IWrappedYearnV3Strategy(address(strategy));
        airdrop(ERC20(MAINNET_DAI), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_DAI).approve(address(strategy), amount);

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
            ERC20(MAINNET_DAI).balanceOf(alice),
            amount,
            0.004e18,
            "user balance should be deposit amount after withdraw"
        );
    }
}

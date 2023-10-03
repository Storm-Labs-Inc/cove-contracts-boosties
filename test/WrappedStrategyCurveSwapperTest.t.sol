// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "src/interfaces/deps/yearn/tokenized-strategy/IStrategy.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { WrappedYearnV3StrategyCurveSwapper } from "src/strategies/WrappedYearnV3StrategyCurveSwapper.sol";
import { ERC20, IERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { ICurveBasePool } from "../src/interfaces/deps/curve/ICurveBasePool.sol";
import { MockChainLinkOracle } from "./mocks/MockChainLinkOracle.sol";
import { Errors } from "src/libraries/Errors.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

contract WrappedStrategyCurveSwapperTest is YearnV3BaseTest {
    // Oracle Addresses
    address public constant CHAINLINK_DAI_USD_MAINNET = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public constant CHAINLINK_USDC_USD_MAINNET = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 1000e18;

    // Contract Addresses
    YearnStakingDelegate public yearnStakingDelegate;
    IStrategy public mockStrategy;
    WrappedYearnV3StrategyCurveSwapper public wrappedYearnV3Strategy;
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

        // Deploy wrapped strategy with different asset than the underlying vault
        wrappedYearnV3Strategy = WrappedYearnV3StrategyCurveSwapper(
            address(
                setUpWrappedStrategyCurveSwapper(
                    "Wrapped YearnV3 USDC -> DAI Strategy (Asset Swap with Oracle)",
                    MAINNET_USDC,
                    address(deployedVault),
                    address(yearnStakingDelegate),
                    dYFI,
                    MAINNET_CURVE_ROUTER
                )
            )
        );
        vm.startPrank(users["tpManagement"]);
        // set the oracle for USDC and DAI
        wrappedYearnV3Strategy.setOracle(MAINNET_DAI, CHAINLINK_DAI_USD_MAINNET);
        wrappedYearnV3Strategy.setOracle(MAINNET_USDC, CHAINLINK_USDC_USD_MAINNET);
        {
            // set the swap parameters
            // [token_from, pool, token_to, pool, ...]
            _assetDeployParams.route[0] = MAINNET_USDC;
            _assetDeployParams.route[1] = MAINNET_CRV3POOL;
            _assetDeployParams.route[2] = MAINNET_DAI;
            _assetDeployParams.swapParams[0] = [uint256(1), 0, 1, 2, 1];

            // [token_from, pool, token_to, pool, ...]
            _assetFreeParams.route[0] = MAINNET_DAI;
            _assetFreeParams.route[1] = MAINNET_CRV3POOL;
            _assetFreeParams.route[2] = MAINNET_USDC;
            _assetFreeParams.swapParams[0] = [uint256(0), 1, 1, 2, 1];

            wrappedYearnV3Strategy.setSwapParameters(_assetDeployParams, _assetFreeParams, 99_500, 1 days);
        }
        vm.stopPrank();
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 1e13);
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(wrappedYearnV3Strategy), amount);
        // deposit into strategy happens
        IWrappedYearnV3Strategy(address(wrappedYearnV3Strategy)).deposit(amount, alice);
        // check for expected changes
        uint256 ysdBalance = deployedVault.balanceOf(wrappedYearnV3Strategy.yearnStakingDelegate());
        vm.stopPrank();
        require(ERC20(MAINNET_USDC).balanceOf(alice) == 0, "alice still has USDC");
        uint256 minAmountFromCurve = ICurveBasePool(MAINNET_CRV3POOL).get_dy(1, 0, amount);
        require(
            ysdBalance >= minAmountFromCurve - (minAmountFromCurve * 0.05e18 / 1e18),
            "vault shares not given to delegate"
        );
        require(deployedVault.totalSupply() == ysdBalance, "vault total_supply did not update correctly");
        require(
            IWrappedYearnV3Strategy(address(wrappedYearnV3Strategy)).balanceOf(alice) == amount,
            "Deposit was not successful"
        );
    }

    function testFuzz_deposit_revertsSlippageTooHigh_tooLargeDeposit(uint256 amount) public {
        vm.assume(amount > 1e14);
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(wrappedYearnV3Strategy), amount);
        vm.expectRevert();
        IWrappedYearnV3Strategy(address(wrappedYearnV3Strategy)).deposit(amount, alice);
    }

    function test_deposit_revertsSlippageTooHigh() public {
        vm.startPrank(users["tpManagement"]);
        // Setup oracles with un-pegged price
        mockDAIOracle = new MockChainLinkOracle(1e6);
        // set the oracle for USDC and DAI
        wrappedYearnV3Strategy.setOracle(MAINNET_DAI, address(mockDAIOracle));
        vm.stopPrank();
        uint256 amount = 1e8; // 100 USDC
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        mockDAIOracle.setTimestamp(block.timestamp);
        mockDAIOracle.setPrice(1e5);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(wrappedYearnV3Strategy), amount);
        // deposit into strategy happens
        vm.expectRevert(abi.encodeWithSelector(Errors.SlippageTooHigh.selector));
        IWrappedYearnV3Strategy(address(wrappedYearnV3Strategy)).deposit(amount, alice);
    }

    function test_deposit_revertsOracleOutdated() public {
        vm.startPrank(users["tpManagement"]);
        // Setup oracles with un-pegged price
        mockDAIOracle = new MockChainLinkOracle(1e6);
        // set the oracle for USDC and DAI
        wrappedYearnV3Strategy.setOracle(MAINNET_DAI, address(mockDAIOracle));
        vm.stopPrank();
        uint256 amount = 1e8; // 100 USDC
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        mockDAIOracle.setTimestamp(block.timestamp - 2 days);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(wrappedYearnV3Strategy), amount);
        // deposit into strategy happens
        vm.expectRevert(abi.encodeWithSelector(Errors.OracleOudated.selector));
        IWrappedYearnV3Strategy(address(wrappedYearnV3Strategy)).deposit(amount, alice);
    }
}

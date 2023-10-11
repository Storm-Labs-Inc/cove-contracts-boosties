// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "src/interfaces/deps/yearn/tokenized-strategy/IStrategy.sol";
import { CurveRouterSwapper, ICurveRouter } from "src/swappers/CurveRouterSwapper.sol";
import { TokenizedStrategyAssetSwapOracle } from "src/strategies/TokenizedStrategyAssetSwapOracle.sol";
import { ERC20, IERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin-5.0/contracts/interfaces/IERC4626.sol";
import { ICurveBasePool } from "../src/interfaces/deps/curve/ICurveBasePool.sol";
import { MockChainLinkOracle } from "./mocks/MockChainLinkOracle.sol";
import { Errors } from "src/libraries/Errors.sol";

contract TokenizedStrategyCurveSwapperTest is YearnV3BaseTest {
    // Oracle Addresses
    address public constant CHAINLINK_FRAX_USD_MAINNET = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address public constant CHAINLINK_USDC_USD_MAINNET = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 1000e18;

    // Contract Addresses
    TokenizedStrategyAssetSwapOracle public strategy;
    IERC4626 public deployedVault;
    MockChainLinkOracle public mockFraxOracle;
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
            deployedVault = IERC4626(deployVaultV3("sFRAX Vault", MAINNET_FRAX, new address[](0)));
        }

        // Deploy wrapped strategy with different asset than the underlying vault
        strategy = TokenizedStrategyAssetSwapOracle(
            address(
                setUpTokenizedStrategyCurveSwapper(
                    "Tokenized Strategy USDC -> FRAX Strategy (Asset Swap with Oracle)",
                    MAINNET_USDC,
                    address(deployedVault),
                    MAINNET_CURVE_ROUTER
                )
            )
        );
        vm.startPrank(users["tpManagement"]);
        // set the oracle for USDC and FRAX
        strategy.setOracle(MAINNET_FRAX, CHAINLINK_FRAX_USD_MAINNET);
        strategy.setOracle(MAINNET_USDC, CHAINLINK_USDC_USD_MAINNET);
        {
            // set the swap parameters
            // [token_from, pool, token_to, pool, ...]
            _assetDeployParams.route[0] = MAINNET_USDC;
            _assetDeployParams.route[1] = MAINNET_FRAX_USDC_POOL;
            _assetDeployParams.route[2] = MAINNET_FRAX;
            _assetDeployParams.swapParams[0] = [uint256(1), 0, 1, 1, 2];

            // [token_from, pool, token_to, pool, ...]
            _assetFreeParams.route[0] = MAINNET_FRAX;
            _assetFreeParams.route[1] = MAINNET_FRAX_USDC_POOL;
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
        IStrategy(address(strategy)).deposit(amount, alice);
        // check for expected changes

        vm.stopPrank();
        assertEq(ERC20(MAINNET_USDC).balanceOf(alice), 0, "alice still has USDC");
        assertApproxEqRel(
            ERC20(MAINNET_FRAX).balanceOf(address(deployedVault)),
            minAmountFromCurve,
            0.001e18,
            "vault did not receive correct amount of FRAX"
        );
        assertEq(IStrategy(address(strategy)).balanceOf(alice), amount, "Deposit was not successful");
    }

    function testFuzz_deposit_revertWhen_slippageIsHigh(uint256 amount) public {
        vm.assume(amount > 1e15);
        vm.assume(amount < 1e40);
        airdrop(ERC20(MAINNET_USDC), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);
        vm.expectRevert("Slippage");
        IStrategy(address(strategy)).deposit(amount, alice);
    }

    function testFuzz_deposit_revertWhen_depositTooBig(uint256 amount) public {
        vm.assume(amount > 1e40);
        airdrop(ERC20(MAINNET_USDC), alice, amount);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);
        vm.expectRevert();
        IStrategy(address(strategy)).deposit(amount, alice);
    }

    function test_deposit_revertWhen_slippageIsHighMockOracle() public {
        vm.startPrank(users["tpManagement"]);
        // Setup oracles with un-pegged price
        mockFraxOracle = new MockChainLinkOracle(1e6);
        // set the oracle for USDC and FRAX
        strategy.setOracle(MAINNET_FRAX, address(mockFraxOracle));
        vm.stopPrank();
        uint256 amount = 1e8; // 100 USDC
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        mockFraxOracle.setTimestamp(block.timestamp);
        mockFraxOracle.setPrice(1e5); // Oracle reporting 1 USDC = 100 FRAX, resulting higher expected return amount
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);
        // deposit into strategy happens
        vm.expectRevert("Slippage");
        IStrategy(address(strategy)).deposit(amount, alice);
    }

    function test_deposit_revertWhen_oracleOutdated() public {
        vm.startPrank(users["tpManagement"]);
        // Setup oracles with un-pegged price
        mockFraxOracle = new MockChainLinkOracle(1e18);
        // set the oracle for USDC and FRAX
        strategy.setOracle(MAINNET_FRAX, address(mockFraxOracle));
        vm.stopPrank();
        uint256 amount = 1e8; // 100 USDC
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        mockFraxOracle.setTimestamp(block.timestamp - 2 days);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);
        // deposit into strategy happens
        vm.expectRevert(abi.encodeWithSelector(Errors.OracleOudated.selector));
        IStrategy(address(strategy)).deposit(amount, alice);
    }

    function test_redeem(uint256 amount) public {
        vm.assume(amount > 1e8);
        // limit fuzzing to 1 million (pool slippage is too great otherwise)
        vm.assume(amount < 1e13);
        amount = 1e8;
        IStrategy _strategy = IStrategy(address(strategy));
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

        IStrategy _strategy = IStrategy(address(strategy));
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

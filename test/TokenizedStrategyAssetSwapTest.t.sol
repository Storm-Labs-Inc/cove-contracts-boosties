// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { IStrategy } from "@tokenized-strategy/interfaces/IStrategy.sol";
import { CurveRouterSwapper, ICurveRouter } from "src/swappers/CurveRouterSwapper.sol";
import { TokenizedStrategyAssetSwap } from "src/strategies/TokenizedStrategyAssetSwap.sol";
import { StrategyAssetSwap } from "src/strategies/StrategyAssetSwap.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { MockChainLinkOracle } from "./mocks/MockChainLinkOracle.sol";
import { Errors } from "src/libraries/Errors.sol";

contract TokenizedStrategyAssetSwapTest is YearnV3BaseTest {
    // Oracle Addresses
    address public constant CHAINLINK_FRAX_USD_MAINNET = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address public constant CHAINLINK_USDC_USD_MAINNET = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 1000e18;

    // Contract Addresses
    TokenizedStrategyAssetSwap public strategy;
    IERC4626 public deployedVault;
    MockChainLinkOracle public mockFRAXOracle;
    MockChainLinkOracle public mockUSDCOracle;
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
        strategy = TokenizedStrategyAssetSwap(
            address(
                setUpTokenizedStrategyAssetSwap(
                    "Tokenized Strategy USDC -> FRAX Strategy (Asset Swap with Oracle)",
                    MAINNET_USDC,
                    address(deployedVault),
                    MAINNET_CURVE_ROUTER,
                    // specifies that we do want to use oracles for price fetching
                    true
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

            // set the swap tolerance
            StrategyAssetSwap.SwapTolerance memory swapTolerance =
                StrategyAssetSwap.SwapTolerance({ slippageTolerance: 99_500, timeTolerance: 1 days });

            strategy.setSwapParameters(_assetDeployParams, _assetFreeParams, swapTolerance);
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

    // TODO: why does below not revert correctly
    function test_deposit_revertWhen_slippageIsHigh_MockOracleStrategyAsset() public {
        vm.startPrank(users["tpManagement"]);
        // Setup oracles with un-pegged price
        mockUSDCOracle = new MockChainLinkOracle(1e9); // Oracle Reporting 10USD = 1 USDC
        // set the oracle for USDC and FRAX
        strategy.setOracle(MAINNET_USDC, address(mockUSDCOracle));
        vm.stopPrank();
        uint256 amount = 1e8; // 100 USDC
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        mockUSDCOracle.setTimestamp(block.timestamp);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);
        // deposit into strategy happens
        vm.expectRevert("Slippage");
        IStrategy(address(strategy)).deposit(amount, alice);
    }

    function test_deposit_revertWhen_slippageIsHigh_MockOracleVaultAsset() public {
        vm.startPrank(users["tpManagement"]);
        // Setup oracles with un-pegged price
        mockFRAXOracle = new MockChainLinkOracle(1e7); // Oracle Reporting 1USD = 10 FRAX
        // set the oracle for USDC and FRAX
        strategy.setOracle(MAINNET_FRAX, address(mockFRAXOracle));
        vm.stopPrank();
        uint256 amount = 1e8; // 100 USDC
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        mockFRAXOracle.setTimestamp(block.timestamp);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);
        // deposit into strategy happens
        vm.expectRevert("Slippage");
        IStrategy(address(strategy)).deposit(amount, alice);
    }

    function test_deposit_revertWhen_oracleOutdated() public {
        vm.startPrank(users["tpManagement"]);
        // Setup oracles with un-pegged price
        mockFRAXOracle = new MockChainLinkOracle(1e18);
        // set the oracle for USDC and FRAX
        strategy.setOracle(MAINNET_FRAX, address(mockFRAXOracle));
        vm.stopPrank();
        uint256 amount = 1e8; // 100 USDC
        deal({ token: MAINNET_USDC, to: alice, give: amount });
        mockFRAXOracle.setTimestamp(block.timestamp - 2 days);
        vm.startPrank(alice);
        ERC20(MAINNET_USDC).approve(address(strategy), amount);
        // deposit into strategy happens
        vm.expectRevert(abi.encodeWithSelector(Errors.OracleOutdated.selector));
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

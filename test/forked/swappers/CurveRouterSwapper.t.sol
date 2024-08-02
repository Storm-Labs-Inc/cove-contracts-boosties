// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { MockCurveRouterSwapper } from "test/mocks/MockCurveRouterSwapper.sol";
import { CurveSwapParamsConstants } from "test/utils/CurveSwapParamsConstants.sol";

contract CurveRouterSwapperTest is BaseTest, CurveSwapParamsConstants {
    address public alice;
    MockCurveRouterSwapper public swapper;

    function setUp() public override {
        forkNetworkAt("mainnet", 20_442_138);
        super.setUp();
        _labelEthereumAddresses();

        alice = createUser("alice");
        swapper = new MockCurveRouterSwapper(MAINNET_CURVE_ROUTER);
        vm.label(address(swapper), "CurveRouterSwapper");

        airdrop(ERC20(MAINNET_DAI), address(swapper), 1000 * 10 ** ERC20(MAINNET_DAI).decimals());
        airdrop(ERC20(MAINNET_USDT), address(swapper), 1000 * 10 ** ERC20(MAINNET_USDT).decimals());
    }

    function testFuzz_constructor_revertWhen_ZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        new CurveRouterSwapper(address(0));
    }

    function test_approveTokenForSwap() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        assertEq(ERC20(MAINNET_DAI).allowance(address(swapper), MAINNET_CURVE_ROUTER), type(uint256).max);
        swapper.approveTokenForSwap(MAINNET_USDT);
        assertEq(ERC20(MAINNET_USDT).allowance(address(swapper), MAINNET_CURVE_ROUTER), type(uint256).max);
    }

    function test_swap() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        curveSwapParams.route[0] = MAINNET_DAI;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDC;
        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 1, 1, 1, 3]; // DAI -> USDC
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_DAI).decimals();
        uint256 expected = 999 * 10 ** ERC20(MAINNET_USDT).decimals();
        // Assert return value is expected
        uint256 returnVal = swapper.swap(curveSwapParams, amount, expected, address(swapper));
        assertApproxEqRel(returnVal, expected, 0.01e18);
        // Assert balances match the return value
        assertEq(ERC20(MAINNET_USDC).balanceOf(address(swapper)), returnVal);
        // Assert DAI is all used up
        assertEq(ERC20(MAINNET_DAI).balanceOf(address(swapper)), 0);
    }

    function test_swap_revertWhen_IndexOutOfRange() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        curveSwapParams.route[0] = MAINNET_DAI;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDC;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 3, 1, 1, 4]; // j = 3 is out of range
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_DAI).decimals();
        uint256 expected = 999 * 10 ** ERC20(MAINNET_USDT).decimals();
        // Assert return value is expected
        vm.expectRevert();
        swapper.swap(curveSwapParams, amount, expected, address(swapper));
    }

    function test_swap_revertWhen_ExpectedNotReached() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        curveSwapParams.route[0] = MAINNET_DAI;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDC;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 1, 1, 1, 3];
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_DAI).decimals();
        uint256 expected = 1000 * 10 ** ERC20(MAINNET_USDT).decimals();
        vm.expectRevert("Slippage");
        swapper.swap(curveSwapParams, amount, expected, address(swapper));
    }

    function test_swap_passWhenUsingUSDT() public {
        swapper.approveTokenForSwap(MAINNET_USDT);

        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_USDT;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDC;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(2), 1, 1, 1, 3]; // USDT -> USDC
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_USDT).decimals();
        uint256 expected = 999 * 10 ** ERC20(MAINNET_USDC).decimals();

        // Assert return value is expected
        uint256 returnVal = swapper.swap(curveSwapParams, amount, 0, address(swapper));
        assertApproxEqRel(returnVal, expected, 0.01e18);
        // Assert balances match the return value
        assertEq(ERC20(MAINNET_USDC).balanceOf(address(swapper)), returnVal);
        // Assert USDT is all used up
        assertEq(ERC20(MAINNET_USDT).balanceOf(address(swapper)), 0);
    }

    function test_swap_passWhenSwappingThroughStableAndCrypto() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_DAI;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDT;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_2;
        curveSwapParams.route[4] = MAINNET_WETH;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 2, 1, 1, 3]; // DAI -> USDT
        curveSwapParams.swapParams[1] = [uint256(0), 2, 1, 3, 3]; // USDT -> WETH
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_DAI).decimals();
        uint256 expected = 0.329e18;

        // Assert return value is expected
        uint256 returnVal = swapper.swap(curveSwapParams, amount, expected, address(swapper));
        assertApproxEqRel(returnVal, expected, 0.01e18);
        // Assert balances match the return value
        assertEq(ERC20(MAINNET_WETH).balanceOf(address(swapper)), returnVal);
        // Assert DAI is all used up
        assertEq(ERC20(MAINNET_DAI).balanceOf(address(swapper)), 0);
    }

    function test_swap_revertWhen_UsingInvalidSwapParams() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_DAI;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDT;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_2;
        curveSwapParams.route[4] = MAINNET_WETH;

        // i, j, swap_type, pool_type, n_coins
        // Swap is invalid because DAI -> USDC != USDT -> WETH
        curveSwapParams.swapParams[0] = [uint256(0), 1, 1, 1, 3]; // DAI -> USDC
        curveSwapParams.swapParams[1] = [uint256(0), 2, 1, 3, 3]; // USDT -> WETH
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_DAI).decimals();
        uint256 expected = 0.608e18;

        // Assert return value is expected
        vm.expectRevert();
        swapper.swap(curveSwapParams, amount, expected, address(swapper));
    }

    function test_swap_passWhenUsingEthSwapThreeTimes() public {
        swapper.approveTokenForSwap(MAINNET_USDT);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_USDT;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDC;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_USDC;
        curveSwapParams.route[4] = MAINNET_ETH;
        curveSwapParams.route[5] = MAINNET_ETH_YFI_POOL;
        curveSwapParams.route[6] = MAINNET_YFI;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(2), 1, 1, 1, 3]; // USDT -> USDC
        curveSwapParams.swapParams[1] = [uint256(0), 2, 1, 2, 3]; // USDC -> ETH
        curveSwapParams.swapParams[2] = [uint256(0), 1, 1, 2, 2]; // ETH -> YFI
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_USDT).decimals();
        uint256 expected = 184_220_632_912_974_240;
        uint256 returnVal = swapper.swap(curveSwapParams, amount, expected, address(swapper));
        assertApproxEqRel(returnVal, expected, 0.01e18);
        // Assert balances match the return value
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), returnVal);
        // Assert USDT is all used up
        assertEq(ERC20(MAINNET_USDT).balanceOf(address(swapper)), 0);
    }

    function test_validateSwapParams() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_DAI;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDT;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_2;
        curveSwapParams.route[4] = MAINNET_WETH;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 2, 1, 1, 3]; // DAI -> USDT
        curveSwapParams.swapParams[1] = [uint256(0), 2, 1, 3, 3]; // USDT -> WETH

        swapper.validateSwapParams(curveSwapParams, MAINNET_DAI, MAINNET_WETH);
    }

    function test_validateSwapParams_revertWhen_EmptyRoute() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 2, 1, 1, 3]; // DAI -> USDT
        curveSwapParams.swapParams[1] = [uint256(0), 2, 1, 3, 3]; // USDT -> WETH

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFromToken.selector, MAINNET_DAI, address(0)));
        swapper.validateSwapParams(curveSwapParams, MAINNET_DAI, MAINNET_WETH);
    }

    function test_validateSwapParams_revertWhen_InvalidRouteFromTokenMismatch() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_USDT;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDC;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_2;
        curveSwapParams.route[4] = MAINNET_WETH;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 2, 1, 1, 3]; // DAI -> USDT
        curveSwapParams.swapParams[1] = [uint256(0), 2, 1, 3, 3]; // USDT -> WETH

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFromToken.selector, MAINNET_DAI, MAINNET_USDT));
        swapper.validateSwapParams(curveSwapParams, MAINNET_DAI, MAINNET_WETH);
    }

    function test_validateSwapParams_revertWhen_InvalidRouteToTokenMismatch() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_DAI;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDT;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_2;
        curveSwapParams.route[4] = MAINNET_ETH;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 2, 1, 1, 3]; // DAI -> USDT
        curveSwapParams.swapParams[1] = [uint256(0), 2, 1, 3, 3]; // USDT -> WETH

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidToToken.selector, MAINNET_WETH, MAINNET_ETH));
        swapper.validateSwapParams(curveSwapParams, MAINNET_DAI, MAINNET_WETH);
    }

    function test_validateSwapParams_revertWhen_NextInvalidTokenIndex() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_DAI;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDT;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_2;
        curveSwapParams.route[4] = MAINNET_WETH;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(0), 1, 1, 1, 3]; // DAI -> USDC
        curveSwapParams.swapParams[1] = [uint256(0), 5, 1, 3, 3]; // USDT -> WETH

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSwapParams.selector));
        swapper.validateSwapParams(curveSwapParams, MAINNET_DAI, MAINNET_WETH);
    }

    function test_validateSwapParams_revertWhen_FromTokenInvalidTokenIndex() public {
        swapper.approveTokenForSwap(MAINNET_DAI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_DAI;
        curveSwapParams.route[1] = MAINNET_CRV3POOL;
        curveSwapParams.route[2] = MAINNET_USDT;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_2;
        curveSwapParams.route[4] = MAINNET_WETH;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 1, 3]; // DAI -> USDC
        curveSwapParams.swapParams[1] = [uint256(0), 2, 1, 3, 3]; // USDT -> WETH

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSwapParams.selector));
        swapper.validateSwapParams(curveSwapParams, MAINNET_DAI, MAINNET_WETH);
    }
    // YearnGuageStrategy swap params tests

    function test_swap_MainnetWethYethGaugeCurveSwapParams() public {
        airdrop(ERC20(MAINNET_YFI), address(swapper), 1000 * 10 ** ERC20(MAINNET_YFI).decimals());
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetWethYethGaugeCurveSwapParams();

        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert lp token was received
        assertGt(ERC20(MAINNET_WETH_YETH_POOL_LP_TOKEN).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }

    function test_swap_mainnetEthYfiGaugeCurveSwapParams() public {
        airdrop(ERC20(MAINNET_YFI), address(swapper), 1000 * 10 ** ERC20(MAINNET_YFI).decimals());
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetEthYfiGaugeCurveSwapParams();

        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert lp token was received
        assertGt(ERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }

    function test_swap_mainnetDyfiEthGaugeCurveSwapParams() public {
        airdrop(ERC20(MAINNET_YFI), address(swapper), 1000 * 10 ** ERC20(MAINNET_YFI).decimals());
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetDyfiEthGaugeCurveSwapParams();

        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert lp token was received
        assertGt(ERC20(MAINNET_DYFI_ETH_POOL_LP_TOKEN).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }

    function test_swap_mainnetCrvYcrvPoolGaugeCurveSwapParams() public {
        airdrop(ERC20(MAINNET_YFI), address(swapper), 1000 * 10 ** ERC20(MAINNET_YFI).decimals());
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetCrvYcrvPoolGaugeCurveSwapParams();

        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert lp token was received
        assertGt(ERC20(MAINNET_CRV_YCRV_POOL_LP_TOKEN).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }

    function test_swap_mainnetPrismaYprismaPoolGaugeCurveSwapParams() public {
        airdrop(ERC20(MAINNET_YFI), address(swapper), 1000 * 10 ** ERC20(MAINNET_YFI).decimals());
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetPrismaYprismaPoolGaugeCurveSwapParams();

        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert lp token was received
        assertGt(ERC20(MAINNET_PRISMA_YPRISMA_POOL_LP_TOKEN).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }

    function test_swap_mainnetYvusdcGaugeCurveSwapParams() public {
        airdrop(ERC20(MAINNET_YFI), address(swapper), 1000 * 10 ** ERC20(MAINNET_YFI).decimals());
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetYvusdcGaugeCurveSwapParams();

        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert lp token was received
        assertGt(ERC20(MAINNET_USDC).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }

    function test_swap_mainnetYvdaiGaugeCurveSwapParams() public {
        airdrop(ERC20(MAINNET_YFI), address(swapper), 1000 * 10 ** ERC20(MAINNET_YFI).decimals());
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetYvdaiGaugeCurveSwapParams();

        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert lp token was received
        assertGt(ERC20(MAINNET_DAI).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }

    function test_swap_mainnetYvwethGaugeCurveSwapParams() public {
        airdrop(ERC20(MAINNET_YFI), address(swapper), 1000 * 10 ** ERC20(MAINNET_YFI).decimals());
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetYvwethGaugeCurveSwapParams();

        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert lp token was received
        assertGt(ERC20(MAINNET_WETH).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }

    function test_swap_mainnetCoveyfiYfiGaugeCurveSwapParams() public {
        swapper = new MockCurveRouterSwapper(MAINNET_CURVE_ROUTER_NG);
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        airdrop(ERC20(MAINNET_YFI), address(swapper), amount);
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetCoveyfiYfiGaugeCurveSwapParams();

        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert lp token was received
        assertGt(ERC20(MAINNET_COVEYFI_YFI_POOL_LP_TOKEN).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }

    function test_swap_mainnetYvdai2GaugeCurveSwapParams() public {
        swapper = new MockCurveRouterSwapper(MAINNET_CURVE_ROUTER_NG);
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        airdrop(ERC20(MAINNET_YFI), address(swapper), amount);
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetYvdai2GaugeCurveSwapParams();

        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert DAI was received
        assertGt(ERC20(MAINNET_DAI).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }

    function test_swap_mainnetYvweth2GaugeCurveSwapParams() public {
        swapper = new MockCurveRouterSwapper(MAINNET_CURVE_ROUTER_NG);
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        airdrop(ERC20(MAINNET_YFI), address(swapper), amount);
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetYvweth2GaugeCurveSwapParams();

        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert WETH was received
        assertGt(ERC20(MAINNET_WETH).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }

    function test_swap_mainnetYvcrvusd2GaugeCurveSwapParams() public {
        swapper = new MockCurveRouterSwapper(MAINNET_CURVE_ROUTER_NG);
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_YFI).decimals();
        airdrop(ERC20(MAINNET_YFI), address(swapper), amount);
        swapper.approveTokenForSwap(MAINNET_YFI);
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams = getMainnetYvcrvusd2GaugeCurveSwapParams();

        swapper.swap(curveSwapParams, amount, 0, address(swapper));
        // Assert CRVUSD was received
        assertGt(ERC20(MAINNET_CRVUSD).balanceOf(address(swapper)), 0);
        // Assert YFI is all used up
        assertEq(ERC20(MAINNET_YFI).balanceOf(address(swapper)), 0);
    }
}

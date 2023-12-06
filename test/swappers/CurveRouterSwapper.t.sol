// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "../utils/BaseTest.t.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { MockCurveRouterSwapper } from "test/mocks/MockCurveRouterSwapper.sol";

contract CurveRouterSwapperTest is BaseTest {
    address public alice;
    MockCurveRouterSwapper public swapper;

    function setUp() public override {
        forkNetworkAt("mainnet", 18_172_262);
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
        uint256 returnVal = swapper.swap(curveSwapParams, amount, expected, address(swapper));
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
        uint256 expected = 0.608e18;

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
        vm.expectRevert("Received nothing");
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
        curveSwapParams.route[5] = MAINNET_YFI_ETH_POOL;
        curveSwapParams.route[6] = MAINNET_YFI;

        // i, j, swap_type, pool_type, n_coins
        curveSwapParams.swapParams[0] = [uint256(2), 1, 1, 1, 3]; // USDT -> USDC
        curveSwapParams.swapParams[1] = [uint256(0), 2, 1, 2, 3]; // USDC -> ETH
        curveSwapParams.swapParams[2] = [uint256(0), 1, 1, 2, 2]; // ETH -> YFI
        uint256 amount = 1000 * 10 ** ERC20(MAINNET_USDT).decimals();
        uint256 expected = 0.183e18;

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
}

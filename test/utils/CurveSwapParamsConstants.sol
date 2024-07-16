// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { Constants } from "test/utils/Constants.sol";

/**
 * @title Curve Swap Params Constants
 * @notice Contains constant parameters for Curve swaps
 */
contract CurveSwapParamsConstants is Constants {
    function getMainnetWethYethGaugeCurveSwapParams() public pure returns (CurveRouterSwapper.CurveSwapParams memory) {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        curveSwapParams.route[0] = MAINNET_YFI;
        curveSwapParams.route[1] = MAINNET_ETH_YFI_POOL;
        curveSwapParams.route[2] = MAINNET_WETH;
        curveSwapParams.route[3] = MAINNET_WETH_YETH_POOL;
        curveSwapParams.route[4] = MAINNET_WETH_YETH_POOL_LP_TOKEN; // expect the lp token back
        // i, j, swap_type, pool_type, n_coins
        // YFI -> WETH
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2];
        // ETH -> weth/yeth pool lp token, swap type is 4 to notify the swap router to call add_liquidity()
        curveSwapParams.swapParams[1] = [uint256(0), 0, 4, 1, 2];

        return curveSwapParams;
    }

    function getMainnetEthYfiGaugeCurveSwapParams() public pure returns (CurveRouterSwapper.CurveSwapParams memory) {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_YFI;
        curveSwapParams.route[1] = MAINNET_ETH_YFI_POOL;
        curveSwapParams.route[2] = MAINNET_ETH_YFI_POOL_LP_TOKEN; // expect the lp token back

        // i, j, swap_type, pool_type, n_coins
        // YFI -> yfi/eth pool lp token, swap type is 4 to notify the swap router to call add_liquidity()
        curveSwapParams.swapParams[0] = [uint256(1), 0, 4, 1, 2];
        return curveSwapParams;
    }

    function getMainnetDyfiEthGaugeCurveSwapParams() public pure returns (CurveRouterSwapper.CurveSwapParams memory) {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_YFI;
        curveSwapParams.route[1] = MAINNET_ETH_YFI_POOL;
        curveSwapParams.route[2] = MAINNET_WETH;
        curveSwapParams.route[3] = MAINNET_DYFI_ETH_POOL;
        curveSwapParams.route[4] = MAINNET_DYFI_ETH_POOL_LP_TOKEN; // expect the lp token back

        // i, j, swap_type, pool_type, n_coins
        // YFI -> WETH
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2];
        // YFI -> yfi/eth pool lp token, swap type is 4 to notify the swap router to call add_liquidity()
        curveSwapParams.swapParams[1] = [uint256(1), 0, 4, 1, 2];
        return curveSwapParams;
    }

    function getMainnetCrvYcrvPoolGaugeCurveSwapParams()
        public
        pure
        returns (CurveRouterSwapper.CurveSwapParams memory)
    {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_YFI;
        curveSwapParams.route[1] = MAINNET_ETH_YFI_POOL;
        curveSwapParams.route[2] = MAINNET_WETH;
        curveSwapParams.route[3] = MAINNET_TRICRV_POOL;
        curveSwapParams.route[4] = MAINNET_CRV;
        curveSwapParams.route[5] = MAINNET_CRV_YCRV_POOL;
        curveSwapParams.route[6] = MAINNET_CRV_YCRV_POOL_LP_TOKEN; // expect the lp token back

        // i, j, swap_type, pool_type, n_coins
        // YFI -> WETH
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2];
        // WETH -> CRV
        curveSwapParams.swapParams[1] = [uint256(1), 2, 1, 3, 3];
        // CRV -> crv/ycrv pool lp token, swap type is 4 to notify the swap router to call add_liquidity()
        curveSwapParams.swapParams[2] = [uint256(0), 0, 4, 1, 2];
        return curveSwapParams;
    }

    function getMainnetPrismaYprismaPoolGaugeCurveSwapParams()
        public
        pure
        returns (CurveRouterSwapper.CurveSwapParams memory)
    {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_YFI;
        curveSwapParams.route[1] = MAINNET_ETH_YFI_POOL;
        curveSwapParams.route[2] = MAINNET_WETH;
        curveSwapParams.route[3] = MAINNET_ETH_PRISMA_POOL;
        curveSwapParams.route[4] = MAINNET_PRISMA;
        curveSwapParams.route[5] = MAINNET_PRISMA_YPRISMA_POOL;
        curveSwapParams.route[6] = MAINNET_PRISMA_YPRISMA_POOL_LP_TOKEN; // expect the lp token back

        // i, j, swap_type, pool_type, n_coins
        // YFI -> WETH
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2];
        // WETH -> PRISMA
        curveSwapParams.swapParams[1] = [uint256(0), 1, 1, 2, 2];
        // PRISMA -> prisma/yprisma pool lp token, swap type is 4 to notify the swap router to call add_liquidity()
        curveSwapParams.swapParams[2] = [uint256(0), 0, 4, 1, 2];
        return curveSwapParams;
    }

    function getMainnetYvusdcGaugeCurveSwapParams() public pure returns (CurveRouterSwapper.CurveSwapParams memory) {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_YFI;
        curveSwapParams.route[1] = MAINNET_ETH_YFI_POOL;
        curveSwapParams.route[2] = MAINNET_WETH;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_USDC;
        curveSwapParams.route[4] = MAINNET_USDC;

        // i, j, swap_type, pool_type, n_coins
        // YFI -> WETH
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2];
        // WETH -> USDC
        curveSwapParams.swapParams[1] = [uint256(2), 0, 1, 2, 3];
        return curveSwapParams;
    }

    function getMainnetYvdaiGaugeCurveSwapParams() public pure returns (CurveRouterSwapper.CurveSwapParams memory) {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_YFI;
        curveSwapParams.route[1] = MAINNET_ETH_YFI_POOL;
        curveSwapParams.route[2] = MAINNET_WETH;
        curveSwapParams.route[3] = MAINNET_TRI_CRYPTO_2;
        curveSwapParams.route[4] = MAINNET_USDT;
        curveSwapParams.route[5] = MAINNET_CRV3POOL;
        curveSwapParams.route[6] = MAINNET_DAI;

        // i, j, swap_type, pool_type, n_coins
        // YFI -> WETH
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2];
        // WETH -> USDT
        curveSwapParams.swapParams[1] = [uint256(2), 0, 1, 3, 3];
        // USDT -> DAI
        curveSwapParams.swapParams[2] = [uint256(2), 0, 1, 1, 3];
        return curveSwapParams;
    }

    function getMainnetYvwethGaugeCurveSwapParams() public pure returns (CurveRouterSwapper.CurveSwapParams memory) {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_YFI;
        curveSwapParams.route[1] = MAINNET_ETH_YFI_POOL;
        curveSwapParams.route[2] = MAINNET_WETH;

        // i, j, swap_type, pool_type, n_coins
        // YFI -> WETH
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2];
        return curveSwapParams;
    }

    function getMainnetCoveyfiYfiGaugeCurveSwapParams()
        public
        pure
        returns (CurveRouterSwapper.CurveSwapParams memory)
    {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_YFI;
        curveSwapParams.route[1] = MAINNET_COVEYFI_YFI_POOL;
        curveSwapParams.route[2] = MAINNET_COVEYFI_YFI_POOL_LP_TOKEN; // expect the lp token back

        // i, j, swap_type, pool_type, n_coins
        // YFI -> coveyfi/yfi pool lp token, swap type is 4 to notify the swap router to call add_liquidity()
        curveSwapParams.swapParams[0] = [uint256(1), 0, 4, 10, 2];
        return curveSwapParams;
    }
}

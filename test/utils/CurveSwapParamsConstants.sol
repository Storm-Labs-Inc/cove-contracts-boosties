// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { Constants } from "test/utils/Constants.sol";

/**
 * @title Curve Swap Params Constants
 * @notice Contains constant parameters for Curve swaps
 * CurveRouterNGv1.2 expects below params
 * def exchange(
 *     _route: address[11],
 *     _swap_params: uint256[5][5],
 *     _amount: uint256,
 *     _min_dy: uint256,
 *     _pools: address[5]=empty(address[5]),
 *     _receiver: address=msg.sender
 * ) -> uint256:
 *     """
 *     Performs up to 5 swaps in a single transaction.
 *     Routing and swap params must be determined off-chain. This
 *     functionality is designed for gas efficiency over ease-of-use.
 *
 *     _route Array of [initial token, pool or zap, token, pool or zap, token, ...]
 *     The array is iterated until a pool address of 0x00, then the last
 *     given token is transferred to `_receiver`
 *
 *     _swap_params Multidimensional array of [i, j, swap_type, pool_type, n_coins] where
 *     i is the index of input token
 *     j is the index of output token
 *     For ERC4626:
 *         i == 0 - asset -> share
 *         i == 1 - share -> asset
 *
 *     The swap_type should be:
 *     1. for `exchange`,
 *     2. for `exchange_underlying`,
 *     3. for underlying exchange via zap: factory stable metapools with lending base pool
 *     `exchange_underlying` and factory crypto-meta pools underlying exchange (`exchange` method in zap)
 *     4. for coin -> LP token "exchange" (actually `add_liquidity`),
 *     5. for lending pool underlying coin -> LP token "exchange" (actually `add_liquidity`),
 *     6. for LP token -> coin "exchange" (actually `remove_liquidity_one_coin`)
 *     7. for LP token -> lending or fake pool underlying coin "exchange" (actually `remove_liquidity_one_coin`)
 *     8. for ETH <-> WETH, ETH -> stETH or ETH -> frxETH, stETH <-> wstETH, ETH -> wBETH
 *     9. for ERC4626 asset <-> share
 *
 *     pool_type: 1 - stable, 2 - twocrypto, 3 - tricrypto, 4 - llamma
 *                10 - stable-ng, 20 - twocrypto-ng, 30 - tricrypto-ng
 *
 *     n_coins is the number of coins in pool
 *
 *     _amount The amount of input token (`_route[0]`) to be sent.
 *     _min_dy The minimum amount received after the final swap.
 *     _pools Array of pools for swaps via zap contracts. This parameter is only needed for swap_type = 3.
 *     _receiver Address to transfer the final output token to.
 *     Returns received amount of the final output token.
 *     """
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

    function getMainnetYvdai2GaugeCurveSwapParams() public pure returns (CurveRouterSwapper.CurveSwapParams memory) {
        return getMainnetYvdaiGaugeCurveSwapParams();
    }

    function getMainnetYvweth2GaugeCurveSwapParams() public pure returns (CurveRouterSwapper.CurveSwapParams memory) {
        return getMainnetYvwethGaugeCurveSwapParams();
    }

    function getMainnetYvcrvusd2GaugeCurveSwapParams()
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
        curveSwapParams.route[4] = MAINNET_CRVUSD;

        // i, j, swap_type, pool_type, n_coins
        // YFI -> WETH
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2];
        // WETH -> CRVUSD
        curveSwapParams.swapParams[1] = [uint256(1), 0, 1, 3, 3];
        return curveSwapParams;
    }

    function getMainnetYvusdsGaugeCurveSwapParams() public pure returns (CurveRouterSwapper.CurveSwapParams memory) {
        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;

        // Full path: YFI -> WETH -> CRVUSD -> SCRVUSD -> USDS
        curveSwapParams.route[0] = MAINNET_YFI;
        curveSwapParams.route[1] = MAINNET_ETH_YFI_POOL;
        curveSwapParams.route[2] = MAINNET_ETH;
        curveSwapParams.route[3] = MAINNET_TRICRV_POOL;
        curveSwapParams.route[4] = MAINNET_CRVUSD;
        curveSwapParams.route[5] = MAINNET_SCRVUSD; // Use 4626 to convert CRVUSD to SCRVUSD
        curveSwapParams.route[6] = MAINNET_SCRVUSD;
        curveSwapParams.route[7] = MAINNET_SCRVUSD_SUSDS_POOL;
        curveSwapParams.route[8] = MAINNET_SUSDS;
        curveSwapParams.route[9] = MAINNET_SUSDS; // Use 4626 to convert SUSDS to USDS
        curveSwapParams.route[10] = MAINNET_USDS;

        // i, j, swap_type, pool_type, n_coins for each step
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2]; // YFI -> WETH
        curveSwapParams.swapParams[1] = [uint256(1), 0, 1, 2, 3]; // WETH -> CRVUSD
        curveSwapParams.swapParams[2] = [uint256(0), 1, 9, 0, 0]; // CRVUSD -> SCRVUSD
        curveSwapParams.swapParams[3] = [uint256(0), 1, 1, 10, 2]; // SCRVUSD -> SUSDS
        curveSwapParams.swapParams[4] = [uint256(1), 0, 9, 0, 0]; // SUSDS -> USDS

        return curveSwapParams;
    }
}

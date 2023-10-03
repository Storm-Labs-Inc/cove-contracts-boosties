// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface ICurveRouter {
    /**
     * @notice Performs an exchange operation.
     * @dev `route` and `swapParams` should be determined off chain.
     * @param route An array of [initial token, pool or zap, token, pool or zap, token, ...]. The iteration continues
     * until a pool address of 0x00, then the last given token is transferred to `_receiver`
     * @param swapParams A multidimensional array of [i, j, swap type, pool_type, n_coins] where:
     * i is the index of the input token,
     * j is the index of the output token,
     * swap type should be:
     *         - 1 for `exchange`,
     *         - 2 for `exchange_underlying`,
     *         - 3 for underlying exchange via zap: factory stable metapools with lending base pool
     * `exchange_underlying` and factory crypto-metapools underlying exchange (`exchange` method in zap);
     *         - 4 for coin -> LP token "exchange" (actually `add_liquidity`),
     *         - 5 for lending pool underlying coin -> LP token "exchange" (actually `add_liquidity`),
     *         - 6 for LP token -> coin "exchange" (actually `remove_liquidity_one_coin`),
     *         - 7 for LP token -> lending or fake pool underlying coin "exchange" (actually
     * `remove_liquidity_one_coin`),
     *         - 8 for ETH <-> WETH, ETH -> stETH or ETH -> frxETH, stETH <-> wstETH, frxETH <-> sfrxETH, ETH -> wBETH,
     *         - 9 for SNX swaps (sUSD, sEUR, sETH, sBTC)
     *         Pool type:
     *         - 1 - stable, 2 - crypto, 3 - tricrypto, 4 - llama
     *         `n_coins` indicates the number of coins in the pool
     * @param amount The amount of `route[0]` to be sent.
     * @param expected The minimum amount received after the final swap.
     * @return The received amount of the final output token.
     */
    function exchange(
        address[11] calldata route,
        uint256[5][5] calldata swapParams,
        uint256 amount,
        uint256 expected
    )
        external
        returns (uint256);

    /**
     * @notice Performs up to 5 swaps in a single transaction.
     * @dev Routing and swap params must be determined off-chain. This functionality is designed for gas efficiency over
     * ease-of-use.
     * @param route Array of the route.
     * @param swapParams Parameters for the swap operation.
     * @param amount The amount of `route[0]` to be sent.
     * @param expected The minimum amount expected after all the swaps.
     * @param pools Array of pool addresses for swaps via zap contracts. Needed only for swap type = 3.
     * @param receiver The address to transfer the final output token to.
     * @return The received amount of the final output token.
     */
    function exchange(
        address[11] calldata route,
        uint256[5][5] calldata swapParams,
        uint256 amount,
        uint256 expected,
        address[5] calldata pools,
        address receiver
    )
        external
        returns (uint256);

    /**
     * @notice Executes an exchange operation.
     * @param route Array containing the route for exchange.
     * @param swapParams Parameters for the swap operation.
     * @param amount The amount of input token to be sent.
     * @param expected The minimum amount expected after the exchange.
     * @param pools Array of pool addresses for swaps via zap contracts.
     * @return The received amount of the final output token.
     */
    function exchange(
        address[11] calldata route,
        uint256[5][5] calldata swapParams,
        uint256 amount,
        uint256 expected,
        address[5] calldata pools
    )
        external
        returns (uint256);

    function get_dy(
        address[11] calldata route,
        uint256[5][5] calldata swapParams,
        uint256 amount,
        address[5] calldata pools
    )
        external
        view
        returns (uint256);
}

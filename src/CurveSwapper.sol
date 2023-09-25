// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICurveBasePool } from "./interfaces/ICurveBasePool.sol";

contract CurveSwapper {
    // Optional Variable to be set to not sell dust.
    uint256 public minAmountToSell = 0;

    constructor() { }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to`.
     * This will check and handle all allownaces as well as not swapping
     * unless `_amountIn` is greater than the set `_minAmountToSell`
     *
     * If one of the tokens matches with the `base` token it will do only
     * one jump, otherwise will do two jumps.
     *
     * @param _curvePool The address of the target curve pool.
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _amountIn The amount of `_from` we will swap.
     * @param _minAmountOut The min of `_to` to get out.
     */
    function _swapFrom(
        address _curvePool,
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    )
        internal
    {
        if (_amountIn > minAmountToSell) {
            _checkAllowance(_curvePool, _from, _amountIn);

            (int128 fromIndex, int128 toIndex) = _getTokenIndexes(_curvePool, _from, _to);
            ICurveBasePool(_curvePool).exchange(fromIndex, toIndex, _amountIn, _minAmountOut);
        }
    }
    /**
     * \
     * @dev Internal function to get a quoted amount out of token sale.
     *
     * NOTE: This can be easily manipulated and should not be relied on
     * for anything other than estimations.
     *
     * @param _curvePool The address of the target curve pool.
     * @param _from The token to sell.
     * @param _to The token to buy.
     * @param _amountIn The amount of `_from` to sell.
     * @return . The expected amount of `_to` to buy.
     */

    function _getAmountOut(
        address _curvePool,
        int128 _from,
        int128 _to,
        uint256 _amountIn
    )
        internal
        view
        returns (uint256)
    {
        return ICurveBasePool(_curvePool).get_dy(_from, _to, _amountIn);
    }

    /**
     * \
     * @dev Internal function to get indexes used by curve.
     *
     * @param _from The token to sell.
     * @param _to The token to buy.
     * @return . The indexes of '_from' and '_to' respectively.
     */
    function _getTokenIndexes(address _curvePool, address _from, address _to) internal view returns (int128, int128) {
        int128 fromIndex = -1;
        int128 toIndex = -1;

        for (uint256 i = 0; i < 100; i++) {
            if (fromIndex == -1 && ICurveBasePool(_curvePool).coins(i) == _from) {
                fromIndex = int128(int256(i));
            }
            if (toIndex == -1 && ICurveBasePool(_curvePool).coins(i) == _to) {
                toIndex = int128(int256(i));
            }
            if (fromIndex != -1 && toIndex != -1) {
                break;
            }
        }
        return (fromIndex, toIndex);
    }

    /**
     * @dev Internal safe function to make sure the contract you want to
     * interact with has enough allowance to pull the desired tokens.
     *
     * @param _contract The address of the contract that will move the token.
     * @param _token The ERC-20 token that will be getting spent.
     * @param _amount The amount of `_token` to be spent.
     */
    function _checkAllowance(address _contract, address _token, uint256 _amount) internal {
        if (ERC20(_token).allowance(address(this), _contract) < _amount) {
            ERC20(_token).approve(_contract, 0);
            ERC20(_token).approve(_contract, _amount);
        }
    }
}

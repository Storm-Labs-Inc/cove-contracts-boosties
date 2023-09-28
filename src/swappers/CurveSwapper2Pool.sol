// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICurveTwoAssetPool } from "src/interfaces/deps/curve/ICurveTwoAssetPool.sol";

contract CurveSwapper2Pool {
    // Optional Variable to be set to not sell dust.
    uint256 public minAmountToSell = 0;
    uint256 private constant _MAX_POOL_INDEX = 100;

    /**
     * @dev Used to swap a specific amount of `_from` to `_to`.
     * This will check and handle all allownaces as well as not swapping
     * unless `_amountIn` is greater than the set `_minAmountToSell`
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

            (uint256 fromIndex, uint256 toIndex) = _getTokenIndexes(_curvePool, _from, _to);
            ICurveTwoAssetPool(_curvePool).exchange(fromIndex, toIndex, _amountIn, _minAmountOut);
        }
    }
    /**
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
        uint256 _from,
        uint256 _to,
        uint256 _amountIn
    )
        internal
        view
        returns (uint256)
    {
        return ICurveTwoAssetPool(_curvePool).get_dy(_from, _to, _amountIn);
    }

    /**
     * @dev Internal function to get indexes used by curve.
     *
     * @param _from The token to sell.
     * @param _to The token to buy.
     * @return . The indexes of '_from' and '_to' respectively.
     */
    function _getTokenIndexes(
        address _curvePool,
        address _from,
        address _to
    )
        internal
        view
        returns (uint256, uint256)
    {
        uint256 fromIndex = _MAX_POOL_INDEX;
        uint256 toIndex = _MAX_POOL_INDEX;

        for (uint256 i = 0; i < _MAX_POOL_INDEX; i++) {
            address coinAtIndex = ICurveTwoAssetPool(_curvePool).coins(i);
            if (fromIndex == _MAX_POOL_INDEX && coinAtIndex == _from) {
                fromIndex = i;
            } else if (toIndex == _MAX_POOL_INDEX && coinAtIndex == _to) {
                toIndex = i;
            }
            if (fromIndex != _MAX_POOL_INDEX && toIndex != _MAX_POOL_INDEX) {
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

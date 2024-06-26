// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

contract MockCurveRouterSwapper is CurveRouterSwapper {
    constructor(address _curveRouter) CurveRouterSwapper(_curveRouter) { }

    function approveTokenForSwap(address token) public {
        super._approveTokenForSwap(token);
    }

    function swap(
        CurveSwapParams calldata curveSwapParams,
        uint256 amount,
        uint256 expected,
        address receiver
    )
        public
        returns (uint256)
    {
        return super._swap(curveSwapParams, amount, expected, receiver);
    }

    function validateSwapParams(
        CurveSwapParams calldata curveSwapParams,
        address fromToken,
        address toToken
    )
        public
        view
    {
        super._validateSwapParams(curveSwapParams, fromToken, toToken);
    }
}

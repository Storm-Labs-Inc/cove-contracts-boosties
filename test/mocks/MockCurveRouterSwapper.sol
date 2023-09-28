// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BaseTest } from "../utils/BaseTest.t.sol";
import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

contract MockCurveRouterSwapper is CurveRouterSwapper {
    constructor(address _curveRouter) CurveRouterSwapper(_curveRouter) { }

    function approveTokenForSwap(address token) public {
        super._approveTokenForSwap(token);
    }

    function swap(
        address[11] memory route,
        uint256[5][5] memory swapParams,
        uint256 amount,
        uint256 expected,
        address[5] memory pools,
        address receiver
    )
        public
        returns (uint256)
    {
        return super._swap(route, swapParams, amount, expected, pools, receiver);
    }
}

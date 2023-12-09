// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { ICurveRouter } from "src/interfaces/deps/curve/ICurveRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockCurveRouter is ICurveRouter {
    function exchange(
        address[11] memory route,
        uint256[5][5] memory,
        uint256 amount,
        uint256
    )
        public
        payable
        returns (uint256)
    {
        address fromToken = route[0];
        address toToken;
        for (uint256 i = 0; i < route.length - 1; i++) {
            if (route[i] == address(0)) {
                break;
            }
            toToken = route[i];
        }
        uint256 outputAmount = IERC20(toToken).balanceOf(address(this));
        IERC20(fromToken).transferFrom(msg.sender, address(this), amount);
        IERC20(toToken).transfer(msg.sender, outputAmount);
        return outputAmount;
    }

    function exchange(
        address[11] memory route,
        uint256[5][5] memory swapParams,
        uint256 amount,
        uint256 expected,
        address[5] memory,
        address
    )
        public
        payable
        returns (uint256)
    {
        return exchange(route, swapParams, amount, expected);
    }

    function exchange(
        address[11] memory route,
        uint256[5][5] memory swapParams,
        uint256 amount,
        uint256 expected,
        address[5] memory
    )
        public
        payable
        returns (uint256)
    {
        return exchange(route, swapParams, amount, expected);
    }

    function get_dy(
        address[11] calldata,
        uint256[5][5] calldata,
        uint256,
        address[5] calldata
    )
        external
        view
        returns (uint256)
    {
        return uint256(1);
    }
}

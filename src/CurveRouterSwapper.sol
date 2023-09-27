// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { ICurveRouter } from "./interfaces/curve/ICurveRouter.sol";

/// @title Curve Router Library
/// @notice Contains helper methods for interacting with Curve Router.
/// @dev Curve router is deployed on these networks at 0xF0d4c12A5768D806021F80a262B4d39d26C58b8D
/// - Ethereum
/// - Optimism
/// - Gnosis
/// - Polygon
/// - Fantom
/// - Kava
/// - Arbitrum
/// - Avalanche
/// - Base at 0xd6681e74eEA20d196c15038C580f721EF2aB6320
/// https://github.com/curvefi/curve-router-ng/tree/master
contract CurveRouterSwapper {
    using SafeERC20 for IERC20;

    // solhint-disable-next-line var-name-mixedcase
    address private immutable _CURVE_ROUTER;

    constructor(address _curveRouter) {
        // Checks
        if (_curveRouter == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        _CURVE_ROUTER = _curveRouter;
    }

    function _approveTokenForSwap(address token) internal {
        IERC20(token).forceApprove(_CURVE_ROUTER, type(uint256).max);
    }

    function _swap(
        address[11] memory route,
        uint256[5][5] memory swapParams,
        uint256 amount,
        uint256 expected,
        address[5] memory pools,
        address receiver
    )
        internal
        returns (uint256)
    {
        return ICurveRouter(_CURVE_ROUTER).exchange(route, swapParams, amount, expected, pools, receiver);
    }
}

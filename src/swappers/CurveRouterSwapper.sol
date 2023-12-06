// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { ICurveRouter } from "src/interfaces/deps/curve/ICurveRouter.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
    // slither-disable-start naming-convention
    address private immutable _CURVE_ROUTER;
    // slither-disable-end naming-convention

    struct CurveSwapParams {
        address[11] route;
        uint256[5][5] swapParams;
        address[5] pools;
    }

    constructor(address curveRouter_) {
        // Checks
        if (curveRouter_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        _CURVE_ROUTER = curveRouter_;
    }

    function _approveTokenForSwap(address token) internal {
        IERC20(token).forceApprove(_CURVE_ROUTER, type(uint256).max);
    }

    function _swap(
        CurveSwapParams memory curveSwapParams,
        uint256 amount,
        uint256 expected,
        address receiver
    )
        internal
        returns (uint256)
    {
        return ICurveRouter(_CURVE_ROUTER).exchange(
            curveSwapParams.route, curveSwapParams.swapParams, amount, expected, curveSwapParams.pools, receiver
        );
    }

    function _validateSwapParams(
        CurveSwapParams memory curveSwapParams,
        address fromToken,
        address toToken
    )
        internal
        view
    {
        // Check if fromToken is in the route
        if (fromToken != curveSwapParams.route[0]) {
            revert Errors.InvalidFromToken(fromToken, curveSwapParams.route[0]);
        }
        // Check if toToken is in the route
        address toTokenInRoute;
        for (uint256 i = 0; i < curveSwapParams.route.length; i++) {
            if (curveSwapParams.route[i] == address(0)) {
                break;
            }
            toTokenInRoute = curveSwapParams.route[i];
        }
        if (toTokenInRoute != toToken) {
            revert Errors.InvalidToToken(toToken, toTokenInRoute);
        }
        // Note that this does not check whether supplied token exists in the pool since the
        // get_dy function only relies on the indexes on swaps instead of addresses.
        try ICurveRouter(_CURVE_ROUTER).get_dy(
            curveSwapParams.route,
            curveSwapParams.swapParams,
            10 ** IERC20Metadata(fromToken).decimals(),
            curveSwapParams.pools
        ) returns (uint256 expected) {
            if (expected == 0) {
                revert Errors.ExpectedAmountZero();
            }
        } catch {
            revert Errors.InvalidSwapParams();
        }
    }
}

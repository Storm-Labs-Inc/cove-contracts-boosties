// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { ICurveRouter } from "src/interfaces/deps/curve/ICurveRouter.sol";
import { ICurveBasePool } from "src/interfaces/deps/curve/ICurveBasePool.sol";

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
    address private constant _ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
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

    /* solhint-disable code-complexity */
    function _validateSwapParams(
        CurveSwapParams memory curveSwapParams,
        address fromToken,
        address toToken
    )
        internal
        view
    {
        // Check fromToken address matches the current route token
        if (curveSwapParams.route[0] != fromToken) {
            revert Errors.InvalidFromToken(fromToken, curveSwapParams.route[0]);
        }
        for (uint256 i = 0; i < curveSwapParams.swapParams.length; i++) {
            // Break if this is the last swap
            address curvePool = curveSwapParams.route[i * 2 + 1];
            if (curvePool == address(0)) {
                break;
            }
            // Read the next token address
            address nextToken = curveSwapParams.route[(i + 1) * 2];
            // If this is a regular swap, check if the pool indexes match
            if (curveSwapParams.swapParams[i][2] == 1) {
                // @dev Skip ETH address check since coins() returns WETH on mainnet ETH. We could add WETH as a
                // constant here but then would require us to create different CurveRouterSwapper per chain.
                // Even if this check passes in case where we supply ETH address when the actual coin at index is not
                // ETH or WETH, this will get reverted at router level. Therefore its not critical if we miss this
                // check, just prevents us from having to update to the correct swap params in the future.
                if (fromToken != _ETH_ADDRESS) {
                    if (ICurveBasePool(curvePool).coins(curveSwapParams.swapParams[i][0]) != fromToken) {
                        revert Errors.InvalidCoinIndex();
                    }
                }
                if (nextToken != _ETH_ADDRESS) {
                    if (ICurveBasePool(curvePool).coins(curveSwapParams.swapParams[i][1]) != nextToken) {
                        revert Errors.InvalidCoinIndex();
                    }
                }
            }
            // Update fromToken to the next token
            fromToken = nextToken;
        }

        if (fromToken != toToken) {
            revert Errors.InvalidToToken(toToken, fromToken);
        }
    }
    /* solhint-enable code-complexity */
}

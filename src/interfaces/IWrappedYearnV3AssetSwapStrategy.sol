// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { StrategyAssetSwap } from "src/strategies/StrategyAssetSwap.sol";

interface IWrappedYearnV3AssetSwapStrategy is IWrappedYearnV3Strategy {
    // Need to override the `asset` function since
    // its defined in both interfaces inherited.
    function setOracle(address token, address oracle) external;
    function setSwapParameters(
        CurveRouterSwapper.CurveSwapParams memory deploySwapParams,
        CurveRouterSwapper.CurveSwapParams memory freeSwapParams,
        StrategyAssetSwap.SwapTolerance memory _swapTolerance
    )
        external;
}

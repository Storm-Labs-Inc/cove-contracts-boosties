// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IBaseTokenizedStrategy } from "src/interfaces/deps/yearn/tokenized-strategy/IBaseTokenizedStrategy.sol";
import { ITokenizedStrategy, IERC4626 } from "src/interfaces/deps/yearn/tokenized-strategy/ITokenizedStrategy.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

interface IWrappedYearnV3Strategy is IBaseTokenizedStrategy, ITokenizedStrategy {
    // Need to override the `asset` function since
    // its defined in both interfaces inherited.
    function asset() external view override(IBaseTokenizedStrategy, IERC4626) returns (address);
    function vault() external view returns (address);
    function yearnStakingDelegate() external view returns (address);
    function setHarvestSwapPrams(CurveRouterSwapper.CurveSwapParams memory _curveSwapParams) external;
}

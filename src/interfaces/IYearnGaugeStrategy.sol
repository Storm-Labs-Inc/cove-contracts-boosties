// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { IStrategy } from "@tokenized-strategy/interfaces/IStrategy.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

interface IYearnGaugeStrategy is IStrategy {
    // Need to override the `asset` function since
    // its defined in both interfaces inherited.
    function vault() external view returns (address);
    function yearnStakingDelegate() external view returns (address);
    function setHarvestSwapParams(CurveRouterSwapper.CurveSwapParams memory _curveSwapParams) external;
    function setMaxTotalAssets(uint256 _maxTotalAssets) external;
    //// events ////

    event UserBalanceUpdate(address indexed sender, address indexed gauge, uint256 userGaugeBalance);
}

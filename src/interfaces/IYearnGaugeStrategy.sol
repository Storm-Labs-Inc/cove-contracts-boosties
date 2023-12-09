// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { IStrategy } from "@tokenized-strategy/interfaces/IStrategy.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

interface IYearnGaugeStrategy is IStrategy {
    function vault() external view returns (address);
    function yearnStakingDelegate() external view returns (address);
    function setHarvestSwapParams(CurveRouterSwapper.CurveSwapParams memory curveSwapParams_) external;
    function setMaxTotalAssets(uint256 maxTotalAssets_) external;
    function setFlashLoanProvider(address flashloanProvider_) external;
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { IStrategy } from "tokenized-strategy/interfaces/IStrategy.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

interface IYearnGaugeStrategy is IStrategy {
    function vault() external view returns (address);
    function vaultAsset() external view returns (address);
    function yearnStakingDelegate() external view returns (address);
    function dYfiRedeemer() external view returns (address);
    function setHarvestSwapParams(CurveRouterSwapper.CurveSwapParams calldata curveSwapParams_) external;
    function setDYfiRedeemer(address newDYfiRedeemer) external;
    function maxTotalAssets() external view returns (uint256);
    function depositedInYSD(address asset) external view returns (uint256);
}

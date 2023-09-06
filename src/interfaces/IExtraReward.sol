// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBaseGauge } from "./IBaseGauge.sol";

interface IExtraReward is IBaseGauge {
    function initialize(address _gauge, address _reward, address _owner) external;

    function rewardCheckpoint(address _account) external returns (bool);

    function getReward() external returns (bool);
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IBaseGauge } from "./IBaseGauge.sol";
import { IERC4626Upgradeable } from "@openzeppelin-upgradeable-5.0/contracts/interfaces/IERC4626Upgradeable.sol";

interface IGauge is IBaseGauge, IERC4626Upgradeable {
    function initialize(address _stakingToken, address _owner) external;
    function boostedBalanceOf(address _account) external view returns (uint256);
    function getReward(address _account) external returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { ISwapAndLockEvents } from "src/interfaces/ISwapAndLockEvents.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

interface ISwapAndLock is ISwapAndLockEvents, IAccessControl {
    function MANAGER_ROLE() external view returns (bytes32);
    function swapDYfiToVeYfi(uint256 minYfiAmount) external;
    function setRouterParams(CurveRouterSwapper.CurveSwapParams calldata routerParam) external;
}

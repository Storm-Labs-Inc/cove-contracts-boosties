// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { ISwapAndLockEvents } from "src/interfaces/ISwapAndLockEvents.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";

interface ISwapAndLock is ISwapAndLockEvents, IAccessControl {
    function lockYfi() external returns (IVotingYFI.LockedBalance memory);
    function setDYfiRedeemer(address dYfiRedeemer_) external;
    function dYfiRedeemer() external view returns (address);
}

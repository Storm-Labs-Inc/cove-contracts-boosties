// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";

interface ISwapAndLock is IAccessControl {
    function lockYfi() external returns (IVotingYFI.LockedBalance memory);
    function setDYfiRedeemer(address newDYfiRedeemer) external;
    function dYfiRedeemer() external view returns (address);
}

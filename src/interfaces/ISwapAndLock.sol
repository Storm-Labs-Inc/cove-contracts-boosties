// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IAccessControlEnumerable } from "@openzeppelin/contracts/access/IAccessControlEnumerable.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";

interface ISwapAndLock is IAccessControlEnumerable {
    function lockYfi() external returns (IVotingYFI.LockedBalance memory);
    function setDYfiRedeemer(address newDYfiRedeemer) external;
    function dYfiRedeemer() external view returns (address);
}

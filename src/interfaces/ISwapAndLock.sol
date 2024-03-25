// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IAccessControlEnumerable } from "@openzeppelin/contracts/access/IAccessControlEnumerable.sol";

interface ISwapAndLock is IAccessControlEnumerable {
    function convertToCoveYfi() external returns (uint256);
    function setDYfiRedeemer(address newDYfiRedeemer) external;
    function dYfiRedeemer() external view returns (address);
}

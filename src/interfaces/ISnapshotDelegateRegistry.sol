// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ISnapshotDelegateRegistry {
    function setDelegate(bytes32 id, address delegate) external;
    function delegation(address account, bytes32 id) external view returns (address);
}

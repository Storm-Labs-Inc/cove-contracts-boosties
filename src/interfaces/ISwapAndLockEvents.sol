// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ISwapAndLockEvents {
    event SwapAndLocked(uint256 dYfiAmount, uint256 yfiAmount, uint256 totalLockedYfiBalance);
}

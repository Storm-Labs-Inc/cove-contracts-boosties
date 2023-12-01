// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IDYfiRewardPool {
    function claim() external returns (uint256);
}

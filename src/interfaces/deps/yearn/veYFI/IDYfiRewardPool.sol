// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IDYfiRewardPool {
    function burn(uint256 _amount) external returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBaseGauge {
    function queueNewRewards(uint256 _amount) external returns (bool);
    function earned(address _account) external view returns (uint256);
}

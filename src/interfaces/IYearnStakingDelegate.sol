// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IYearnStakingDelegate {
    function depositToGauge(address vault, uint256 amount) external;
    function withdrawFromGauge(address vault, uint256 amount) external;
    // mapping(address user => mapping(address vault => UserInfo)) public userInfo;
    function userInfo(address user, address vault) external view returns (uint256, uint256);
}

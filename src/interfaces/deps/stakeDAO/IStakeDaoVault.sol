//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IStakeDaoVault {
    function withdraw(uint256 shares) external;
    function token() external view returns (address);
}

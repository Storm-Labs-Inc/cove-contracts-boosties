// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IRedemption {
    function redeem(uint256 dYfiAmount) external payable returns (uint256);
    function eth_required(uint256 dYfiAmount) external view returns (uint256);
}

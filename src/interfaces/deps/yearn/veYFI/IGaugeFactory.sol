// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IGaugeFactory {
    function createGauge(address, address) external returns (address);
}

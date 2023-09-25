// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";

import { BaseTokenizedStrategy } from "src/yearn/tokenized-strategy/BaseTokenizedStrategy.sol";

contract MockStrategy is BaseTokenizedStrategy {
    bool public tendStatus;

    constructor(address _asset) BaseTokenizedStrategy(_asset, "Mock Basic Strategy") { }

    function _deployFunds(uint256) internal override { }

    function _freeFunds(uint256) internal override { }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        _totalAssets = ERC20(asset).balanceOf(address(this));
    }

    function tendTrigger() external view override returns (bool) {
        return tendStatus;
    }

    function setTendStatus(bool _status) external {
        tendStatus = _status;
    }
}

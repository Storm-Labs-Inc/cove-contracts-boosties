// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { BaseStrategy } from "tokenized-strategy/BaseStrategy.sol";

contract MockStrategy is BaseStrategy {
    bool public tendStatus;

    constructor(address _asset) BaseStrategy(_asset, "Mock Basic Strategy") { }

    // solhint-disable no-empty-blocks
    function _deployFunds(uint256) internal override { }

    function _freeFunds(uint256) internal override { }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        _totalAssets = ERC20(asset).balanceOf(address(this));
    }

    function tendTrigger() external view virtual override returns (bool, bytes memory) {
        return (tendStatus, new bytes(0));
    }

    function setTendStatus(bool _status) external {
        tendStatus = _status;
    }
}

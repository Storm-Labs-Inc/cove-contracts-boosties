// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { BaseTokenizedStrategy } from "tokenized-strategy/BaseTokenizedStrategy.sol";
import { SolidlySwapper } from "tokenized-strategy-periphery/swappers/SolidlySwapper.sol";

abstract contract WrappedYearnV3Strategy is BaseTokenizedStrategy {
    function _deployFunds(uint256 _amount) internal override {
        // deposit _amount into vault
    }
}

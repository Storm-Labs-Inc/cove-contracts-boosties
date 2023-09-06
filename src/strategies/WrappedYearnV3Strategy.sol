// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { BaseTokenizedStrategy } from "tokenized-strategy/BaseTokenizedStrategy.sol";
import { SolidlySwapper } from "tokenized-strategy-periphery/swappers/SolidlySwapper.sol";
import { IVault } from "src/interfaces/IVault.sol";

// TODO: remove abstract once implemented
contract WrappedYearnV3Strategy is BaseTokenizedStrategy {
    address public vaultAddress;
    address public yearnStakingDelegateAddress;

    constructor(address _asset) BaseTokenizedStrategy(_asset, "Wrapped YearnV3 Strategy") { }

    function setYieldSource(address v3VaultAddress) external {
        vaultAddress = v3VaultAddress;
    }

    function setStakingDelegate(address delegateAddress) external {
        yearnStakingDelegateAddress = delegateAddress;
    }

    function _deployFunds(uint256 _amount) internal override {
        // deposit _amount into vault
        IVault(vaultAddress).deposit(_amount, yearnStakingDelegateAddress);
    }

    function _freeFunds(uint256 _amount) internal override {
        // withdraw _amount from vault
        IVault(vaultAddress).withdraw(_amount, msg.sender, yearnStakingDelegateAddress, 0, new address[](0));
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // harvest and report
    }
}

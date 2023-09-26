// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { BaseTokenizedStrategy } from "../yearn/tokenized-strategy/BaseTokenizedStrategy.sol";
import { IVault } from "src/interfaces/yearn/yearn-vaults-v3/IVault.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract WrappedYearnV3Strategy is BaseTokenizedStrategy {
    address public vaultAddress;
    address public yearnStakingDelegateAddress;

    using SafeERC20 for ERC20;

    constructor(address _asset) BaseTokenizedStrategy(_asset, "Wrapped YearnV3 Strategy") { }

    function setYieldSource(address v3VaultAddress) external virtual onlyManagement {
        vaultAddress = v3VaultAddress;
        ERC20(asset).approve(vaultAddress, type(uint256).max);
    }

    function setStakingDelegate(address delegateAddress) external onlyManagement {
        yearnStakingDelegateAddress = delegateAddress;
        ERC20(vaultAddress).approve(yearnStakingDelegateAddress, type(uint256).max);
    }

    function _deployFunds(uint256 _amount) internal virtual override {
        // deposit _amount into vault
        uint256 shares = IVault(vaultAddress).deposit(_amount, address(this));
        IYearnStakingDelegate(yearnStakingDelegateAddress).depositToGauge(vaultAddress, shares);
    }

    function _freeFunds(uint256 _amount) internal override {
        // withdraw _amount from gauge through yearn staking delegate
        IYearnStakingDelegate(yearnStakingDelegateAddress).withdrawFromGauge(vaultAddress, _amount);
        // withdraw _amount from vault, with msg.sender as recipient
        IVault(vaultAddress).withdraw(_amount, msg.sender, address(this), 0, new address[](0));
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // harvest and report
    }
}

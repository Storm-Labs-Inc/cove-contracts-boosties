// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { BaseTokenizedStrategy } from "src/deps/yearn/tokenized-strategy/BaseTokenizedStrategy.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { Errors } from "../libraries/Errors.sol";
import { SafeERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract WrappedYearnV3Strategy is BaseTokenizedStrategy {
    address public vaultAddress;
    address public yearnStakingDelegateAddress;

    using SafeERC20 for ERC20;

    constructor(address _asset) BaseTokenizedStrategy(_asset, "Wrapped YearnV3 Strategy") { }

    function setYieldSource(address v3VaultAddress) external virtual onlyManagement {
        // checks
        address strategyAsset = asset;
        if (strategyAsset != IVault(v3VaultAddress).asset()) {
            revert Errors.VaultAssetDiffers();
        }
        // effects
        vaultAddress = v3VaultAddress;
        // interactions
        ERC20(strategyAsset).approve(v3VaultAddress, type(uint256).max);
    }

    function setStakingDelegate(address delegateAddress) external onlyManagement {
        // checks
        if (delegateAddress == address(0)) {
            revert Errors.ZeroAddress();
        }
        // effects
        yearnStakingDelegateAddress = delegateAddress;
        // interactions
        ERC20(vaultAddress).approve(delegateAddress, type(uint256).max);
    }

    function _deployFunds(uint256 _amount) internal virtual override {
        // deposit _amount into vault
        address _vault = vaultAddress;
        uint256 shares = IVault(_vault).deposit(_amount, address(this));
        IYearnStakingDelegate(yearnStakingDelegateAddress).depositToGauge(_vault, shares);
    }

    function _freeFunds(uint256 _amount) internal override {
        // withdraw _amount from gauge through yearn staking delegate
        address _vault = vaultAddress;
        IYearnStakingDelegate(yearnStakingDelegateAddress).withdrawFromGauge(_vault, _amount);
        // withdraw _amount from vault, with msg.sender as recipient
        IVault(_vault).withdraw(_amount, msg.sender, address(this));
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // harvest and report
    }
}

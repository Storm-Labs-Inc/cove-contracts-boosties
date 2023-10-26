// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { IVault } from "yearn-vaults-v3/interfaces/IVault.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Errors } from "../libraries/Errors.sol";

abstract contract WrappedYearnV3 is CurveRouterSwapper {
    // Immutable storage variables
    address internal immutable _VAULT;
    address internal immutable _YEARN_STAKING_DELEGATE;
    address internal immutable _DYFI;

    // Storage variables
    CurveSwapParams internal _harvestSwapParams;
    uint256 public totalUnderlyingVaultShares;

    constructor(address _vault, address _yearnStakingDelegate, address _dYfi) {
        // Check for zero addresses
        if (_vault == address(0) || _yearnStakingDelegate == address(0) || _dYfi == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // Set storage variable values
        _VAULT = _vault;
        _YEARN_STAKING_DELEGATE = _yearnStakingDelegate;
        _DYFI = _dYfi;
    }

    function _setHarvestSwapParams(address asset, CurveSwapParams memory curveSwapParams) internal virtual {
        // Checks (includes external view calls)
        _validateSwapParams(curveSwapParams, _DYFI, asset);

        // Effects
        _harvestSwapParams = curveSwapParams;
    }

    function _depositVaultAssetToYSD(uint256 amount) internal virtual returns (uint256 newShares) {
        // Deposit _amount into vault
        newShares = IVault(_VAULT).deposit(amount, address(this));
        // Update totalUnderlyingVaultShares
        totalUnderlyingVaultShares += newShares;
        // Deposit _shares into gauge via YSD
        IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).depositToGauge(_VAULT, newShares);
    }

    function _redeemVaultSharesFromYSD(uint256 shares) internal virtual returns (uint256 amount) {
        // Update totalUnderlyingVaultShares
        totalUnderlyingVaultShares -= shares;
        // Withdraw _shares from gauge via YSD
        IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).withdrawFromGauge(_VAULT, shares);
        // Withdraw _amount from vault
        amount = IVault(_VAULT).redeem(shares, address(this), address(this));
    }

    function vault() external view returns (address) {
        return _VAULT;
    }

    function yearnStakingDelegate() external view returns (address) {
        return _YEARN_STAKING_DELEGATE;
    }

    function dYfi() external view returns (address) {
        return _DYFI;
    }
}

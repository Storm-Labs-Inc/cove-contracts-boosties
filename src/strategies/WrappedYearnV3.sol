// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Errors } from "../libraries/Errors.sol";

abstract contract WrappedYearnV3 is CurveRouterSwapper {
    // Immutable storage variables
    address public immutable vault;
    address public immutable yearnStakingDelegate;
    address public immutable dYfi;

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
        vault = _vault;
        yearnStakingDelegate = _yearnStakingDelegate;
        dYfi = _dYfi;
    }

    function _setHarvestSwapParams(address asset, CurveSwapParams memory curveSwapParams) internal virtual {
        // Checks (includes external view calls)
        _validateSwapParams(curveSwapParams, dYfi, asset);

        // Effects
        _harvestSwapParams = curveSwapParams;
    }

    function _depositVaultAssetToYSD(uint256 amount) internal virtual returns (uint256 newShares) {
        // Cache vault address
        address _vault = vault;
        // Deposit _amount into vault
        newShares = IVault(_vault).deposit(amount, address(this));
        // Update totalUnderlyingVaultShares
        totalUnderlyingVaultShares += newShares;
        // Deposit _shares into gauge via YSD
        IYearnStakingDelegate(yearnStakingDelegate).depositToGauge(_vault, newShares);
    }

    function _redeemVaultSharesFromYSD(uint256 shares) internal virtual returns (uint256 amount) {
        // Cache vault address
        address _vault = vault;
        // Update totalUnderlyingVaultShares
        totalUnderlyingVaultShares -= shares;
        // Withdraw _shares from gauge via YSD
        IYearnStakingDelegate(yearnStakingDelegate).withdrawFromGauge(_vault, shares);
        // Withdraw _amount from vault
        amount = IVault(_vault).redeem(shares, address(this), address(this));
    }
}

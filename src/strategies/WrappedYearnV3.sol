// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

abstract contract WrappedYearnV3 {
    // Libraries
    using SafeERC20 for IERC20;

    // Immutable storage variables
    // slither-disable-start naming-convention
    address private immutable _YEARN_STAKING_DELEGATE;
    address private immutable _DYFI;
    address internal immutable _VAULT_ASSET;
    address internal immutable _VAULT;
    // slither-disable-end naming-convention

    constructor(address asset_, address yearnStakingDelegate_, address dYfi_) {
        address vault_ = IERC4626(asset_).asset();
        address vaultAsset_ = IERC4626(vault_).asset();
        // Check for zero addresses
        if (
            yearnStakingDelegate_ == address(0) || dYfi_ == address(0) || vault_ == address(0)
                || vaultAsset_ == address(0)
        ) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // Set storage variable values
        _YEARN_STAKING_DELEGATE = yearnStakingDelegate_;
        _DYFI = dYfi_;
        _VAULT = vault_;
        _VAULT_ASSET = vaultAsset_;

        // Interactions
        IERC20(asset_).forceApprove(_YEARN_STAKING_DELEGATE, type(uint256).max);
    }

    function _depositToYSD(address asset, uint256 amount) internal virtual {
        IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).deposit(asset, amount);
    }

    function _withdrawFromYSD(address asset, uint256 amount) internal virtual {
        // Withdraw gauge from YSD which transfers to msg.sender
        IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).withdraw(asset, amount);
    }

    function yearnStakingDelegate() public view returns (address) {
        return _YEARN_STAKING_DELEGATE;
    }

    function dYfi() public view returns (address) {
        return _DYFI;
    }

    function vault() public view returns (address) {
        return _VAULT;
    }

    function vaultAsset() public view returns (address) {
        return _VAULT_ASSET;
    }
}

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

abstract contract YearnGaugeStrategyBase {
    // Libraries
    using SafeERC20 for IERC20;

    // Immutable storage variables
    /* solhint-disable immutable-vars-naming */
    address public immutable yearnStakingDelegate;
    address public immutable dYfi;
    address public immutable vaultAsset;
    address public immutable vault;
    /* solhint-enable immutable-vars-naming */

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
        yearnStakingDelegate = yearnStakingDelegate_;
        dYfi = dYfi_;
        vault = vault_;
        vaultAsset = vaultAsset_;

        // Interactions
        IERC20(asset_).forceApprove(yearnStakingDelegate_, type(uint256).max);
        IERC20(vaultAsset_).forceApprove(vault, type(uint256).max);
        IERC20(vault_).forceApprove(asset_, type(uint256).max);
    }

    function _depositToYSD(address asset, uint256 amount) internal virtual {
        IYearnStakingDelegate(yearnStakingDelegate).deposit(asset, amount);
    }

    function _withdrawFromYSD(address asset, uint256 amount) internal virtual {
        // Withdraw gauge from YSD which transfers to msg.sender
        IYearnStakingDelegate(yearnStakingDelegate).withdraw(asset, amount);
    }
}

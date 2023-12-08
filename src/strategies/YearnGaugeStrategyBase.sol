// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IYearnVaultV2 } from "src/interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";

/// @title YearnGaugeStrategyBase
/// @notice Abstract base contract for Yearn gauge strategies, handling deposits and withdrawals to the
/// YearnStakingDelegate.
abstract contract YearnGaugeStrategyBase {
    // Libraries
    using SafeERC20 for IERC20;

    // Immutable storage variables
    // solhint-disable immutable-vars-naming
    /// @notice Address of the YearnStakingDelegate contract
    address public immutable yearnStakingDelegate;
    /// @notice Address of the dYFI token
    address public immutable dYfi;
    /// @notice Address of the vault's underlying asset
    address public immutable vaultAsset;
    /// @notice Address of the Yearn vault
    address public immutable vault;
    // solhint-enable immutable-vars-naming

    /**
     * @dev Sets the initial configuration of the strategy and approves the maximum amount of tokens to the
     * YearnStakingDelegate.
     * @param asset_ The address of the asset (gauge token).
     * @param yearnStakingDelegate_ The address of the Yearn Staking Delegate.
     * @param dYfi_ The address of the dYFI token.
     */
    constructor(address asset_, address yearnStakingDelegate_, address dYfi_) {
        address vault_ = IERC4626(asset_).asset();
        // slither-disable-next-line uninitialized-local
        address vaultAsset_;
        try IERC4626(vault_).asset() returns (address returnedVaultAsset) {
            vaultAsset_ = returnedVaultAsset;
        } catch {
            vaultAsset_ = IYearnVaultV2(vault_).token();
        }
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

    /**
     * @dev Internal function to deposit assets into the YearnStakingDelegate.
     * @param asset The address of the asset to deposit.
     * @param amount The amount of the asset to deposit.
     */
    function _depositToYSD(address asset, uint256 amount) internal virtual {
        IYearnStakingDelegate(yearnStakingDelegate).deposit(asset, amount);
    }

    /**
     * @dev Internal function to withdraw assets from the YearnStakingDelegate.
     * @param asset The address of the asset to withdraw.
     * @param amount The amount of the asset to withdraw.
     */
    function _withdrawFromYSD(address asset, uint256 amount) internal virtual {
        // Withdraw gauge from YSD which transfers to msg.sender
        IYearnStakingDelegate(yearnStakingDelegate).withdraw(asset, amount);
    }
}

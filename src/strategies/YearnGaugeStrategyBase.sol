// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IYearnVaultV2 } from "src/interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";

/**
 * @title YearnGaugeStrategyBase
 * @notice Abstract base contract for Yearn gauge strategies, handling deposits and withdrawals to the
 * YearnStakingDelegate.
 */
abstract contract YearnGaugeStrategyBase {
    // Libraries
    using SafeERC20 for IERC20;

    // Constant storage variables
    // solhint-disable const-name-snakecase
    /// @notice Address of the dYFI token
    address internal constant _DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    /// @notice Address of the YFI token
    address internal constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    // solhint-enable const-name-snakecase

    // Immutable storage variables
    // solhint-disable immutable-vars-naming
    // slither-disable-start naming-convention
    /// @notice Address of the YearnStakingDelegate contract
    address internal immutable _YEARN_STAKING_DELEGATE;
    /// @notice Address of the vault's underlying asset
    address internal immutable _VAULT_ASSET;
    /// @notice Address of the Yearn vault
    address internal immutable _VAULT;
    // solhint-enable immutable-vars-naming
    // slither-disable-end naming-convention

    /**
     * @dev Sets the initial configuration of the strategy and approves the maximum amount of tokens to the
     * YearnStakingDelegate.
     * @param asset_ The address of the asset (gauge token).
     * @param yearnStakingDelegate_ The address of the Yearn Staking Delegate.
     */
    constructor(address asset_, address yearnStakingDelegate_) {
        address vault_ = IERC4626(asset_).asset();
        address vaultAsset_ = address(0);
        try IERC4626(vault_).asset() returns (address returnedVaultAsset) {
            vaultAsset_ = returnedVaultAsset;
        } catch {
            vaultAsset_ = IYearnVaultV2(vault_).token();
        }
        // Check for zero addresses
        if (yearnStakingDelegate_ == address(0) || vault_ == address(0) || vaultAsset_ == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // Set storage variable values
        _YEARN_STAKING_DELEGATE = yearnStakingDelegate_;
        _VAULT = vault_;
        _VAULT_ASSET = vaultAsset_;

        // Interactions
        IERC20(asset_).forceApprove(yearnStakingDelegate_, type(uint256).max);
        IERC20(vaultAsset_).forceApprove(vault_, type(uint256).max);
        IERC20(vault_).forceApprove(asset_, type(uint256).max);
    }

    /**
     * @notice Get the address of the YearnStakingDelegate.
     * @return The address of the YearnStakingDelegate.
     */
    function yearnStakingDelegate() external view returns (address) {
        return _YEARN_STAKING_DELEGATE;
    }

    /**
     * @notice Get the address of the vault's underlying asset. This is the asset that is deposited into the
     * vault which then is deposited into the gauge.
     * @return The address of the vault's underlying asset.
     */
    function vaultAsset() external view returns (address) {
        return _VAULT_ASSET;
    }

    /**
     * @notice Get the address of the vault. This is the Yearn vault that the gauge is for.
     * @return The address of the vault.
     */
    function vault() external view returns (address) {
        return _VAULT;
    }

    /**
     * @dev Internal function to deposit assets into the YearnStakingDelegate.
     * @param asset The address of the asset to deposit.
     * @param amount The amount of the asset to deposit.
     */
    function _depositToYSD(address asset, uint256 amount) internal virtual {
        IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).deposit(asset, amount);
    }

    /**
     * @dev Internal function to withdraw assets from the YearnStakingDelegate.
     * @param asset The address of the asset to withdraw.
     * @param amount The amount of the asset to withdraw.
     */
    function _withdrawFromYSD(address asset, uint256 amount) internal virtual {
        // Withdraw gauge from YSD which transfers to msg.sender
        IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).withdraw(asset, amount);
    }

    /**
     * @notice Return the amount of the asset deposited by this contract in the YearnStakingDelegate.
     * @param asset The address of the asset to check.
     * @return The amount of the asset deposited in the YearnStakingDelegate.
     */
    function depositedInYSD(address asset) public view returns (uint256) {
        return IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).balanceOf(address(this), asset);
    }
}

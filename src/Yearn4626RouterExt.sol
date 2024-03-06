// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Yearn4626Router } from "Yearn-ERC4626-Router/Yearn4626Router.sol";
import { IYearnVaultV2 } from "./interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";
import { IPermit2 } from "permit2/interfaces/IPermit2.sol";
import { ISignatureTransfer } from "permit2/interfaces/ISignatureTransfer.sol";
import { IWETH9 } from "Yearn-ERC4626-Router/external/PeripheryPayments.sol";
import { IYearn4626RouterExt } from "./interfaces/IYearn4626RouterExt.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Yearn4626Router Extension
 * @notice Extends the Yearn4626Router with additional functionality for depositing to Yearn Vault V2 and pulling tokens
 * with Permit2.
 * @dev This contract introduces two key functions: depositing to Yearn Vault V2 and pulling tokens with a signature via
 * Permit2.
 * The contract holds an immutable reference to a Permit2 contract to facilitate token transfers with permits.
 */
contract Yearn4626RouterExt is IYearn4626RouterExt, Yearn4626Router {
    // slither-disable-next-line naming-convention
    IPermit2 private immutable _PERMIT2;

    error InsufficientShares();
    error InvalidTo();
    error VaultMismatch();

    struct Vault {
        address vault;
        bool isYearnVaultV2;
    }

    /**
     * @notice Constructs the Yearn4626RouterExt contract.
     * @dev Sets up the router with the name for the vault, WETH address, and Permit2 contract address.
     * @param name_ The name of the vault.
     * @param weth_ The address of the WETH contract.
     * @param permit2_ The address of the Permit2 contract.
     */
    // slither-disable-next-line locked-ether
    constructor(string memory name_, address weth_, address permit2_) payable Yearn4626Router(name_, IWETH9(weth_)) {
        _PERMIT2 = IPermit2(permit2_);
    }

    /**
     * @notice Deposits the specified `amount` of tokens into the Yearn Vault V2.
     * @dev Calls the `deposit` function of the Yearn Vault V2 contract and checks if the returned shares are above the
     * `minSharesOut`.
     * Reverts with `InsufficientShares` if the condition is not met.
     * @param vault The Yearn Vault V2 contract instance.
     * @param amount The amount of tokens to deposit.
     * @param to The address to which the shares will be minted.
     * @param minSharesOut The minimum number of shares expected to be received.
     * @return sharesOut The actual number of shares minted to the `to` address.
     */
    function depositToVaultV2(
        IYearnVaultV2 vault,
        uint256 amount,
        address to,
        uint256 minSharesOut
    )
        public
        payable
        returns (uint256 sharesOut)
    {
        if ((sharesOut = vault.deposit(amount, to)) < minSharesOut) revert InsufficientShares();
    }

    /**
     * @notice Pulls tokens to the contract using a signature via Permit2.
     * @dev Verifies that the `to` address in `transferDetails` is the contract itself and then calls
     * `permitTransferFrom` on the Permit2 contract.
     * Reverts with `InvalidTo` if the `to` address is not the contract itself.
     * @param permit The PermitTransferFrom struct containing the permit details.
     * @param transferDetails The details of the transfer, including the `to` address.
     * @param signature The signature to authorize the token transfer.
     */
    function pullTokensWithPermit2(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    )
        public
        payable
    {
        if (transferDetails.to != address(this)) revert InvalidTo();
        IPermit2(_PERMIT2).permitTransferFrom(permit, transferDetails, msg.sender, signature);
    }

    /**
     * @notice Calculate the amount of shares to be received from a series of deposits to ERC4626 vaults or Yearn Vault
     * V2.
     * @param vaults The array of vaults to deposit into.
     * @param assetIn The amount of assets to deposit into the first vault.
     */
    // slither-disable-start calls-loop
    function previewDeposits(
        Vault[] calldata vaults,
        uint256 assetIn
    )
        external
        view
        returns (address assetInAddress, uint256[] memory sharesOut)
    {
        sharesOut = new uint256[](vaults.length);
        for (uint256 i; i < vaults.length;) {
            address vaultAsset;
            if (vaults[i].isYearnVaultV2) {
                vaultAsset = IYearnVaultV2(vaults[i].vault).token();
                sharesOut[i] =
                    Math.mulDiv(assetIn, 1e18, IYearnVaultV2(vaults[i].vault).pricePerShare(), Math.Rounding.Down) - 1;
            } else {
                vaultAsset = IERC4626(vaults[i].vault).asset();
                sharesOut[i] = IERC4626(vaults[i].vault).previewDeposit(assetIn);
            }
            if (i > 0) {
                if (vaultAsset != vaults[i - 1].vault) {
                    revert VaultMismatch();
                }
            } else {
                assetInAddress = vaultAsset;
            }
            assetIn = sharesOut[i];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Calculate the amount of assets required to mint a given amount of shares from a series of deposits to
     * ERC4626 vaults or Yearn Vault V2.
     * @param vaults The array of vaults to deposit into.
     * @param shareOut The amount of shares to mint from the last vault.
     */
    function previewMints(
        Vault[] calldata vaults,
        uint256 shareOut
    )
        external
        view
        returns (address assetInAddress, uint256[] memory assetsIn)
    {
        assetsIn = new uint256[](vaults.length);
        for (uint256 i; i < vaults.length;) {
            address vaultAsset;
            if (vaults[i].isYearnVaultV2) {
                vaultAsset = IYearnVaultV2(vaults[i].vault).token();
                assetsIn[i] =
                    Math.mulDiv(shareOut, IYearnVaultV2(vaults[i].vault).pricePerShare(), 1e18, Math.Rounding.Up) + 1;
            } else {
                vaultAsset = IERC4626(vaults[i].vault).asset();
                assetsIn[i] = IERC4626(vaults[i].vault).previewMint(shareOut);
            }
            if (i > 0) {
                if (vaultAsset != vaults[i - 1].vault) {
                    revert VaultMismatch();
                }
            } else {
                assetInAddress = vaultAsset;
            }
            shareOut = assetsIn[i];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Calculate the amount of shares required to withdraw a given amount of assets from a series of withdraws
     * from
     * ERC4626 vaults or Yearn Vault V2.
     * @param vaults The array of vaults to withdraw from.
     * @param assetOut The amount of assets to withdraw from the last vault.
     */
    function previewWithdraws(
        Vault[] calldata vaults,
        uint256 assetOut
    )
        external
        view
        returns (address assetOutAddress, uint256[] memory sharesIn)
    {
        sharesIn = new uint256[](vaults.length);
        for (uint256 i; i < vaults.length;) {
            address vaultAsset;
            if (vaults[i].isYearnVaultV2) {
                vaultAsset = IYearnVaultV2(vaults[i].vault).token();
                sharesIn[i] =
                    Math.mulDiv(assetOut, 1e18, IYearnVaultV2(vaults[i].vault).pricePerShare(), Math.Rounding.Down) - 1;
            } else {
                vaultAsset = IERC4626(vaults[i].vault).asset();
                sharesIn[i] = IERC4626(vaults[i].vault).previewWithdraw(assetOut);
            }
            if (i < vaults.length - 1) {
                if (vaultAsset != vaults[i + 1].vault) {
                    revert VaultMismatch();
                }
            } else {
                assetOutAddress = vaultAsset;
            }
            assetOut = sharesIn[i];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Calculate the amount of assets to be received from a series of withdraws from ERC4626 vaults or Yearn
     * Vault V2.
     * @param vaults The array of vaults to withdraw from.
     * @param shareIn The amount of shares to withdraw from the first vault.
     */
    function previewRedeems(
        Vault[] calldata vaults,
        uint256 shareIn
    )
        external
        view
        returns (address assetOutAddress, uint256[] memory assetsOut)
    {
        assetsOut = new uint256[](vaults.length);
        for (uint256 i; i < vaults.length;) {
            address vaultAsset;
            if (vaults[i].isYearnVaultV2) {
                vaultAsset = IYearnVaultV2(vaults[i].vault).token();
                assetsOut[i] =
                    Math.mulDiv(shareIn, IYearnVaultV2(vaults[i].vault).pricePerShare(), 1e18, Math.Rounding.Up) + 1;
            } else {
                vaultAsset = IERC4626(vaults[i].vault).asset();
                assetsOut[i] = IERC4626(vaults[i].vault).previewRedeem(shareIn);
            }
            if (i < vaults.length - 1) {
                if (vaultAsset != vaults[i + 1].vault) {
                    revert VaultMismatch();
                }
            } else {
                assetOutAddress = vaultAsset;
            }
            shareIn = assetsOut[i];
            unchecked {
                ++i;
            }
        }
    }
}

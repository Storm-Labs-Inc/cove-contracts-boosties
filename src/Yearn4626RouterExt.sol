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
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

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
    error PathIsTooShort();
    error NonVaultAddressInPath(address invalidVault);
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
     * @param path The array of addresses that represents the path from input token to output token
     * @param assetIn The amount of assets to deposit into the first vault.
     * @return sharesOut The amount of shares to be received from each deposit. The length of the array is `path.length
     * - 1`.
     */
    // slither-disable-start calls-loop
    function previewDeposits(
        address[] calldata path,
        uint256 assetIn
    )
        external
        view
        returns (uint256[] memory sharesOut)
    {
        if (path.length < 2) revert PathIsTooShort();
        sharesOut = new uint256[](path.length - 1);
        for (uint256 i; i < sharesOut.length;) {
            address vault = path[i + 1];
            if (!Address.isContract(vault)) {
                revert NonVaultAddressInPath(vault);
            }
            address vaultAsset;
            (bool success, bytes memory data) = vault.staticcall(abi.encodeWithSelector(IERC4626.asset.selector));
            if (success) {
                vaultAsset = abi.decode(data, (address));
                sharesOut[i] = IERC4626(vault).previewDeposit(assetIn);
            } else {
                (success, data) = vault.staticcall(abi.encodeWithSelector(IYearnVaultV2.token.selector));
                if (success) {
                    vaultAsset = abi.decode(data, (address));
                    sharesOut[i] =
                        Math.mulDiv(assetIn, 1e18, IYearnVaultV2(vault).pricePerShare(), Math.Rounding.Down) - 1;
                } else {
                    revert NonVaultAddressInPath(vault);
                }
            }
            if (vaultAsset != path[i]) {
                revert VaultMismatch();
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
     * @param path The array of addresses that represents the path from input to output.
     * @param shareOut The amount of shares to mint from the last vault.
     * @return assetsIn The amount of assets required at each step. The length of the array is `path.length - 1`.
     */
    function previewMints(
        address[] calldata path,
        uint256 shareOut
    )
        external
        view
        returns (uint256[] memory assetsIn)
    {
        if (path.length < 2) revert PathIsTooShort();
        assetsIn = new uint256[](path.length - 1);
        for (uint256 i; i < assetsIn.length;) {
            address vault = path[i + 1];
            if (!Address.isContract(vault)) {
                revert NonVaultAddressInPath(vault);
            }
            address vaultAsset;
            (bool success, bytes memory data) = vault.staticcall(abi.encodeWithSelector(IERC4626.asset.selector));
            if (success) {
                vaultAsset = abi.decode(data, (address));
                assetsIn[i] = IERC4626(vault).previewMint(shareOut);
            } else {
                (success, data) = vault.staticcall(abi.encodeWithSelector(IYearnVaultV2.token.selector));
                if (success) {
                    vaultAsset = abi.decode(data, (address));
                    assetsIn[i] =
                        Math.mulDiv(shareOut, IYearnVaultV2(vault).pricePerShare(), 1e18, Math.Rounding.Up) + 1;
                } else {
                    revert NonVaultAddressInPath(vault);
                }
            }

            if (vaultAsset != path[i]) {
                revert VaultMismatch();
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
     * @param path The array of addresses that represents the path from input to output.
     * @param assetOut The amount of assets to withdraw from the last vault.
     * @return sharesIn The amount of shares required at each step. The length of the array is `path.length - 1`.
     */
    function previewWithdraws(
        address[] calldata path,
        uint256 assetOut
    )
        external
        view
        returns (uint256[] memory sharesIn)
    {
        if (path.length < 2) revert PathIsTooShort();
        sharesIn = new uint256[](path.length - 1);
        for (uint256 i; i < sharesIn.length;) {
            address vault = path[i];
            if (!Address.isContract(vault)) {
                revert NonVaultAddressInPath(vault);
            }
            address vaultAsset;
            (bool success, bytes memory data) = vault.staticcall(abi.encodeWithSelector(IERC4626.asset.selector));
            if (success) {
                vaultAsset = abi.decode(data, (address));
                sharesIn[i] = IERC4626(vault).previewWithdraw(assetOut);
            } else {
                (success, data) = vault.staticcall(abi.encodeWithSelector(IYearnVaultV2.token.selector));
                if (success) {
                    vaultAsset = abi.decode(data, (address));
                    sharesIn[i] =
                        Math.mulDiv(assetOut, 1e18, IYearnVaultV2(vault).pricePerShare(), Math.Rounding.Down) - 1;
                } else {
                    revert NonVaultAddressInPath(vault);
                }
            }
            if (vaultAsset != path[i + 1]) {
                revert VaultMismatch();
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
     * @param path The array of addresses that represents the path from input to output.
     * @param shareIn The amount of shares to withdraw from the first vault.
     * @return assetsOut The amount of assets to be received at each step. The length of the array is `path.length - 1`.
     */
    function previewRedeems(
        address[] calldata path,
        uint256 shareIn
    )
        external
        view
        returns (uint256[] memory assetsOut)
    {
        if (path.length < 2) revert PathIsTooShort();
        assetsOut = new uint256[](path.length - 1);
        for (uint256 i; i < assetsOut.length;) {
            address vault = path[i];
            if (!Address.isContract(vault)) {
                revert NonVaultAddressInPath(vault);
            }
            address vaultAsset;
            (bool success, bytes memory data) = vault.staticcall(abi.encodeWithSelector(IERC4626.asset.selector));
            if (success) {
                vaultAsset = abi.decode(data, (address));
                assetsOut[i] = IERC4626(vault).previewRedeem(shareIn);
            } else {
                (success, data) = vault.staticcall(abi.encodeWithSelector(IYearnVaultV2.token.selector));
                if (success) {
                    vaultAsset = abi.decode(data, (address));
                    assetsOut[i] =
                        Math.mulDiv(shareIn, IYearnVaultV2(vault).pricePerShare(), 1e18, Math.Rounding.Up) + 1;
                } else {
                    revert NonVaultAddressInPath(vault);
                }
            }
            if (vaultAsset != path[i + 1]) {
                revert VaultMismatch();
            }
            shareIn = assetsOut[i];
            unchecked {
                ++i;
            }
        }
    }
}

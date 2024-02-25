// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Yearn4626Router } from "Yearn-ERC4626-Router/Yearn4626Router.sol";
import { IYearnVaultV2 } from "./interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";
import { IPermit2 } from "permit2/interfaces/IPermit2.sol";
import { ISignatureTransfer } from "permit2/interfaces/ISignatureTransfer.sol";
import { IWETH9 } from "Yearn-ERC4626-Router/external/PeripheryPayments.sol";
import { IYearn4626RouterExt } from "./interfaces/IYearn4626RouterExt.sol";

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

    /**
     * @notice Constructs the Yearn4626RouterExt contract.
     * @dev Sets up the router with the name for the vault, WETH address, and Permit2 contract address.
     * @param name_ The name of the vault.
     * @param weth_ The address of the WETH contract.
     * @param permit2_ The address of the Permit2 contract.
     */
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
}

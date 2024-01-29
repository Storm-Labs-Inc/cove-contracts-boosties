// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Yearn4626Router } from "Yearn-ERC4626-Router/Yearn4626Router.sol";
import { IYearnVaultV2 } from "./interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";
import { IPermit2 } from "permit2/interfaces/IPermit2.sol";
import { ISignatureTransfer } from "permit2/interfaces/ISignatureTransfer.sol";
import { IWETH9 } from "Yearn-ERC4626-Router/external/PeripheryPayments.sol";
import { IYearn4626RouterExt } from "./interfaces/IYearn4626RouterExt.sol";

contract Yearn4626RouterExt is IYearn4626RouterExt, Yearn4626Router {
    IPermit2 private immutable _PERMIT2;

    error InsufficientShares();
    error InvalidTo();

    constructor(string memory name_, address weth_, address permit2_) Yearn4626Router(name_, IWETH9(weth_)) {
        _PERMIT2 = IPermit2(permit2_);
    }

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

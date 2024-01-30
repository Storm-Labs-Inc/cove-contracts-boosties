// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { IYearn4626Router } from "Yearn-ERC4626-Router/interfaces/IYearn4626Router.sol";
import { IYearnVaultV2 } from "./deps/yearn/veYFI/IYearnVaultV2.sol";
import { ISignatureTransfer } from "permit2/interfaces/ISignatureTransfer.sol";

interface IYearn4626RouterExt is IYearn4626Router {
    function depositToVaultV2(
        IYearnVaultV2 vault,
        uint256 amount,
        address to,
        uint256 minSharesOut
    )
        external
        payable
        returns (uint256 sharesOut);

    function pullTokensWithPermit2(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    )
        external
        payable;
}

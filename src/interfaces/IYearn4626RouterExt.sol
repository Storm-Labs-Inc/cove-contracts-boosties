// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { IYearn4626Router } from "Yearn-ERC4626-Router/interfaces/IYearn4626Router.sol";
import { IYearnVaultV2 } from "./deps/yearn/veYFI/IYearnVaultV2.sol";
import { ISignatureTransfer } from "permit2/interfaces/ISignatureTransfer.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IStakeDaoGauge } from "./deps/stakeDAO/IStakeDaoGauge.sol";

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

    function redeemVaultV2(
        IYearnVaultV2 vault,
        uint256 shares,
        address to,
        uint256 minAmountOut
    )
        external
        payable
        returns (uint256 amountOut);

    function redeemFromRouter(
        IERC4626 vault,
        uint256 shares,
        address to,
        uint256 minAmountOut
    )
        external
        payable
        returns (uint256 amountOut);

    function withdrawFromRouter(
        IERC4626 vault,
        uint256 assets,
        address to,
        uint256 maxSharesIn
    )
        external
        payable
        returns (uint256 sharesIn);

    function redeemStakeDaoGauge(IStakeDaoGauge gauge, uint256 shares) external payable returns (uint256 amountOut);

    function previewDeposits(
        address[] calldata path,
        uint256 assetsIn
    )
        external
        view
        returns (uint256[] memory sharesOut);
    function previewMints(
        address[] calldata path,
        uint256 sharesOut
    )
        external
        view
        returns (uint256[] memory assetsIn);
    function previewWithdraws(
        address[] calldata path,
        uint256 assetsOut
    )
        external
        view
        returns (uint256[] memory sharesIn);
    function previewRedeems(
        address[] calldata path,
        uint256 sharesIn
    )
        external
        view
        returns (uint256[] memory assetsOut);

    function pullTokenWithPermit2(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    )
        external
        payable;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Yearn4626Router } from "Yearn-ERC4626-Router/Yearn4626Router.sol";
import { IYearnVaultV2 } from "./interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";
import { IPermit2 } from "permit2/interfaces/IPermit2.sol";
import { ISignatureTransfer } from "permit2/interfaces/ISignatureTransfer.sol";
import { IWETH9 } from "Yearn-ERC4626-Router/external/PeripheryPayments.sol";
import { IYearn4626RouterExt } from "./interfaces/IYearn4626RouterExt.sol";
import { IERC20Metadata, IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IStakeDaoGauge } from "./interfaces/deps/stakeDAO/IStakeDaoGauge.sol";
import { IStakeDaoVault } from "./interfaces/deps/stakeDAO/IStakeDaoVault.sol";

/**
 * @title Yearn4626Router Extension
 * @notice Extends the Yearn4626Router with additional functionality for depositing to Yearn Vault V2 and pulling tokens
 * with Permit2.
 * @dev This contract introduces two key functions: depositing to Yearn Vault V2 and pulling tokens with a signature via
 * Permit2.
 * The contract holds an immutable reference to a Permit2 contract to facilitate token transfers with permits.
 */
contract Yearn4626RouterExt is IYearn4626RouterExt, Yearn4626Router {
    using SafeERC20 for IERC20;

    // slither-disable-next-line naming-convention
    IPermit2 private immutable _PERMIT2;

    /// @notice Error for when the number of shares received is less than the minimum expected.
    error InsufficientShares();
    /// @notice Error for when the amount of assets received is less than the minimum expected.
    error InsufficientAssets();
    /// @notice Error for when the amount of shares burned is more than the maximum expected.
    error RequiresMoreThanMaxShares();
    /// @notice Error for when the `to` address in the Permit2 transfer is not the router contract.
    error InvalidPermit2TransferTo();
    /// @notice Error for when the amount in the Permit2 transfer is not the same as the requested amount.
    error InvalidPermit2TransferAmount();
    /// @notice Error for when the path is too short to preview the deposits/mints/withdraws/redeems.
    error PreviewPathIsTooShort();
    /// @notice Error for when the address in the path is not a vault.
    error PreviewNonVaultAddressInPath(address invalidVault);
    /// @notice Error for when an address in the path does not match previous or next vault's asset.
    error PreviewVaultMismatch();

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

    // ------------- YEARN VAULT V2 FUNCTIONS ------------- //

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
     * @notice Redeems the specified `shares` from the Yearn Vault V2.
     * @dev The shares must exist in this router before calling this function.
     * @param vault The Yearn Vault V2 contract instance.
     * @param shares The amount of shares to redeem.
     * @param to The address to which the assets will be transferred.
     * @param minAssetsOut The minimum amount of assets expected to be received.
     * @return amountOut The actual amount of assets received by the `to` address.
     */
    function redeemVaultV2(
        IYearnVaultV2 vault,
        uint256 shares,
        address to,
        uint256 minAssetsOut
    )
        public
        payable
        returns (uint256 amountOut)
    {
        if ((amountOut = vault.withdraw(shares, to)) < minAssetsOut) revert InsufficientAssets();
    }

    // ------------- ERC4626 VAULT FUNCTIONS  ------------- //

    /**
     * @notice Redeems the specified IERC4626 vault `shares` that this router is holding.
     * @param vault The IERC4626 vault contract instance.
     * @param shares The amount of shares to redeem.
     * @param to The address to which the assets will be transferred.
     * @param minAmountOut The minimum amount of assets expected to be received.
     * @return amountOut The actual amount of assets received by the `to` address.
     */
    function redeemFromRouter(
        IERC4626 vault,
        uint256 shares,
        address to,
        uint256 minAmountOut
    )
        public
        payable
        virtual
        returns (uint256 amountOut)
    {
        if ((amountOut = vault.redeem(shares, to, address(this))) < minAmountOut) revert InsufficientAssets();
    }

    /**
     * @notice Withdraws the specified `assets` from the IERC4626 vault.
     * @param vault The IERC4626 vault contract instance.
     * @param assets The amount of assets to withdraw.
     * @param to The address to which the assets will be transferred.
     * @param maxSharesIn The maximum amount of vault shares expected to be burned.
     * @return sharesOut The actual amount of shares burned from the `vault`.
     */
    function withdrawFromRouter(
        IERC4626 vault,
        uint256 assets,
        address to,
        uint256 maxSharesIn
    )
        public
        payable
        virtual
        returns (uint256 sharesOut)
    {
        if ((sharesOut = vault.withdraw(assets, to, address(this))) > maxSharesIn) revert RequiresMoreThanMaxShares();
    }

    // ------------- STAKEDAO FUNCTIONS  ------------- //

    /**
     * @notice Redeems the specified `shares` of the StakeDAO Gauge.
     * @dev Assumes the assets withdrawn will be the the yearn vault tokens and will always be the same amount as the
     * `shares` of the burned StakeDAO gauge tokens.
     * @param gauge The StakeDAO Gauge contract instance.
     * @param shares The amount of StakeDAO gauge tokens to burn.
     */
    function redeemStakeDaoGauge(IStakeDaoGauge gauge, uint256 shares, address to) public payable returns (uint256) {
        IStakeDaoVault vault = IStakeDaoVault(gauge.staking_token());
        vault.withdraw(shares);
        if (to != address(this)) {
            IERC20(vault.token()).safeTransfer(to, shares);
        }
        return shares;
    }

    // ------------- PERMIT2 FUNCTIONS  ------------- //

    /**
     * @notice Pulls tokens to the contract using a signature via Permit2.
     * @dev Verifies that the `to` address in `transferDetails` is the contract itself and then calls
     * `permitTransferFrom` on the Permit2 contract.
     * Reverts with `InvalidTo` if the `to` address is not the contract itself.
     * @param permit The PermitTransferFrom struct containing the permit details.
     * @param transferDetails The details of the transfer, including the `to` address.
     * @param signature The signature to authorize the token transfer.
     */
    function pullTokenWithPermit2(
        ISignatureTransfer.PermitTransferFrom calldata permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    )
        public
        payable
    {
        if (transferDetails.to != address(this)) revert InvalidPermit2TransferTo();
        if (permit.permitted.amount != transferDetails.requestedAmount) revert InvalidPermit2TransferAmount();
        _PERMIT2.permitTransferFrom(permit, transferDetails, msg.sender, signature);
    }

    // ------------- PREVIEW FUNCTIONS  ------------- //

    /**
     * @notice Calculate the amount of shares to be received from a series of deposits to ERC4626 vaults or Yearn Vault
     * V2.
     * @param path The array of addresses that represents the path from input token to output token
     * @param assetsIn The amount of assets to deposit into the first vault.
     * @return sharesOut The amount of shares to be received from each deposit. The length of the array is `path.length
     * - 1`.
     */
    // slither-disable-start calls-loop,low-level-calls
    function previewDeposits(
        address[] calldata path,
        uint256 assetsIn
    )
        external
        view
        returns (uint256[] memory sharesOut)
    {
        if (path.length < 2) revert PreviewPathIsTooShort();
        uint256 sharesOutLength = path.length - 1;
        sharesOut = new uint256[](sharesOutLength);
        for (uint256 i; i < sharesOutLength;) {
            address vault = path[i + 1];
            if (!Address.isContract(vault)) {
                revert PreviewNonVaultAddressInPath(vault);
            }
            address vaultAsset = address(0);
            (bool success, bytes memory data) = vault.staticcall(abi.encodeCall(IERC4626.asset, ()));
            if (success) {
                vaultAsset = abi.decode(data, (address));
                sharesOut[i] = IERC4626(vault).previewDeposit(assetsIn);
            } else {
                (success, data) = vault.staticcall(abi.encodeCall(IYearnVaultV2.token, ()));
                if (success) {
                    vaultAsset = abi.decode(data, (address));
                    sharesOut[i] = Math.mulDiv(
                        assetsIn,
                        10 ** IERC20Metadata(vault).decimals(),
                        IYearnVaultV2(vault).pricePerShare(),
                        Math.Rounding.Down
                    ) - 1;
                } else {
                    revert PreviewNonVaultAddressInPath(vault);
                }
            }
            if (vaultAsset != path[i]) {
                revert PreviewVaultMismatch();
            }
            assetsIn = sharesOut[i];

            /// @dev Increment the loop index `i` without checking for overflow.
            /// This is safe because the loop's termination condition ensures that `i` will not exceed
            /// the bounds of the `sharesOut` array, which would be the only case where an overflow could occur.
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Calculate the amount of assets required to mint a given amount of shares from a series of deposits to
     * ERC4626 vaults or Yearn Vault V2.
     * @param path The array of addresses that represents the path from input to output.
     * @param sharesOut The amount of shares to mint from the last vault.
     * @return assetsIn The amount of assets required at each step. The length of the array is `path.length - 1`.
     * @dev sharesOut is the expected result at the last vault, and the path = [tokenIn, vault0, vault1, ..., vaultN].
     * First calculate the amount of assets in to get the desired sharesOut from the last vault, then using that amount
     * as the next sharesOut to get the amount of assets in for the penultimate vault.
     */
    function previewMints(
        address[] calldata path,
        uint256 sharesOut
    )
        external
        view
        returns (uint256[] memory assetsIn)
    {
        if (path.length < 2) revert PreviewPathIsTooShort();
        uint256 assetsInLength = path.length - 1;
        assetsIn = new uint256[](assetsInLength);
        for (uint256 i = assetsInLength; i > 0;) {
            address vault = path[i];
            if (!Address.isContract(vault)) {
                revert PreviewNonVaultAddressInPath(vault);
            }
            address vaultAsset = address(0);
            (bool success, bytes memory data) = vault.staticcall(abi.encodeCall(IERC4626.asset, ()));
            if (success) {
                vaultAsset = abi.decode(data, (address));
                assetsIn[i - 1] = IERC4626(vault).previewMint(sharesOut);
            } else {
                (success, data) = vault.staticcall(abi.encodeCall(IYearnVaultV2.token, ()));
                if (success) {
                    vaultAsset = abi.decode(data, (address));
                    assetsIn[i - 1] = Math.mulDiv(
                        sharesOut,
                        IYearnVaultV2(vault).pricePerShare(),
                        10 ** IERC20Metadata(vault).decimals(),
                        Math.Rounding.Up
                    ) + 1;
                } else {
                    revert PreviewNonVaultAddressInPath(vault);
                }
            }

            if (vaultAsset != path[i - 1]) {
                revert PreviewVaultMismatch();
            }
            sharesOut = assetsIn[i - 1];

            /// @dev Decrement the loop counter within an unchecked block to avoid redundant gas cost associated with
            /// underflow checking. This is safe because the loop's initialization and exit condition ensure that `i`
            /// will not underflow.
            unchecked {
                --i;
            }
        }
    }

    /**
     * @notice Calculate the amount of shares required to withdraw a given amount of assets from a series of withdraws
     * from ERC4626 vaults or Yearn Vault V2.
     * @param path The array of addresses that represents the path from input to output.
     * @param assetsOut The amount of assets to withdraw from the last vault.
     * @dev assetsOut is the desired result of the output token, and the path = [vault0, vault1, ..., vaultN, tokenOut].
     * First calculate the amount of shares in to get the desired assetsOut from the last vault, then using that amount
     * as the next assetsOut to get the amount of shares in for the penultimate vault.
     * @return sharesIn The amount of shares required at each step. The length of the array is `path.length - 1`.
     */
    function previewWithdraws(
        address[] calldata path,
        uint256 assetsOut
    )
        external
        view
        returns (uint256[] memory sharesIn)
    {
        if (path.length < 2) revert PreviewPathIsTooShort();
        uint256 sharesInLength = path.length - 1;
        sharesIn = new uint256[](sharesInLength);
        for (uint256 i = path.length - 2;;) {
            address vault = path[i];
            if (!Address.isContract(vault)) {
                revert PreviewNonVaultAddressInPath(vault);
            }
            address vaultAsset = address(0);
            (bool success, bytes memory data) = vault.staticcall(abi.encodeCall(IERC4626.asset, ()));
            if (success) {
                vaultAsset = abi.decode(data, (address));
                sharesIn[i] = IERC4626(vault).previewWithdraw(assetsOut);
            } else {
                (success, data) = vault.staticcall(abi.encodeCall(IYearnVaultV2.token, ()));
                if (success) {
                    vaultAsset = abi.decode(data, (address));
                    sharesIn[i] = Math.mulDiv(
                        assetsOut,
                        10 ** IERC20Metadata(vault).decimals(),
                        IYearnVaultV2(vault).pricePerShare(),
                        Math.Rounding.Up
                    );
                } else {
                    // StakeDAO gauge token
                    // StakeDaoGauge.staking_token().token() is the yearn vault v2 token
                    (success, data) = vault.staticcall(abi.encodeCall(IStakeDaoGauge.staking_token, ()));
                    if (success) {
                        vaultAsset = IStakeDaoVault(abi.decode(data, (address))).token();
                        sharesIn[i] = assetsOut;
                    } else {
                        revert PreviewNonVaultAddressInPath(vault);
                    }
                }
            }
            if (vaultAsset != path[i + 1]) {
                revert PreviewVaultMismatch();
            }
            if (i == 0) return sharesIn;
            assetsOut = sharesIn[i];

            /// @dev Decrement the loop counter without checking for overflow.  This is safe because the for loop
            /// naturally ensures that `i` will not underflow as it is bounded by i == 0 check.
            unchecked {
                --i;
            }
        }
    }

    /**
     * @notice Calculate the amount of assets to be received from a series of withdraws from ERC4626 vaults or Yearn
     * Vault V2.
     * @param path The array of addresses that represents the path from input to output.
     * @param sharesIn The amount of shares to withdraw from the first vault.
     * @return assetsOut The amount of assets to be received at each step. The length of the array is `path.length - 1`.
     */
    function previewRedeems(
        address[] calldata path,
        uint256 sharesIn
    )
        external
        view
        returns (uint256[] memory assetsOut)
    {
        if (path.length < 2) revert PreviewPathIsTooShort();
        uint256 assetsOutLength = path.length - 1;
        assetsOut = new uint256[](assetsOutLength);
        for (uint256 i; i < assetsOutLength;) {
            address vault = path[i];
            if (!Address.isContract(vault)) {
                revert PreviewNonVaultAddressInPath(vault);
            }
            address vaultAsset = address(0);
            (bool success, bytes memory data) = vault.staticcall(abi.encodeCall(IERC4626.asset, ()));
            if (success) {
                vaultAsset = abi.decode(data, (address));
                assetsOut[i] = IERC4626(vault).previewRedeem(sharesIn);
            } else {
                (success, data) = vault.staticcall(abi.encodeCall(IYearnVaultV2.token, ()));
                if (success) {
                    vaultAsset = abi.decode(data, (address));
                    assetsOut[i] = Math.mulDiv(
                        sharesIn,
                        IYearnVaultV2(vault).pricePerShare(),
                        10 ** IERC20Metadata(vault).decimals(),
                        Math.Rounding.Down
                    );
                } else {
                    // StakeDAO gauge token
                    // StakeDaoGauge.staking_token().token() is the yearn vault v2 token
                    (success, data) = vault.staticcall(abi.encodeCall(IStakeDaoGauge.staking_token, ()));
                    if (success) {
                        vaultAsset = IStakeDaoVault(abi.decode(data, (address))).token();
                        assetsOut[i] = sharesIn;
                    } else {
                        revert PreviewNonVaultAddressInPath(vault);
                    }
                }
            }
            if (vaultAsset != path[i + 1]) {
                revert PreviewVaultMismatch();
            }
            sharesIn = assetsOut[i];

            /// @dev The unchecked block is used here to prevent overflow checking for the loop increment, which is not
            /// necessary since the loop's exit condition ensures `i` will not exceed `assetsOutLength`.
            unchecked {
                ++i;
            }
        }
    }
    // slither-disable-end calls-loop,low-level-calls
}

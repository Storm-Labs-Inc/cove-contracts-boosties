// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IYearnVaultV2 } from "src/interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title YearnVaultV2Helper
 * @notice Helper functions for Yearn Vault V2 contracts. Since Yearn Vault V2 contracts are not ERC-4626 compliant,
 * they do not provide `previewDeposit`, `previewMint`, `previewRedeem`, and `previewWithdraw` functions. This library
 * provides these functions for previewing share based deposit/mint/redeem/withdraw estimations.
 * @dev These functions are only to be used off-chain for previewing. Due to how Yearn Vault V2 contracts work,
 * share based withdraw/redeem estimations may not be accurate if the vault incurs a loss, thus share price changes.
 * Coverage is currently disabled for this library due to forge limitations. TODO: Once the fix PR is merged,
 * https://github.com/foundry-rs/foundry/pull/7510 coverage should be re-enabled.
 */
library YearnVaultV2Helper {
    /**
     * @notice Calculates the currently free funds in a Yearn Vault V2 contract.
     * @param vault The Yearn Vault V2 contract.
     * @return The free funds in the vault.
     * @dev This is based on Yearn Vault V2 contract's free funds calculation logic.
     * https://github.com/yearn/yearn-vaults/blob/97ca1b2e4fcf20f4be0ff456dabd020bfeb6697b/contracts/Vault.vy#L844-L847
     */
    function freeFunds(IYearnVaultV2 vault) internal view returns (uint256) {
        uint256 lockedProfit = vault.lockedProfit();
        uint256 lockedFundsRatio = (block.timestamp - vault.lastReport()) * vault.lockedProfitDegradation();
        // slither-disable-next-line timestamp
        if (lockedFundsRatio < 1e18) {
            lockedProfit -= (lockedProfit * lockedFundsRatio) / 1e18;
        } else {
            lockedProfit = 0;
        }
        return vault.totalAssets() - lockedProfit;
    }

    /**
     * @notice Preview the amount of shares to be issued for a given deposit amount.
     * @param vault The Yearn Vault V2 contract.
     * @param assetsIn The amount of assets to be deposited.
     * @return The number of shares that would be issued for the deposited assets.
     */
    function previewDeposit(IYearnVaultV2 vault, uint256 assetsIn) internal view returns (uint256) {
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply > 0) {
            return Math.mulDiv(assetsIn, totalSupply, freeFunds(vault), Math.Rounding.Down);
        }
        return assetsIn;
    }

    /**
     * @notice Preview the amount of assets required to mint a given amount of shares.
     * @param vault The Yearn Vault V2 contract.
     * @param sharesOut The number of shares to be minted.
     * @return The amount of assets required to mint the specified number of shares.
     */
    function previewMint(IYearnVaultV2 vault, uint256 sharesOut) internal view returns (uint256) {
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply > 0) {
            return Math.mulDiv(sharesOut, freeFunds(vault), totalSupply, Math.Rounding.Up);
        }
        return sharesOut;
    }

    /**
     * @notice Preview the amount of assets to be received for redeeming a given amount of shares.
     * @param vault The Yearn Vault V2 contract.
     * @param sharesIn The number of shares to be redeemed.
     * @return The amount of assets that would be received for the redeemed shares.
     */
    function previewRedeem(IYearnVaultV2 vault, uint256 sharesIn) internal view returns (uint256) {
        uint256 totalSupply = vault.totalSupply();
        if (sharesIn > totalSupply) {
            return freeFunds(vault);
        }
        if (totalSupply > 0) {
            return Math.mulDiv(sharesIn, freeFunds(vault), totalSupply, Math.Rounding.Down);
        }
        return 0;
    }

    /**
     * @notice Preview the number of shares to be redeemed for a given withdrawal amount of assets.
     * @param vault The Yearn Vault V2 contract.
     * @param assetsOut The amount of assets to be withdrawn.
     * @return The number of shares that would be redeemed for the withdrawn assets.
     */
    function previewWithdraw(IYearnVaultV2 vault, uint256 assetsOut) internal view returns (uint256) {
        uint256 freeFunds_ = freeFunds(vault);
        // slither-disable-next-line timestamp
        if (assetsOut > freeFunds_) {
            return vault.totalSupply();
        }
        // slither-disable-next-line timestamp
        if (freeFunds_ > 0) {
            return Math.mulDiv(assetsOut, vault.totalSupply(), freeFunds(vault), Math.Rounding.Up);
        }
        return 0;
    }
}

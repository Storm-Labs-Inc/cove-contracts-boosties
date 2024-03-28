// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { IYearnVaultV2 } from "src/interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title YearnVaultV2Helper
/// @notice Helper functions for Yearn Vault V2 contracts. Since Yearn Vault V2 contracts are not ERC-4626 compliant, we
/// need to implement custom preview functions for deposit, mint, redeem, and withdraw.
library YearnVaultV2Helper {
    /// @dev Yearn Vault V2 contract's calculate locked profit logic
    /// https://github.com/yearn/yearn-vaults/blob/97ca1b2e4fcf20f4be0ff456dabd020bfeb6697b/contracts/Vault.vy#L829-L842
    function calculateLockedProfit(IYearnVaultV2 vault) internal view returns (uint256) {
        uint256 lockedProfit = vault.lockedProfit();
        uint256 lockedFundsRatio = (block.timestamp - vault.lastReport()) * vault.lockedProfitDegradation();
        if (lockedFundsRatio < 1e18) {
            lockedProfit -= (lockedProfit * lockedFundsRatio) / 1e18;
        } else {
            lockedProfit = 0;
        }
        return lockedProfit;
    }

    /// @dev Yearn Vault V2 contract's free funds calculation logic
    /// https://github.com/yearn/yearn-vaults/blob/97ca1b2e4fcf20f4be0ff456dabd020bfeb6697b/contracts/Vault.vy#L844-L847
    function freeFunds(IYearnVaultV2 vault) internal view returns (uint256) {
        return vault.totalAssets() - calculateLockedProfit(vault);
    }

    /// @dev Yearn Vault V2 contract's _issueSharesForAmount() logic
    /// https://github.com/yearn/yearn-vaults/blob/97ca1b2e4fcf20f4be0ff456dabd020bfeb6697b/contracts/Vault.vy#L849-L872
    function previewDeposit(IYearnVaultV2 vault, uint256 assetsIn) internal view returns (uint256) {
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply > 0) {
            return Math.mulDiv(assetsIn, totalSupply, freeFunds(vault), Math.Rounding.Down);
        }
        return assetsIn;
    }

    /// @dev Yearn Vault V2 contract's _issueSharesForAmount() logic
    /// https://github.com/yearn/yearn-vaults/blob/97ca1b2e4fcf20f4be0ff456dabd020bfeb6697b/contracts/Vault.vy#L849-L872
    function previewMint(IYearnVaultV2 vault, uint256 sharesOut) internal view returns (uint256) {
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply > 0) {
            return Math.mulDiv(sharesOut, freeFunds(vault), totalSupply, Math.Rounding.Up);
        }
        return sharesOut;
    }

    function previewRedeem(IYearnVaultV2 vault, uint256 sharesIn) internal view returns (uint256) {
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply > 0) {
            return Math.mulDiv(sharesIn, freeFunds(vault), totalSupply, Math.Rounding.Down);
        }
        return 0;
    }

    function previewWithdraw(IYearnVaultV2 vault, uint256 assetsOut) internal view returns (uint256) {
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply > 0) {
            return Math.mulDiv(assetsOut, totalSupply, freeFunds(vault), Math.Rounding.Up);
        }
        return 0;
    }
}

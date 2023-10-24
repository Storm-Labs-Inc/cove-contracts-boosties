// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import { BaseTokenizedStrategy } from "src/deps/yearn/tokenized-strategy/BaseTokenizedStrategy.sol";
import { StrategyAssetSwap, CurveRouterSwapper } from "src/strategies/StrategyAssetSwap.sol";
import { Errors } from "../libraries/Errors.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 as console } from "forge-std/console2.sol";
import { WrappedYearnV3 } from "./WrappedYearnV3.sol";

contract WrappedYearnV3StrategyAssetSwap is StrategyAssetSwap, BaseTokenizedStrategy, WrappedYearnV3 {
    // Libraries
    using SafeERC20 for IERC20;

    // Immutable storage variables
    address internal immutable _VAULT_ASSET;
    uint256 internal immutable _VAULT_ASSET_DECIMALS;

    constructor(
        address _asset,
        address _vault,
        address _yearnStakingDelegate,
        address _dYFI,
        address _curveRouter,
        bool _usesOracle
    )
        BaseTokenizedStrategy(_asset, "Wrapped YearnV3 Asset Swap Strategy")
        CurveRouterSwapper(_curveRouter)
        WrappedYearnV3(_vault, _yearnStakingDelegate, _dYFI)
    {
        // Checks
        // Cache variables
        address _vaultAsset = IERC4626(_vault).asset();
        // Ensure that the given asset is NOT the same as the given vault's asset
        if (_asset == _vaultAsset) {
            revert Errors.VaultAssetDoesNotDiffer();
        }

        // Effects
        // Set storage variable values
        _VAULT_ASSET = _vaultAsset;
        _VAULT_ASSET_DECIMALS = IERC20Metadata(_vaultAsset).decimals();
        _setUsesOracle(_usesOracle);

        // Interactions
        _approveTokenForSwap(_dYFI);
        _approveTokenForSwap(_asset);
        _approveTokenForSwap(_vaultAsset);
        IERC20(_vaultAsset).forceApprove(_vault, type(uint256).max);
        IERC20(_vault).forceApprove(_yearnStakingDelegate, type(uint256).max);
    }

    // TODO: not sure exactly which role to assign here
    function setOracle(address token, address oracle) external onlyManagement {
        _setOracle(token, oracle);
    }

    // TODO: not sure exactly which role to assign here
    function setSwapParameters(
        CurveSwapParams memory deploySwapParams,
        CurveSwapParams memory freeSwapParams,
        StrategyAssetSwap.SwapTolerance memory _swapTolerance
    )
        external
        onlyManagement
    {
        // Interactions
        _setSwapParameters(TokenizedStrategy.asset(), _VAULT_ASSET, deploySwapParams, freeSwapParams, _swapTolerance);
    }

    function setHarvestSwapParams(CurveSwapParams memory curveSwapParams) external onlyManagement {
        // Set harvest to swap dYFI -> vaultAsset for this strategy
        _setHarvestSwapParams(_VAULT_ASSET, curveSwapParams);
    }

    function _deployFunds(uint256 _amount) internal override {
        // Get prices of strategy asset and vault asset
        // @dev this will be 1,1 if not using an oracle
        (uint256 strategyAssetPrice, uint256 vaultAssetPrice) = _getPrices(asset, _VAULT_ASSET);
        // Expected amount of tokens to receive from the swap using oracles or fixed price
        uint256 expectedAmount = _calculateExpectedAmount(
            strategyAssetPrice, vaultAssetPrice, TokenizedStrategy.decimals(), _VAULT_ASSET_DECIMALS, _amount
        );
        console.log("fromAmount: ", _amount);
        console.log("expectedAmount: ", expectedAmount);

        // Swap _amount of strategy asset for vault asset using the deploy swap params
        uint256 swapResult = _swap(_assetDeploySwapParams, _amount, expectedAmount, address(this));

        // check if we got less than the expected amount
        console.log("after swap token Balance: ", swapResult);
        // Deposit _amount into vault and YSD if the swap was successful
        _depositVaultAssetToYSD(swapResult);
    }

    function _freeFunds(uint256 _amount) internal override {
        // Find withdrawer's allocation of total ysd shares
        uint256 vaultSharesToWithdraw = totalUnderlyingVaultShares * _amount / TokenizedStrategy.totalAssets();
        // Withdraw from gauge via YSD
        uint256 withdrawnVaultAssetAmount = _redeemVaultSharesFromYSD(vaultSharesToWithdraw);
        console.log("redeem amount: ", withdrawnVaultAssetAmount);
        // Get prices of strategy asset and vault asset
        (uint256 strategyAssetPrice, uint256 vaultAssetPrice) = _getPrices(asset, _VAULT_ASSET);
        console.log("strategyAssetPrice: ", strategyAssetPrice, "vaultAssetPrice: ", vaultAssetPrice);
        // Expected amount of asset to receive from the swap using oracles or fixed price
        uint256 expectedAmount = _calculateExpectedAmount(
            vaultAssetPrice,
            strategyAssetPrice,
            _VAULT_ASSET_DECIMALS,
            TokenizedStrategy.decimals(),
            withdrawnVaultAssetAmount
        );

        uint256 swapResult = _swap(_assetFreeSwapParams, withdrawnVaultAssetAmount, expectedAmount, address(this));

        // Check if we got less than the expected amount
        console.log("after swap token Balance: ", swapResult);
        console.log("expected swap amount    : ", expectedAmount);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // Cache variables
        address _vault = _VAULT;
        address _ysd = _YEARN_STAKING_DELEGATE;
        address _vaultAsset = _VAULT_ASSET;
        // Harvest any dYFI rewards
        uint256 dYFIBalance = IYearnStakingDelegate(_ysd).harvest(_vault);
        uint256 newIdleBalance = 0;
        // If dYFI was harvested, swap it for vault asset
        if (dYFIBalance > 0) {
            // If the strategy is not shutdown, deploy the funds
            // Else add the received tokens to the idle balance
            if (!TokenizedStrategy.isShutdown()) {
                // Swap dYFI -> vaultAsset and then deploy the funds
                uint256 receivedTokens = _swap(_harvestSwapParams, dYFIBalance, 0, address(this));
                _depositVaultAssetToYSD(receivedTokens);
            } else {
                // @dev this is an unoptimized swap path that could be improved
                // Only gets triggered if the strategy is shutdown
                // Swap dYFI -> vaultAsset
                newIdleBalance = _swap(_harvestSwapParams, dYFIBalance, 0, address(this));
                // Swap vaultAsset -> strategyAsset
                newIdleBalance = _swap(_assetFreeSwapParams, newIdleBalance, 0, address(this));
            }
        }

        // TODO: below may not be accurate accounting as the underlying vault may not have realized gains/losses
        // additionally profits may have been awarded but not fully unlocked yet, these are concerns to be investigated
        // off-chain by management in the timing of calling _harvestAndReport

        // Convert totalUnderlyingVaultShares to underlying vault assets
        uint256 underlyingVaultAssets = IERC4626(_vault).convertToAssets(totalUnderlyingVaultShares);
        // Convert vault asset to strategy asset using oracles or fixed price
        (uint256 vaultAssetPrice, uint256 strategyAssetPrice) = _getPrices(_vaultAsset, TokenizedStrategy.asset());
        /// @dev this always returns the worst possible exchange as it is used for the minimum amount to
        /// receive in the swap. TODO may be to change this behavior to have more accurate accounting
        return newIdleBalance
            + _calculateExpectedAmount(
                vaultAssetPrice,
                strategyAssetPrice,
                _VAULT_ASSET_DECIMALS,
                TokenizedStrategy.decimals(),
                underlyingVaultAssets
            );
    }
}

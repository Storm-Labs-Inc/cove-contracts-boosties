// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BaseTokenizedStrategy } from "src/deps/yearn/tokenized-strategy/BaseTokenizedStrategy.sol";
import { StrategyAssetSwap, CurveRouterSwapper } from "src/strategies/StrategyAssetSwap.sol";
import { Errors } from "../libraries/Errors.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 as console } from "forge-std/console2.sol";

contract TokenizedStrategyAssetSwap is StrategyAssetSwap, BaseTokenizedStrategy {
    // Libraries
    using SafeERC20 for IERC20;

    // Immutable storage variables
    address public immutable VAULT;
    address public immutable VAULT_ASSET;

    // Storage variables
    uint256 public totalOwnedUnderlying4626Shares;
    uint256 public vaultAssetDecimals;

    constructor(
        address _asset,
        address _vault,
        address _curveRouter,
        bool _usesOracle
    )
        // TODO: change this to CurveRouterSwapper constructor
        BaseTokenizedStrategy(_asset, "Tokenized Asset Swap Strategy")
        CurveRouterSwapper(_curveRouter)
    {
        // Checks
        // Check for zero addresses
        if (_asset == address(0) || _vault == address(0)) {
            revert Errors.ZeroAddress();
        }
        address _vaultAsset = IERC4626(_vault).asset();
        // Check if the given asset is the same as the given vault's asset
        if (_asset == _vaultAsset) {
            revert Errors.VaultAssetDoesNotDiffer();
        }

        // Effects
        // Set storage variable values
        VAULT = _vault;
        VAULT_ASSET = _vaultAsset;
        vaultAssetDecimals = IERC20Metadata(_vaultAsset).decimals();
        _setUsesOracle(_usesOracle);

        // Interactions
        IERC20(_vaultAsset).forceApprove(_vault, type(uint256).max);
        _approveTokenForSwap(_asset);
        _approveTokenForSwap(_vaultAsset);
    }

    // TODO: not sure exactly which role to assign here
    function setOracle(address token, address oracle) external onlyManagement {
        _setOracle(token, oracle);
    }

    // TODO: not sure exactly which role to assign here
    function setUsesOracle(bool _usesOracle) external onlyManagement {
        _setUsesOracle(_usesOracle);
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
        _setSwapParameters(asset, VAULT_ASSET, deploySwapParams, freeSwapParams, _swapTolerance);
    }

    function _deployFunds(uint256 _amount) internal override {
        (uint256 vaultAssetPrice, uint256 strategyAssetPrice) = _getPrices(VAULT_ASSET, asset);
        // Expected amount of tokens to receive from the swap
        uint256 expectedAmount = _calculateExpectedAmount(
            strategyAssetPrice, vaultAssetPrice, TokenizedStrategy.decimals(), vaultAssetDecimals, _amount
        );
        console.log("fromAmount: ", _amount);
        console.log("expectedAmount: ", expectedAmount);

        uint256 swapResult = _swap(_assetDeploySwapParams, _amount, expectedAmount, address(this));

        // check if we got less than the expected amount
        console.log("after swap token Balance: ", swapResult);

        // deposit _amount into vault if the swap was successful
        totalOwnedUnderlying4626Shares += IERC4626(VAULT).deposit(swapResult, address(this));
    }

    function _freeFunds(uint256 _amount) internal override {
        // Find withdrawer's allocation of total ysd shares
        uint256 vaultSharesToWithdraw = totalOwnedUnderlying4626Shares * _amount / TokenizedStrategy.totalAssets();
        // Effects
        // Total vault shares that strategy has deposited into the vault
        totalOwnedUnderlying4626Shares -= vaultSharesToWithdraw;
        // Interactions
        uint256 _withdrawnVaultAssetAmount = IERC4626(VAULT).redeem(vaultSharesToWithdraw, address(this), address(this));
        console.log("redeem amount: ", _withdrawnVaultAssetAmount);
        (uint256 vaultAssetPrice, uint256 strategyAssetPrice) = _getPrices(VAULT_ASSET, asset);
        console.log("strategyAssetPrice: ", strategyAssetPrice, "vaultAssetPrice: ", vaultAssetPrice);
        // Expected amount of tokens to receive from the swap
        uint256 expectedAmount = _calculateExpectedAmount(
            vaultAssetPrice,
            strategyAssetPrice,
            vaultAssetDecimals,
            TokenizedStrategy.decimals(),
            _withdrawnVaultAssetAmount
        );

        uint256 swapResult = _swap(_assetFreeSwapParams, _withdrawnVaultAssetAmount, expectedAmount, address(this));

        // check if we got less than the expected amount
        console.log("after swap token Balance: ", swapResult);
        console.log("expected swap amount    : ", expectedAmount);
    }

    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // We have no harvesting to do so just report the total assets held in the underlying strategy
        // Captures any changes in value in the underlying vault
        uint256 underlyingVaultAssets = IERC4626(VAULT).convertToAssets(totalOwnedUnderlying4626Shares);
        // Swap this amount in valut asset to get strategy asset amount
        (uint256 vaultAssetPrice, uint256 strategyAssetPrice) = _getPrices(VAULT_ASSET, asset);
        /// @dev this always returns the worst possible exchange as it is used for the minimum amount to
        /// receive in the swap. TODO may be to change this behavior to have more accurate accounting
        return _calculateExpectedAmount(
            vaultAssetPrice, strategyAssetPrice, vaultAssetDecimals, TokenizedStrategy.decimals(), underlyingVaultAssets
        );
    }
}

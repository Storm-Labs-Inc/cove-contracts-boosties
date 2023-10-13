// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { BaseTokenizedStrategy } from "src/deps/yearn/tokenized-strategy/BaseTokenizedStrategy.sol";
import { StrategyAssetSwap } from "src/strategies/StrategyAssetSwap.sol";
import { Errors } from "../libraries/Errors.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IChainLinkOracle } from "src/interfaces/IChainLinkOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 as console } from "forge-std/console2.sol";

contract TokenizedStrategyAssetSwap is StrategyAssetSwap, BaseTokenizedStrategy {
    // Libraries
    using SafeERC20 for IERC20Metadata;

    // Immutable storage variables
    address public immutable vault;
    address public immutable vaultAsset;

    // Storage variables
    bool public usesOracle;

    constructor(
        address _asset,
        address _vault,
        address _curveRouter,
        bool _usesOracle
    )
        StrategyAssetSwap(_curveRouter)
        BaseTokenizedStrategy(_asset, "Tokenized Asset Swap Strategy")
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
        vault = _vault;
        vaultAsset = _vaultAsset;
        usesOracle = _usesOracle;

        // Interactions
        IERC20Metadata(_vaultAsset).approve(_vault, type(uint256).max);
    }

    // TODO: not sure exactly which role to assign here
    function setOracle(address token, address oracle) external onlyManagement {
        _setOracle(token, oracle);
    }

    // TODO: not sure exactly which role to assign here
    function setSwapParameters(
        address strategyAsset,
        CurveSwapParams memory deploySwapParams,
        CurveSwapParams memory freeSwapParams,
        uint256 _slippageTolerance,
        uint256 _timeTolerance
    )
        external
        onlyManagement
    {
        address _vaultAsset = vaultAsset;
        // Checks
        // Check if the given asset is the same as the given vault's asset
        if (strategyAsset == _vaultAsset) {
            revert Errors.VaultAssetDoesNotDiffer();
        }
        // Check if the given asset is the same as the underlying strategy asset
        if (strategyAsset != TokenizedStrategy.asset()) {
            revert Errors.AssetDoesNotMatchStrategyAsset();
        }

        // Innteractions
        _setSwapParameters(
            strategyAsset, _vaultAsset, deploySwapParams, freeSwapParams, _slippageTolerance, _timeTolerance
        );
    }

    function _getPrices() internal view returns (uint256, uint256) {
        if (usesOracle) {
            return (_getOraclePrices(TokenizedStrategy.asset(), vaultAsset));
        } else {
            return (1, 1);
        }
    }

    function _deployFunds(uint256 _amount) internal override {
        (uint256 strategyAssetPrice, uint256 vaultAssetPrice) = _getPrices();
        // Expected amount of tokens to receive from the swap
        uint256 expectedAmount = _calculateExpectedAmount(
            strategyAssetPrice,
            vaultAssetPrice,
            TokenizedStrategy.decimals(),
            IERC20Metadata(vaultAsset).decimals(),
            _amount
        );
        console.log("fromAmount: ", _amount);
        console.log("expectedAmount: ", expectedAmount);

        uint256 swapResult = _swap(_assetDeploySwapParams, _amount, expectedAmount, address(this));

        // check if we got less than the expected amount
        console.log("after swap token Balance: ", swapResult);

        // deposit _amount into vault if the swap was successful
        IERC4626(vault).deposit(swapResult, address(this));
    }

    function _freeFunds(uint256 _amount) internal override {
        IERC4626 _vault = IERC4626(vault);
        uint256 assetDecimals = TokenizedStrategy.decimals();
        // Find percentage of total assets in this amount
        uint256 allocation = _amount * assetDecimals / TokenizedStrategy.totalAssets();
        // Total vault shares that strategy has deposited into the vault
        uint256 totalUnderlyingVaultShares = _vault.balanceOf(address(this));
        // Find withdrawer's allocation of total ysd shares
        uint256 vaultSharesToWithdraw = totalUnderlyingVaultShares * allocation / assetDecimals;
        // Withdraw from vault using redeem
        uint256 _withdrawnVaultAssetAmount = _vault.redeem(vaultSharesToWithdraw, address(this), address(this));
        console.log("redeem amount: ", _withdrawnVaultAssetAmount);
        (uint256 strategyAssetPrice, uint256 vaultAssetPrice) = _getPrices();
        console.log("strategyAssetPrice: ", strategyAssetPrice, "vaultAssetPrice: ", vaultAssetPrice);
        // Expected amount of tokens to receive from the swap
        uint256 expectedAmount = _calculateExpectedAmount(
            vaultAssetPrice,
            strategyAssetPrice,
            IERC20Metadata(vaultAsset).decimals(),
            assetDecimals,
            _withdrawnVaultAssetAmount
        );

        uint256 swapResult = _swap(_assetFreeSwapParams, _withdrawnVaultAssetAmount, expectedAmount, address(this));

        // check if we got less than the expected amount
        console.log("after swap token Balance: ", swapResult);
        console.log("expected swap amount    : ", expectedAmount);
    }

    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // We have no harvesting to do so just report the total assets held in the underlying strategy
        IERC4626 _vault = IERC4626(vault);
        return _vault.convertToAssets(_vault.balanceOf(address(this)));
    }
}

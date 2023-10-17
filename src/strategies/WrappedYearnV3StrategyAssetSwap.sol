// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import { BaseTokenizedStrategy } from "src/deps/yearn/tokenized-strategy/BaseTokenizedStrategy.sol";
import { StrategyAssetSwap, CurveRouterSwapper } from "src/strategies/StrategyAssetSwap.sol";
import { Errors } from "../libraries/Errors.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IChainLinkOracle } from "src/interfaces/IChainLinkOracle.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 as console } from "forge-std/console2.sol";

contract WrappedYearnV3StrategyAssetSwap is StrategyAssetSwap, BaseTokenizedStrategy {
    // Libraries
    using SafeERC20 for IERC20Metadata;

    // Immutable storage variables
    address public immutable vault;
    address public immutable vaultAsset;
    address public immutable yearnStakingDelegate;
    address public immutable dYFI;

    // Storage variables
    CurveSwapParams internal _harvestSwapParams;
    uint256 public totalOwnedUnderlying4626Shares;
    uint256 public vaultAssetDecimals;

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
    {
        // Checks
        // Check for zero addresses
        if (_asset == address(0) || _vault == address(0) || _yearnStakingDelegate == address(0)) {
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
        vaultAssetDecimals = IERC20Metadata(_vaultAsset).decimals();
        yearnStakingDelegate = _yearnStakingDelegate;
        _setUsesOracle(_usesOracle);
        dYFI = _dYFI;

        // Interactions
        _approveTokenForSwap(_dYFI);
        _approveTokenForSwap(_asset);
        _approveTokenForSwap(_vaultAsset);
        IERC20Metadata(_vaultAsset).approve(_vault, type(uint256).max);
        IERC20Metadata(_vault).approve(_yearnStakingDelegate, type(uint256).max);
    }

    // TODO: not sure exactly which role to assign here
    function setOracle(address token, address oracle) external onlyManagement {
        _setOracle(token, oracle);
    }

    // TODO: not sure exactly which role to assign here
    function setSwapParameters(
        CurveSwapParams memory deploySwapParams,
        CurveSwapParams memory freeSwapParams,
        uint256 _slippageTolerance,
        uint256 _timeTolerance
    )
        external
        onlyManagement
    {
        // Interactions
        _setSwapParameters(
            TokenizedStrategy.asset(), vaultAsset, deploySwapParams, freeSwapParams, _slippageTolerance, _timeTolerance
        );
    }

    function setHarvestSwapParams(CurveSwapParams memory curveSwapParams) external onlyManagement {
        // Checks (includes external view calls)
        _validateSwapParams(curveSwapParams, dYFI, asset);

        // effects
        _harvestSwapParams = curveSwapParams;
    }

    function _deployFunds(uint256 _amount) internal override {
        address _vault = vault;
        (uint256 vaultAssetPrice, uint256 strategyAssetPrice) = _getPrices(vaultAsset, TokenizedStrategy.asset());
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
        uint256 shares = IERC4626(_vault).deposit(swapResult, address(this));
        totalOwnedUnderlying4626Shares += shares;
        IYearnStakingDelegate(yearnStakingDelegate).depositToGauge(_vault, shares);
    }

    function _freeFunds(uint256 _amount) internal override {
        address _vault = vault;
        uint256 assetDecimals = TokenizedStrategy.decimals();
        IYearnStakingDelegate _yearnStakingDelegate = IYearnStakingDelegate(yearnStakingDelegate);
        // Total vault shares that strategy has deposited into the vault
        uint256 totalUnderlyingVaultShares = uint256(_yearnStakingDelegate.userInfo(address(this), _vault).balance);
        // Find withdrawer's allocation of total ysd shares
        uint256 vaultSharesToWithdraw = totalUnderlyingVaultShares * _amount / TokenizedStrategy.totalAssets();
        // Effects
        totalOwnedUnderlying4626Shares -= vaultSharesToWithdraw;
        // Withdraw that amount of vaul tokens from gauge via YSD
        _yearnStakingDelegate.withdrawFromGauge(_vault, vaultSharesToWithdraw);
        // Withdraw from vault using redeem
        uint256 _withdrawnVaultAssetAmount = IERC4626(vault).redeem(vaultSharesToWithdraw, address(this), address(this));
        console.log("redeem amount: ", _withdrawnVaultAssetAmount);
        (uint256 vaultAssetPrice, uint256 strategyAssetPrice) = _getPrices(vaultAsset, TokenizedStrategy.asset());
        console.log("strategyAssetPrice: ", strategyAssetPrice, "vaultAssetPrice: ", vaultAssetPrice);
        // Expected amount of tokens to receive from the swap
        uint256 expectedAmount = _calculateExpectedAmount(
            vaultAssetPrice, strategyAssetPrice, vaultAssetDecimals, assetDecimals, _withdrawnVaultAssetAmount
        );

        uint256 swapResult = _swap(_assetFreeSwapParams, _withdrawnVaultAssetAmount, expectedAmount, address(this));

        // check if we got less than the expected amount
        console.log("after swap token Balance: ", swapResult);
        console.log("expected swap amount    : ", expectedAmount);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        address _vault = vault;
        address _ysd = yearnStakingDelegate;
        address _vaultAsset = vaultAsset;

        // ysd.harvest() <- harvests gauge rewards (dFYI) and transfers them to this contract
        uint256 dYFIBalance = IYearnStakingDelegate(_ysd).harvest(_vault);
        // swap dYFI -> ETH -> vaultAsset if rewards were harvested

        if (dYFIBalance > 0) {
            if (!TokenizedStrategy.isShutdown()) {
                uint256 receivedTokens = _swap(_harvestSwapParams, dYFIBalance, 0, address(this));
                _deployFunds(receivedTokens);
            }
        }

        // TODO: below may not be accurate accounting as the underlying vault may not have realized gains/losses
        // additionally profits may have been awarded but not fully unlocked yet, these are concerns to be investigated
        // off-chain by management in the timing of calling _harvestAndReport

        // Captures any changes in value in the underlying vault
        uint256 underlyingVaultAssets = IERC4626(_vault).convertToAssets(totalOwnedUnderlying4626Shares);
        // Swap this amount in valut asset to get strategy asset amount
        (uint256 vaultAssetPrice, uint256 strategyAssetPrice) = _getPrices(_vaultAsset, TokenizedStrategy.asset());
        /// @dev this always returns the worst possible exchange as it is used for the minimum amount to
        /// receive in the swap. TODO may be to change this behavior to have more accurate accounting
        return _calculateExpectedAmount(
            vaultAssetPrice, strategyAssetPrice, vaultAssetDecimals, TokenizedStrategy.decimals(), underlyingVaultAssets
        );
    }
}

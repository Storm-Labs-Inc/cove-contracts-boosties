// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { BaseTokenizedStrategy } from "src/deps/yearn/tokenized-strategy/BaseTokenizedStrategy.sol";
import { WrappedYearnV3Strategy } from "./WrappedYearnV3Strategy.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { IStrategy } from "src/interfaces/deps/yearn/tokenized-strategy/IStrategy.sol";
import { Errors } from "../libraries/Errors.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IERC20Metadata } from "@openzeppelin-5.0/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 as console } from "forge-std/console2.sol";

contract WrappedYearnV3StrategyAssetSwapStatic is BaseTokenizedStrategy, CurveRouterSwapper {
    // Libraries
    using SafeERC20 for IERC20Metadata;

    // Constant storage variables
    uint256 public constant SLIPPAGE_TOLERANCE_PRECISION = 1e5;
    uint256 public constant MIN_SLIPPAGE_TOLERANCE = 99_000;

    // Immutable storage variables
    address public immutable vault;
    address public immutable vaultAsset;
    address public immutable yearnStakingDelegate;
    address public immutable dYFI;

    // Storage variables
    uint256 public slippageTolerance = 99_500;
    CurveSwapParams internal _harvestSwapParams;
    CurveSwapParams internal _assetDeploySwapParams;
    CurveSwapParams internal _assetFreeSwapParams;

    constructor(
        address _asset,
        address _vault,
        address _yearnStakingDelegate,
        address _dYFI,
        address _curveRouter
    )
        BaseTokenizedStrategy(_asset, "Wrapped YearnV3 Asset Swap (Oracle) Strategy")
        CurveRouterSwapper(_curveRouter)
    {
        // Checks
        // Check for zero addresses
        if (_asset == address(0) || _vault == address(0) || _yearnStakingDelegate == address(0) || _dYFI == address(0))
        {
            revert Errors.ZeroAddress();
        }
        // Check if the given asset is the same as the given vault's asset
        address _vaultAsset = IVault(_vault).asset();
        if (_asset == _vaultAsset) {
            revert Errors.VaultAssetDoesNotDiffer();
        }

        // Effects
        // Set storage variable values
        vault = _vault;
        vaultAsset = _vaultAsset;
        dYFI = _dYFI;
        yearnStakingDelegate = _yearnStakingDelegate;

        // Interactions
        _approveTokenForSwap(_dYFI);
        _approveTokenForSwap(_asset);
        _approveTokenForSwap(_vaultAsset);
        IERC20Metadata(_vaultAsset).approve(_vault, type(uint256).max);
        IERC20Metadata(_vault).approve(_yearnStakingDelegate, type(uint256).max);
    }

    // TODO: not sure exactly which role to assign here
    function setSwapParameters(
        CurveSwapParams memory deploySwapParams,
        CurveSwapParams memory freeSwapParams,
        uint256 _slippageTolerance
    )
        external
        onlyManagement
    {
        // Checks
        // Checks (includes external view calls)
        if (_slippageTolerance > SLIPPAGE_TOLERANCE_PRECISION || _slippageTolerance < MIN_SLIPPAGE_TOLERANCE) {
            revert Errors.SlippageToleranceNotInRange(_slippageTolerance);
        }
        address _asset = asset;
        address _vaultAsset = vaultAsset;
        _validateSwapParams(deploySwapParams, _asset, _vaultAsset);
        _validateSwapParams(freeSwapParams, _vaultAsset, _asset);

        // Effects
        _assetDeploySwapParams = deploySwapParams;
        _assetFreeSwapParams = freeSwapParams;
        slippageTolerance = _slippageTolerance;
    }

    function _calculateExpectedAmount(
        uint256 fromDecimal,
        uint256 toDecimal,
        uint256 fromAmount
    )
        internal
        view
        returns (uint256)
    {
        // Expected amount of tokens to receive from the swap
        return (fromAmount * 10 ** (18 - fromDecimal)) * slippageTolerance / SLIPPAGE_TOLERANCE_PRECISION
            / 10 ** (18 - toDecimal);
    }

    function _deployFunds(uint256 _amount) internal override {
        address _vault = vault;
        // Expected amount of tokens to receive from the swap
        uint256 expectedAmount =
            _calculateExpectedAmount(IERC20Metadata(asset).decimals(), IERC20Metadata(vaultAsset).decimals(), _amount);

        uint256 swapResult = _swap(_assetDeploySwapParams, _amount, expectedAmount, address(this));

        // check if we got less than the expected amount
        console.log("after swap token Balance: ", swapResult);
        console.log("expected swap amount    : ", expectedAmount);

        // deposit _amount into vault if the swap was successful
        uint256 shares = IVault(_vault).deposit(swapResult, address(this));
        IYearnStakingDelegate(yearnStakingDelegate).depositToGauge(_vault, shares);
    }

    function _freeFunds(uint256 _amount) internal override {
        address _vault = vault;
        uint256 assetDecimals = IERC20Metadata(asset).decimals();
        IYearnStakingDelegate _yearnStakingDelegate = IYearnStakingDelegate(yearnStakingDelegate);
        // Find percentage of total assets is this amount
        uint256 allocation = _amount * assetDecimals / IStrategy(address(this)).totalAssets();
        // Total vault shares that wStrat has deposited into ysd
        uint256 totalUnderlyingVaultShares = uint256(_yearnStakingDelegate.userInfo(address(this), _vault).balance);
        // Find withdrawer's allocation of total ysd shares
        uint256 vaultSharesToWithdraw = totalUnderlyingVaultShares * allocation / assetDecimals;
        // Withdraw from gauge via YSD
        _yearnStakingDelegate.withdrawFromGauge(_vault, vaultSharesToWithdraw);
        // Withdraw from vault using redeem
        uint256 _withdrawnVaultAssetAmount = IVault(_vault).redeem(vaultSharesToWithdraw, address(this), address(this));
        // Expected amount of tokens to receive from the swap
        uint256 expectedAmount =
            _calculateExpectedAmount(IERC20Metadata(vaultAsset).decimals(), assetDecimals, _withdrawnVaultAssetAmount);

        uint256 swapResult = _swap(_assetFreeSwapParams, _withdrawnVaultAssetAmount, expectedAmount, address(this));

        // check if we got less than the expected amount
        console.log("after swap token Balance: ", swapResult);
        console.log("expected swap amount    : ", expectedAmount);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) { }
}

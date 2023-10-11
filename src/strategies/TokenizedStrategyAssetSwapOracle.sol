// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { BaseTokenizedStrategy } from "src/deps/yearn/tokenized-strategy/BaseTokenizedStrategy.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { Errors } from "../libraries/Errors.sol";
import { IERC4626 } from "@openzeppelin-5.0/contracts/interfaces/IERC4626.sol";
import { IChainLinkOracle } from "src/interfaces/IChainLinkOracle.sol";
import { IERC20Metadata } from "@openzeppelin-5.0/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 as console } from "forge-std/console2.sol";

contract TokenizedStrategyAssetSwapOracle is BaseTokenizedStrategy, CurveRouterSwapper {
    // Libraries
    using SafeERC20 for IERC20Metadata;

    // Constant storage variables
    uint256 private constant _SLIPPAGE_TOLERANCE_PRECISION = 1e5;
    uint256 private constant _MIN_SLIPPAGE_TOLERANCE = 99_000;
    uint256 private constant _MAX_TIME_TOLERANCE = 2 days;

    // Immutable storage variables
    address public immutable vault;
    address public immutable vaultAsset;

    // Storage variables
    uint256 public slippageTolerance = 99_500;
    uint256 public timeTolerance = 6 hours;
    CurveSwapParams internal _harvestSwapParams;
    CurveSwapParams internal _assetDeploySwapParams;
    CurveSwapParams internal _assetFreeSwapParams;

    mapping(address token => address) public oracles;

    constructor(
        address _asset,
        address _vault,
        address _curveRouter
    )
        BaseTokenizedStrategy(_asset, "Tokenized Asset Swap (Oracle) Strategy")
        CurveRouterSwapper(_curveRouter)
    {
        // Checks
        // Check for zero addresses
        if (_asset == address(0) || _vault == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Check if the given asset is the same as the given vault's asset
        address _vaultAsset = IERC4626(_vault).asset();
        if (_asset == _vaultAsset) {
            revert Errors.VaultAssetDoesNotDiffer();
        }

        // Effects
        // Set storage variable values
        vault = _vault;
        vaultAsset = _vaultAsset;

        // Interactions
        _approveTokenForSwap(_asset);
        _approveTokenForSwap(_vaultAsset);
        IERC20Metadata(_vaultAsset).approve(_vault, type(uint256).max);
    }

    // TODO: not sure exactly which role to assign here
    function setOracle(address token, address oracle) external onlyManagement {
        // Checks
        if (token == address(0) || oracle == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        oracles[token] = oracle;
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
        // Checks
        // Checks (includes external view calls)
        if (_slippageTolerance > _SLIPPAGE_TOLERANCE_PRECISION || _slippageTolerance < _MIN_SLIPPAGE_TOLERANCE) {
            revert Errors.SlippageToleranceNotInRange(_slippageTolerance);
        }
        if (_timeTolerance > _MAX_TIME_TOLERANCE) {
            revert Errors.TimeToleranceNotInRange(_timeTolerance);
        }
        address _asset = asset;
        address _vaultAsset = vaultAsset;
        _validateSwapParams(deploySwapParams, _asset, _vaultAsset);
        _validateSwapParams(freeSwapParams, _vaultAsset, _asset);

        // Effects
        _assetDeploySwapParams = deploySwapParams;
        _assetFreeSwapParams = freeSwapParams;
        slippageTolerance = _slippageTolerance;
        timeTolerance = _timeTolerance;
    }

    function _calculateExpectedAmount(
        uint256 fromPrice,
        uint256 toPrice,
        uint256 fromDecimal,
        uint256 toDecimal,
        uint256 fromAmount
    )
        internal
        view
        returns (uint256)
    {
        // Expected amount of tokens to receive from the swap
        return ((fromAmount * fromPrice) * 10 ** (18 - fromDecimal)) * slippageTolerance / toPrice
            / _SLIPPAGE_TOLERANCE_PRECISION / 10 ** (18 - toDecimal);
    }

    function _deployFunds(uint256 _amount) internal override {
        (uint256 assetPrice, uint256 vaultAssetPrice) = _getOraclePrices();
        // Expected amount of tokens to receive from the swap
        uint256 expectedAmount = _calculateExpectedAmount(
            assetPrice, vaultAssetPrice, TokenizedStrategy.decimals(), IERC20Metadata(vaultAsset).decimals(), _amount
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
        (uint256 assetPrice, uint256 vaultAssetPrice) = _getOraclePrices();
        console.log("assetPrice: ", assetPrice, "vaultAssetPrice: ", vaultAssetPrice);
        // Expected amount of tokens to receive from the swap
        uint256 expectedAmount = _calculateExpectedAmount(
            vaultAssetPrice,
            assetPrice,
            IERC20Metadata(vaultAsset).decimals(),
            assetDecimals,
            _withdrawnVaultAssetAmount
        );

        uint256 swapResult = _swap(_assetFreeSwapParams, _withdrawnVaultAssetAmount, expectedAmount, address(this));

        // check if we got less than the expected amount
        console.log("after swap token Balance: ", swapResult);
        console.log("expected swap amount    : ", expectedAmount);
    }

    /**
     * Returns the latest price from the oracle and the timestamp of the price
     * @return assetPrice the price of the asset this strategy accepts
     * @return vaultAssetPrice the price of the vault asset this strategy will deposit into the vault
     */
    function _getOraclePrices() internal view returns (uint256 assetPrice, uint256 vaultAssetPrice) {
        address _asset = asset;
        address _vaultAsset = vaultAsset;
        address _assetOracle = oracles[_asset];
        address _vaultAssetOracle = oracles[_vaultAsset];
        // Checks
        if (_assetOracle == address(0)) {
            revert Errors.OracleNotSet(_asset);
        }
        if (_vaultAssetOracle == address(0)) {
            revert Errors.OracleNotSet(_vaultAsset);
        }

        // Interactions
        // get the price for each token from the oracle.
        (, int256 quotedAssetPrice,, uint256 fromTimeStamp,) = IChainLinkOracle(_assetOracle).latestRoundData();
        (, int256 quotedVaultAssetPrice,, uint256 toTimeStamp,) = IChainLinkOracle(_vaultAssetOracle).latestRoundData();

        // check if oracles are outdated
        uint256 _timeTolerance = timeTolerance;
        if (block.timestamp - fromTimeStamp > _timeTolerance || block.timestamp - toTimeStamp > _timeTolerance) {
            revert Errors.OracleOudated();
        }

        assetPrice = uint256(quotedAssetPrice);
        vaultAssetPrice = uint256(quotedVaultAssetPrice);
        console.log("quotedAssetPrice: ", assetPrice, "quotedVaultAssetPrice: ", vaultAssetPrice);
    }

    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // We have no harvesting to do so just report the total assets held in the underlying strategy
        IERC4626 _vault = IERC4626(vault);
        return _vault.convertToAssets(_vault.balanceOf(address(this)));
    }
}

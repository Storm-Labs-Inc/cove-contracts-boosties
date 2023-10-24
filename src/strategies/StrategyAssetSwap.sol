// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { IChainLinkOracle } from "src/interfaces/IChainLinkOracle.sol";
import { Errors } from "../libraries/Errors.sol";
import { console2 as console } from "forge-std/console2.sol";

abstract contract StrategyAssetSwap is CurveRouterSwapper {
    // Struct definitions
    struct SwapTolerance {
        uint128 slippageTolerance;
        uint128 timeTolerance;
    }

    // Constant storage variables
    uint256 internal constant _SLIPPAGE_TOLERANCE_PRECISION = 1e5;
    uint256 internal constant _MIN_SLIPPAGE_TOLERANCE = 99_000;
    uint256 internal constant _MAX_TIME_TOLERANCE = 2 days;

    // Storage variables
    SwapTolerance public swapTolerance;
    bool public usesOracle;

    CurveSwapParams internal _assetDeploySwapParams;
    CurveSwapParams internal _assetFreeSwapParams;

    mapping(address token => address) public oracles;

    function _setOracle(address token, address oracle) internal {
        // Checks
        if (token == address(0) || oracle == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        oracles[token] = oracle;
    }

    function _setUsesOracle(bool _usesOracle) internal {
        usesOracle = _usesOracle;
    }

    /**
     * Returns the latest price from the oracle for two assets
     */
    function _getOraclePrices(
        address asset0,
        address asset1
    )
        internal
        view
        returns (uint256 asset0Price, uint256 asset1Price)
    {
        // Checks
        // Cache variables
        address _asset0Oracle = oracles[asset0];
        address _asset1Oracle = oracles[asset1];
        // Will revert if oracle has not been set
        if (_asset0Oracle == address(0)) {
            revert Errors.OracleNotSet(asset0);
        }
        if (_asset1Oracle == address(0)) {
            revert Errors.OracleNotSet(asset1);
        }

        // Interactions
        // get the price for each token from the oracle.
        (, int256 quotedAsset0Price,, uint256 fromTimeStamp,) = IChainLinkOracle(_asset0Oracle).latestRoundData();
        (, int256 quotedAsset1Price,, uint256 toTimeStamp,) = IChainLinkOracle(_asset1Oracle).latestRoundData();

        // check if oracles are outdated
        uint256 _timeTolerance = swapTolerance.timeTolerance;
        if (block.timestamp - fromTimeStamp > _timeTolerance || block.timestamp - toTimeStamp > _timeTolerance) {
            revert Errors.OracleOutdated();
        }

        console.log(
            "quotedAsset0Price: ", uint256(quotedAsset0Price), "quotedAsset1Price: ", uint256(quotedAsset1Price)
        );
        return (uint256(quotedAsset0Price), uint256(quotedAsset1Price));
    }

    function _getPrices(address strategyAsset, address vaultAsset) internal view returns (uint256, uint256) {
        return (usesOracle ? _getOraclePrices(strategyAsset, vaultAsset) : (1, 1));
    }

    /// @notice Calculates the expected amount from a swap
    /// @dev for prices, if not using an oracle, these can be inferred to be 1
    /// @param fromPrice The price of the token to swap from
    /// @param toPrice The price of the token to swap to
    /// @param fromDecimal The decimal of the token to swap from
    /// @param toDecimal The decimal of the token to swap to
    /// @param fromAmount The amount of tokens to swap from
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
        return ((fromAmount * fromPrice) * 10 ** (18 - fromDecimal)) * swapTolerance.slippageTolerance / toPrice
            / _SLIPPAGE_TOLERANCE_PRECISION / 10 ** (18 - toDecimal);
    }

    function _setSwapParameters(
        address strategyAsset,
        address vaultAsset,
        CurveSwapParams memory deploySwapParams,
        CurveSwapParams memory freeSwapParams,
        SwapTolerance memory _swapTolerance
    )
        internal
    {
        // Cache variables
        // Convert slippage tolerance to uint256 for calculations
        uint256 _slippageTolerance = uint256(_swapTolerance.slippageTolerance);
        // Checks (includes external view calls)
        if (_slippageTolerance > _SLIPPAGE_TOLERANCE_PRECISION || _slippageTolerance < _MIN_SLIPPAGE_TOLERANCE) {
            revert Errors.SlippageToleranceNotInRange(_swapTolerance.slippageTolerance);
        }
        if (_swapTolerance.timeTolerance > _MAX_TIME_TOLERANCE) {
            revert Errors.TimeToleranceNotInRange(_swapTolerance.timeTolerance);
        }
        _validateSwapParams(deploySwapParams, strategyAsset, vaultAsset);
        _validateSwapParams(freeSwapParams, vaultAsset, strategyAsset);

        // Effects
        _assetDeploySwapParams = deploySwapParams;
        _assetFreeSwapParams = freeSwapParams;
        swapTolerance = _swapTolerance;
    }
}

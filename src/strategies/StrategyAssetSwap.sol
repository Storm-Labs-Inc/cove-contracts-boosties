// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { IChainLinkOracle } from "src/interfaces/IChainLinkOracle.sol";
import { Errors } from "../libraries/Errors.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 as console } from "forge-std/console2.sol";

abstract contract StrategyAssetSwap is CurveRouterSwapper {
    // TODO add oracle functions here
    // Constant storage variables
    uint256 internal constant _SLIPPAGE_TOLERANCE_PRECISION = 1e5;
    uint256 internal constant _MIN_SLIPPAGE_TOLERANCE = 99_000;
    uint256 internal constant _MAX_TIME_TOLERANCE = 2 days;

    // Storage variables
    uint256 public slippageTolerance = 99_500;
    uint256 public timeTolerance = 6 hours;

    CurveSwapParams internal _assetDeploySwapParams;
    CurveSwapParams internal _assetFreeSwapParams;

    mapping(address token => address) public oracles;

    constructor(address _curveRouter) CurveRouterSwapper(_curveRouter) { }

    function _setOracle(address token, address oracle) internal {
        // Checks
        if (token == address(0) || oracle == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        oracles[token] = oracle;
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
        returns (uint256 asset1Price, uint256 asset2Price)
    {
        address _asset = asset0;
        address _vaultAsset = asset1;
        // Checks
        // Will revert if oracle has not been set
        address _asset0Oracle = oracles[_asset];
        address _asset1Oracle = oracles[_vaultAsset];
        if (_asset0Oracle == address(0)) {
            revert Errors.OracleNotSet(_asset);
        }
        if (_asset1Oracle == address(0)) {
            revert Errors.OracleNotSet(_vaultAsset);
        }

        // Interactions
        // get the price for each token from the oracle.
        (, int256 quotedAsset0Price,, uint256 fromTimeStamp,) = IChainLinkOracle(_asset0Oracle).latestRoundData();
        (, int256 quotedAsset1Price,, uint256 toTimeStamp,) = IChainLinkOracle(_asset1Oracle).latestRoundData();

        // check if oracles are outdated
        uint256 _timeTolerance = timeTolerance;
        if (block.timestamp - fromTimeStamp > _timeTolerance || block.timestamp - toTimeStamp > _timeTolerance) {
            revert Errors.OracleOutdated();
        }

        console.log(
            "quotedAsset1Price: ", uint256(quotedAsset0Price), "quotedAsset2Price: ", uint256(quotedAsset1Price)
        );
        return (uint256(quotedAsset0Price), uint256(quotedAsset1Price));
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
        return ((fromAmount * fromPrice) * 10 ** (18 - fromDecimal)) * slippageTolerance / toPrice
            / _SLIPPAGE_TOLERANCE_PRECISION / 10 ** (18 - toDecimal);
    }

    function _setSwapParameters(
        address strategyAsset,
        address vaultAsset,
        CurveSwapParams memory deploySwapParams,
        CurveSwapParams memory freeSwapParams,
        uint256 _slippageTolerance,
        uint256 _timeTolerance
    )
        internal
    {
        // Checks (includes external view calls)
        if (_slippageTolerance > _SLIPPAGE_TOLERANCE_PRECISION || _slippageTolerance < _MIN_SLIPPAGE_TOLERANCE) {
            revert Errors.SlippageToleranceNotInRange(_slippageTolerance);
        }
        if (_timeTolerance > _MAX_TIME_TOLERANCE) {
            revert Errors.TimeToleranceNotInRange(_timeTolerance);
        }
        // Check for zero addresses
        if (strategyAsset == address(0) || vaultAsset == address(0)) {
            revert Errors.ZeroAddress();
        }
        address _asset = strategyAsset;
        address _vaultAsset = vaultAsset;
        _validateSwapParams(deploySwapParams, _asset, _vaultAsset);
        _validateSwapParams(freeSwapParams, _vaultAsset, _asset);

        // Effects
        _assetDeploySwapParams = deploySwapParams;
        _assetFreeSwapParams = freeSwapParams;
        slippageTolerance = _slippageTolerance;
        timeTolerance = _timeTolerance;

        // Interactions
        _approveTokenForSwap(_asset);
        _approveTokenForSwap(_vaultAsset);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { WrappedYearnV3Strategy } from "./WrappedYearnV3Strategy.sol";
import { CurveSwapper } from "../CurveSwapper.sol";
import { Errors } from "../libraries/Errors.sol";
import { IVault } from "src/interfaces/yearn/yearn-vaults-v3/IVault.sol";
import { IChainLinkOracle } from "src/interfaces/IChainLinkOracle.sol";
import { IERC20Metadata } from "@openzeppelin-5.0/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 as console } from "forge-std/console2.sol";

contract WrappedYearnV3StrategyCurveSwapper is WrappedYearnV3Strategy, CurveSwapper {
    address public immutable curvePoolAddress;
    address public vaultAsset;
    uint256 public slippageTolerance = 99_500;
    uint256 public constant SLIPPAGE_TOLERANCE_PRECISION = 1e5;
    uint256 public constant MIN_SLIPPAGE_TOLERANCE = 99_000;
    uint256 public timeTolerance = 6 hours;
    uint256 public constant MAX_TIME_TOLERANCE = 2 days;

    using SafeERC20 for IERC20Metadata;

    mapping(address token => address) public oracles;

    constructor(address _asset, address curvePool) WrappedYearnV3Strategy(_asset) {
        // Checks
        if (curvePool == address(0) || _asset == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        curvePoolAddress = curvePool;
    }

    function setYieldSource(address v3VaultAddress) external override onlyManagement {
        // Checks
        address _vaultAsset = IVault(v3VaultAddress).asset();
        (int128 i, int128 j) = _getTokenIndexes(curvePoolAddress, asset, IVault(v3VaultAddress).asset());
        if (i <= -1 || j <= -1) {
            revert Errors.TokenNotFoundInPool(_vaultAsset);
        }

        // Effects
        vaultAsset = _vaultAsset;
        vaultAddress = v3VaultAddress;

        // Interactions
        IERC20Metadata(_vaultAsset).approve(v3VaultAddress, type(uint256).max);
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
    function setSwapParameters(uint256 _slippageTolerance, uint256 _timeTolerance) external onlyManagement {
        // Checks
        if (_slippageTolerance >= SLIPPAGE_TOLERANCE_PRECISION || _slippageTolerance <= MIN_SLIPPAGE_TOLERANCE) {
            revert Errors.SlippageToleranceNotInRange(_slippageTolerance);
        }
        if (_timeTolerance > MAX_TIME_TOLERANCE) {
            revert Errors.TimeToleranceNotInRange(_timeTolerance);
        }

        // Effects
        slippageTolerance = _slippageTolerance;
        timeTolerance = _timeTolerance;
    }

    function _deployFunds(uint256 _amount) internal override {
        address _vaultAsset = vaultAsset;
        uint256 beforeBalance = IERC20Metadata(_vaultAsset).balanceOf(address(this));
        (uint256 fromPrice, uint256 toPrice) = _getOraclePrices();
        // Expected amount of tokens to receive from the swap
        uint256 expectedAmount = ((_amount * fromPrice) * 10 ** (18 - IERC20Metadata(asset).decimals()))
            * slippageTolerance / toPrice / SLIPPAGE_TOLERANCE_PRECISION;

        _swapFrom(curvePoolAddress, asset, _vaultAsset, _amount, 0);

        // get exact amount of tokens from the transfer denominated in 1e18
        uint256 afterTokenBalance = (IERC20Metadata(_vaultAsset).balanceOf(address(this)) - beforeBalance)
            * 10 ** (18 - IERC20Metadata(_vaultAsset).decimals());

        // check if we got less than the expected amount
        console.log("after swap token Balance: ", afterTokenBalance);
        console.log("expected swap amount    : ", expectedAmount);
        if (afterTokenBalance < expectedAmount) {
            revert Errors.SlippageTooHigh();
        }

        // deposit _amount into vault if the swap was successful
        IVault(vaultAddress).deposit(afterTokenBalance, yearnStakingDelegateAddress);
    }

    /**
     * Returns the latest price from the oracle and the timestamp of the price
     * @return fromPrice the price of the from asset
     * @return toPrice the price of the to asset
     */
    function _getOraclePrices() internal view returns (uint256 fromPrice, uint256 toPrice) {
        address _assetOracle = oracles[asset];
        address _vaultAssetOracle = oracles[vaultAsset];
        // Checks
        if (_assetOracle == address(0)) {
            revert Errors.OracleNotSet(asset);
        }
        if (_vaultAssetOracle == address(0)) {
            revert Errors.OracleNotSet(vaultAsset);
        }

        // Interactions
        // get the decimal adjusted price for each token from the oracle,
        (, int256 quotedFromPrice,, uint256 fromTimeStamp,) = IChainLinkOracle(_assetOracle).latestRoundData();
        (, int256 quotedToPrice,, uint256 toTimeStamp,) = IChainLinkOracle(_vaultAssetOracle).latestRoundData();
        console.log("quotedFromPrice: ", uint256(quotedFromPrice), "quotedToPrice: ", uint256(quotedToPrice));

        // check if oracles are outdated
        uint256 _timeTolerance = timeTolerance;
        if (block.timestamp - fromTimeStamp > _timeTolerance || block.timestamp - toTimeStamp > _timeTolerance) {
            revert Errors.OracleOudated();
        }
        return (uint256(quotedFromPrice), uint256(quotedToPrice));
    }
}

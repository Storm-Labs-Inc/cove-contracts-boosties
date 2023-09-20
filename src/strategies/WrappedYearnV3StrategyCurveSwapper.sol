// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { WrappedYearnV3Strategy } from "./WrappedYearnV3Strategy.sol";
import { CurveSwapper } from "../CurveSwapper.sol";
import { Errors } from "../libraries/Errors.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { IChainLinkOracle } from "src/interfaces/IChainLinkOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 as console } from "forge-std/console2.sol";

contract WrappedYearnV3StrategyCurveSwapper is WrappedYearnV3Strategy, CurveSwapper {
    address public immutable curvePoolAddress;
    address public vaultAsset;
    uint256 public slippageTolerance = 995;
    uint256 public constant SLIPPAGE_TOLERANCE_PRECISION = 1e4;
    uint256 public timeTolerance = 2 hours;

    using SafeERC20 for IERC20Metadata;

    mapping(address token => address oracle) public oracles;

    constructor(address _asset, address curvePool) WrappedYearnV3Strategy(_asset) {
        require(curvePool != address(0), "curve pool address cannot be 0");
        curvePoolAddress = curvePool;
    }

    function setYieldSource(address v3VaultAddress) external override onlyManagement {
        vaultAddress = v3VaultAddress;
        // checks address is an ERC4626 vault and exists
        address _vaultAsset = IVault(v3VaultAddress).asset();

        vaultAsset = _vaultAsset;
        (int128 i, int128 j) = _getTokenIndexes(curvePoolAddress, asset, IVault(v3VaultAddress).asset());
        require(i >= -1 && j >= -1, "token not found in curve pool");
        // Approve all future vault deposits
        IERC20Metadata(_vaultAsset).approve(v3VaultAddress, type(uint256).max);
    }

    // TODO: not sure exactly which role to assign here
    function setOracle(address token, address oracle) external onlyManagement {
        require(token != address(0), "token address cannot be 0");
        require(oracle != address(0), "oracle address cannot be 0");
        oracles[token] = oracle;
    }

    // TODO: not sure exactly which role to assign here
    function setSwapParameters(uint256 _slippageTolerance, uint256 _timeTolerance) external onlyManagement {
        require(_slippageTolerance <= SLIPPAGE_TOLERANCE_PRECISION, "slippage tolerance cannot be greater than 100%");
        require(_slippageTolerance >= 500, "slippage tolerance cannot be less than 50%");
        require(_timeTolerance != 0, "time tolerance cannot be 0");
        require(_timeTolerance <= 1 days, "time tolerance cannot be greater than 1 day");
        slippageTolerance = _slippageTolerance;
        timeTolerance = _timeTolerance;
    }

    function _deployFunds(uint256 _amount) internal override {
        address _vaultAsset = vaultAsset;
        uint256 beforeBalance = IERC20Metadata(_vaultAsset).balanceOf(address(this));

        // get the current price of the from and to assets
        uint256[2] memory prices = _getOraclePrices();
        // prices are always given in the precision as each other, eth pairs have 18 and non-eth pairs have 8

        // get the minimum we expect to reciceve adjusted by slippage tolerance
        // TODO: is there a better way to handle these decimals?
        uint256 expectedAmount = ((_amount * prices[0] / prices[1]) * slippageTolerance / SLIPPAGE_TOLERANCE_PRECISION)
            * 10 ** (18 - IERC20Metadata(asset).decimals());
        // swap _amount into underlying vault asset
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
     * @return prices array of the latest price for each token
     */
    function _getOraclePrices() internal view returns (uint256[2] memory prices) {
        require(oracles[asset] != address(0), "oracle for asset not set");
        require(oracles[vaultAsset] != address(0), "oracle for vault asset not set");
        require(timeTolerance != 0, "time tolerance not set");
        require(slippageTolerance != 0, "slippage tolerance not set");
        uint256 _timeTolerance = timeTolerance;
        // get the decimal adjusted price for each token from the oracle,
        (, int256 quotedFromPrice,, uint256 fromTimeStamp,) = IChainLinkOracle(oracles[asset]).latestRoundData();
        (, int256 quotedToPrice,, uint256 toTimeStamp,) = IChainLinkOracle(oracles[vaultAsset]).latestRoundData();
        console.log("quotedFromPrice: ", uint256(quotedFromPrice), "quotedToPrice: ", uint256(quotedToPrice));

        // check if oracles are outdated
        if (block.timestamp - fromTimeStamp > _timeTolerance || block.timestamp - toTimeStamp > _timeTolerance) {
            revert Errors.OracleOudated();
        }
        return ([uint256(quotedFromPrice), uint256(quotedToPrice)]);
    }
}

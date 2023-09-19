// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { WrappedYearnV3Strategy } from "./WrappedYearnV3Strategy.sol";
import { CurveSwapper } from "../CurveSwapper.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { IChainLinkOracle } from "src/interfaces/IChainLinkOracle.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// TODO: check with weeb how to handle this below interface
import { IERC20 } from "src/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 as console } from "forge-std/console2.sol";

contract WrappedYearnV3StrategyCurveSwapper is WrappedYearnV3Strategy, CurveSwapper {
    address public immutable curvePoolAddress;
    address public vaultAsset;

    using SafeERC20 for ERC20;

    // TODO: mainnet addresses just used for testing, will change to providing oracles on function call
    address public constant CHAINLINK_DAI_USD_MAINNET = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public constant CHAINLINK_USDC_USD_MAINNET = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    uint256 public constant SLIPPAGE_TOLERANCE = 995;
    uint256 public constant TIME_TOLERANCE = 1 days;

    error OracleOudated();
    error SlippgeTooHigh();

    constructor(address _asset, address curvePool) WrappedYearnV3Strategy(_asset) {
        require(curvePool != address(0), "curve pool address cannot be 0");
        curvePoolAddress = curvePool;
    }

    function setYieldSource(address v3VaultAddress) external override {
        vaultAddress = v3VaultAddress;
        address _vaultAsset = IVault(v3VaultAddress).asset();
        vaultAsset = _vaultAsset;
        (int128 i, int128 j) = _getTokenIndexes(curvePoolAddress, asset, IVault(v3VaultAddress).asset());
        require(i >= -1 && j >= -1, "token not found in curve pool");
        // Approve all future vault deposits
        ERC20(_vaultAsset).approve(v3VaultAddress, type(uint256).max);
    }

    function _deployFunds(uint256 _amount) internal override {
        address _vaultAsset = vaultAsset;
        uint256 beforeBalance = ERC20(_vaultAsset).balanceOf(address(this));

        // get the current price of the from and to assets
        uint256[2] memory prices = _getOraclePrices([CHAINLINK_USDC_USD_MAINNET, CHAINLINK_DAI_USD_MAINNET]);
        // prices are always given in the precision as each other, eth pairs have 18 and non-eth pairs have 8

        // get the minimum we expect to reciceve adjusted by slippage tolerance
        // TODO: is there a better way to handle these decimals?
        uint256 expectedAmount =
            ((_amount * prices[0] / prices[1]) * SLIPPAGE_TOLERANCE / 1000) * 10 ** (18 - IERC20(asset).decimals());
        // swap _amount into underlying vault asset
        _swapFrom(curvePoolAddress, asset, _vaultAsset, _amount, 0);

        // get exact amount of tokens from the transfer denominated in 1e18
        uint256 afterTokenBalance =
            (ERC20(_vaultAsset).balanceOf(address(this)) - beforeBalance) * 10 ** (18 - IERC20(_vaultAsset).decimals());

        // check if we got less than the expected amount
        console.log("afterTokenBalance: ", afterTokenBalance);
        console.log("expectedAmount   : ", expectedAmount);
        if (afterTokenBalance < expectedAmount) {
            revert SlippgeTooHigh();
        }

        // deposit _amount into vault if the swap was successful
        IVault(vaultAddress).deposit(afterTokenBalance, yearnStakingDelegateAddress);
    }

    /**
     * Returns the latest price from the oracle and the timestamp of the price
     * @param oracles address of the oracle of the from and to tokens
     * @return prices array of the latest price for each token
     */
    function _getOraclePrices(address[2] memory oracles) internal view returns (uint256[2] memory prices) {
        uint256 _timeTolerance = TIME_TOLERANCE;
        // get the decimal adjusted price for each token from the oracle,
        (, int256 quotedFromPrice,, uint256 fromTimeStamp,) = IChainLinkOracle(oracles[0]).latestRoundData();
        (, int256 quotedToPrice,, uint256 toTimeStamp,) = IChainLinkOracle(oracles[1]).latestRoundData();
        console.log("quotedFromPrice: ", uint256(quotedFromPrice), "quotedToPrice: ", uint256(quotedToPrice));

        // check if oracles are outdated
        if (block.timestamp - fromTimeStamp > _timeTolerance || block.timestamp - toTimeStamp > _timeTolerance) {
            revert OracleOudated();
        }
        return ([uint256(quotedFromPrice), uint256(quotedToPrice)]);
    }
}

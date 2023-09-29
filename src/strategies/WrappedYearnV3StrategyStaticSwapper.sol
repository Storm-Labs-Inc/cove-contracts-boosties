// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { WrappedYearnV3Strategy } from "./WrappedYearnV3Strategy.sol";
import { CurveSwapperOldPool } from "src/swappers/CurveSwapperOldPool.sol";
import { Errors } from "../libraries/Errors.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IERC20Metadata } from "@openzeppelin-5.0/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 as console } from "forge-std/console2.sol";

contract WrappedYearnV3StrategyStaticSwapper is WrappedYearnV3Strategy, CurveSwapperOldPool {
    address public curvePoolAddress;
    address public vaultAsset;
    uint256 public slippageTolerance = 99_500;
    uint256 public constant SLIPPAGE_TOLERANCE_PRECISION = 1e5;
    uint256 public constant MIN_SLIPPAGE_TOLERANCE = 99_000;

    using SafeERC20 for IERC20Metadata;

    constructor(
        address _asset,
        address curvePool
    )
        // TODO: leaving dummy setup for underlying wrapped strategy for now
        WrappedYearnV3Strategy(_asset, address(1), address(1), address(1), address(1))
    {
        // Checks
        if (curvePool == address(0) || _asset == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        curvePoolAddress = curvePool;
    }

    function setYieldSource(address v3VaultAddress) public override onlyManagement {
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
    function setSwapParameters(uint256 _slippageTolerance) external onlyManagement {
        // Checks
        if (_slippageTolerance >= SLIPPAGE_TOLERANCE_PRECISION || _slippageTolerance <= MIN_SLIPPAGE_TOLERANCE) {
            revert Errors.SlippageToleranceNotInRange(_slippageTolerance);
        }

        // Effects
        slippageTolerance = _slippageTolerance;
    }

    function _deployFunds(uint256 _amount) internal override {
        address _vaultAsset = vaultAsset;
        address strategyAsset = asset;
        uint256 beforeBalance = IERC20Metadata(_vaultAsset).balanceOf(address(this));
        // Expected amount of tokens to receive from the swap, assuming closely pegged assets
        uint256 expectedAmount = _amount * 10 ** (18 - IERC20Metadata(strategyAsset).decimals()) * slippageTolerance
            / SLIPPAGE_TOLERANCE_PRECISION;

        _swapFrom(curvePoolAddress, strategyAsset, _vaultAsset, _amount, 0);

        // get exact amount of tokens from the transfer denominated in 1e18
        uint256 afterTokenBalance = (IERC20Metadata(_vaultAsset).balanceOf(address(this)) - beforeBalance)
            * 10 ** (18 - IERC20Metadata(_vaultAsset).decimals());

        // check if we got less than the expected amount
        console.log("before swap token Balance: ", beforeBalance);
        console.log("after swap token Balance: ", afterTokenBalance);
        console.log("expected swap amount    : ", expectedAmount);
        if (afterTokenBalance < expectedAmount) {
            revert Errors.SlippageTooHigh();
        }

        // deposit _amount into vault if the swap was successful
        IVault(vaultAddress).deposit(afterTokenBalance, yearnStakingDelegateAddress);
    }
}

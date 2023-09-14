// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { WrappedYearnV3Strategy } from "./WrappedYearnV3Strategy.sol";
import { CurveSwapper } from "../CurveSwapper.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract WrappedYearnV3StrategyCurveSwapper is WrappedYearnV3Strategy, CurveSwapper {
    address public immutable curvePoolAddress;
    address public vaultAsset;

    using SafeERC20 for ERC20;

    constructor(address _asset, address curvePool) WrappedYearnV3Strategy(_asset) {
        require(curvePool != address(0), "curve pool address cannot be 0");
        curvePoolAddress = curvePool;
    }

    function setYieldSource(address v3VaultAddress) external override {
        vaultAddress = v3VaultAddress;
        vaultAsset = IVault(vaultAddress).asset();
        (int128 i, int128 j) = _getTokenIndexes(curvePoolAddress, asset, vaultAsset);
        require(i >= -1 && j >= -1, "token not found in curve pool");
        // Approve all future vault deposits
        ERC20(vaultAsset).approve(vaultAddress, type(uint256).max);
    }

    function _deployFunds(uint256 _amount) internal override {
        // swap _amount into underlying vault asset
        uint256 beforeBalance = ERC20(vaultAsset).balanceOf(address(this));
        // TODO: find a reliable way to get a min amount out
        _swapFrom(curvePoolAddress, asset, vaultAsset, _amount, 0);

        // get exact amount of tokens from the transfer
        uint256 toTokenBalance = ERC20(vaultAsset).balanceOf(address(this)) - beforeBalance;
        // deposit _amount into vault
        IVault(vaultAddress).deposit(toTokenBalance, yearnStakingDelegateAddress);
    }
}

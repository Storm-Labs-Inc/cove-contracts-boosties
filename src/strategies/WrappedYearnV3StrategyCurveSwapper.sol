// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { BaseTokenizedStrategy } from "tokenized-strategy/BaseTokenizedStrategy.sol";
import { CurveSwapper } from "../CurveSwapper.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract WrappedYearnV3StrategyCurveSwapper is BaseTokenizedStrategy, CurveSwapper {
    address public vaultAddress;
    address public yearnStakingDelegateAddress;
    address public curvePoolAddress;

    using SafeERC20 for ERC20;

    constructor(address _asset, address curvePool) BaseTokenizedStrategy(_asset, "Wrapped YearnV3 Strategy") {
        curvePoolAddress = curvePool;
    }

    function setYieldSource(address v3VaultAddress) external {
        vaultAddress = v3VaultAddress;
    }

    function setStakingDelegate(address delegateAddress) external {
        yearnStakingDelegateAddress = delegateAddress;
    }

    function _deployFunds(uint256 _amount) internal override {
        // swap _amount into underlying vault asset
        uint256 beforeBalance = ERC20(IVault(vaultAddress).asset()).balanceOf(address(this));
        _swapFrom(curvePoolAddress, asset, IVault(vaultAddress).asset(), _amount, 0);

        // get exact amount of tokens from the transfer
        uint256 toTokenBalance = ERC20(IVault(vaultAddress).asset()).balanceOf(address(this)) - beforeBalance;
        // deposit _amount into vault
        ERC20(IVault(vaultAddress).asset()).approve(vaultAddress, toTokenBalance);
        IVault(vaultAddress).deposit(toTokenBalance, yearnStakingDelegateAddress);
    }

    function _freeFunds(uint256 _amount) internal override {
        // withdraw _amount from vault
        IVault(vaultAddress).withdraw(_amount, msg.sender, yearnStakingDelegateAddress, 0, new address[](0));
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // harvest and report
    }
}

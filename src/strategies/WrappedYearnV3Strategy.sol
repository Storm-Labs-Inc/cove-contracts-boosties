// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { BaseTokenizedStrategy } from "tokenized-strategy/BaseTokenizedStrategy.sol";
import { CurveSwapper } from "../CurveSwapper.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract WrappedYearnV3Strategy is BaseTokenizedStrategy, CurveSwapper {
    address public vaultAddress;
    address public yearnStakingDelegateAddress;

    using SafeERC20 for ERC20;

    constructor(address _asset) BaseTokenizedStrategy(_asset, "Wrapped YearnV3 Strategy") { }

    function setYieldSource(address v3VaultAddress) external {
        vaultAddress = v3VaultAddress;
    }

    function setStakingDelegate(address delegateAddress) external {
        yearnStakingDelegateAddress = delegateAddress;
    }

    function swapFrom(
        address _curvePool,
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    )
        external
    {
        _swapFrom(_curvePool, _from, _to, _amountIn, _minAmountOut);
    }

    function _deployFunds(uint256 _amount) internal override {
        // deposit _amount into vault
        ERC20(asset).approve(vaultAddress, _amount);
        IVault(vaultAddress).deposit(_amount, yearnStakingDelegateAddress);
    }

    function _freeFunds(uint256 _amount) internal override {
        // withdraw _amount from vault
        IVault(vaultAddress).withdraw(_amount, msg.sender, yearnStakingDelegateAddress, 0, new address[](0));
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // harvest and report
    }
}

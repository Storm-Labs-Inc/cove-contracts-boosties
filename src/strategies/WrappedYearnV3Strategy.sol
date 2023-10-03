// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { BaseTokenizedStrategy } from "src/deps/yearn/tokenized-strategy/BaseTokenizedStrategy.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { Errors } from "../libraries/Errors.sol";
import { SafeERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

contract WrappedYearnV3Strategy is BaseTokenizedStrategy, CurveRouterSwapper {
    address public vaultAddress;
    address public yearnStakingDelegateAddress;
    address public dYFI;

    using SafeERC20 for ERC20;

    CurveSwapParams internal _curveSwapParams;

    constructor(
        address _asset,
        address _v3VaultAddress,
        address _yearnStakingDelegateAddress,
        address _dYFIAddress,
        address _curveRouterAddress
    )
        BaseTokenizedStrategy(_asset, "Wrapped YearnV3 Strategy")
        CurveRouterSwapper(_curveRouterAddress)
    {
        vaultAddress = _v3VaultAddress;
        yearnStakingDelegateAddress = _yearnStakingDelegateAddress;
        dYFI = _dYFIAddress;
    }

    function setYieldSource(address v3VaultAddress) public virtual onlyManagement {
        // checks
        address strategyAsset = asset;
        if (strategyAsset != IVault(v3VaultAddress).asset()) {
            revert Errors.VaultAssetDiffers();
        }
        // effects
        vaultAddress = v3VaultAddress;
        // interactions
        ERC20(strategyAsset).approve(v3VaultAddress, type(uint256).max);
    }

    function setStakingDelegate(address delegateAddress) public onlyManagement {
        // checks
        if (delegateAddress == address(0)) {
            revert Errors.ZeroAddress();
        }
        // effects
        yearnStakingDelegateAddress = delegateAddress;
        // interactions
        ERC20(vaultAddress).approve(delegateAddress, type(uint256).max);
    }

    function setdYFIAddress(address _dYFI) public onlyManagement {
        // checks
        if (_dYFI == address(0)) {
            revert Errors.ZeroAddress();
        }
        // effects
        dYFI = _dYFI;
        // interactions
        _approveTokenForSwap(dYFI);
    }

    function setCurveSwapPrams(CurveSwapParams memory curveSwapParams) external onlyManagement {
        // TODO: check irst and last aare corect tokens, every other corresponds to curvepool.coins[i or j]
        _validateSwapParams(curveSwapParams, dYFI, asset);

        // effects
        _curveSwapParams = curveSwapParams;
    }

    function _deployFunds(uint256 _amount) internal virtual override {
        // deposit _amount into vault
        address _vault = vaultAddress;
        uint256 shares = IVault(_vault).deposit(_amount, address(this));
        IYearnStakingDelegate(yearnStakingDelegateAddress).depositToGauge(_vault, shares);
    }

    function _freeFunds(uint256 _amount) internal override {
        // withdraw _amount from gauge through yearn staking delegate
        address _vault = vaultAddress;
        IYearnStakingDelegate(yearnStakingDelegateAddress).withdrawFromGauge(_vault, _amount);
        // withdraw _amount from vault, with msg.sender as recipient
        IVault(_vault).withdraw(_amount, msg.sender, address(this));
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        address vault = vaultAddress;
        IVault yearnVault = IVault(vault);
        IYearnStakingDelegate yearnStakingDelegate = IYearnStakingDelegate(yearnStakingDelegateAddress);
        // ysd.harvest() <- harvests gauge rewards (dFYI) and transfers them to this contract
        uint256 dYFIBalance = yearnStakingDelegate.harvest(vault);
        // swap dYFI -> ETH -> vaultAsset if rewards were harvested

        if (dYFIBalance > 0) {
            uint256 receivedTokens = _swap(_curveSwapParams, dYFIBalance, 0, address(this));
            // TODO: decide if funds should be deployed if the strategy is shutdown
            // if (!TokenizedStrategy.isShutdown()) {
            //     _deployFunds(ERC20(asset).balanceOf(address(this)));
            // }

            // redploy the harvestest rewards into the strategy
            _deployFunds(receivedTokens);
        }

        // TODO: below may not be accurate accounting as the underlying vault may not have realized gains/losses
        // additionally profits may have been awarded but not fully unlocked yet, these are concerns to be investigated
        // off-chain by management in the timing of calling _harvestAndReportvi
        return yearnVault.convertToAssets(yearnStakingDelegate.userInfo(address(this), vault).balance);
    }
}

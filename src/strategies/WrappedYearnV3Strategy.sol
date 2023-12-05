// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { BaseStrategy } from "@tokenized-strategy/BaseStrategy.sol";
import { IStakingDelegateRewards } from "src/interfaces/deps/yearn/veYFI/IStakingDelegateRewards.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { WrappedYearnV3 } from "./WrappedYearnV3.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";

contract WrappedYearnV3Strategy is BaseStrategy, CurveRouterSwapper, WrappedYearnV3 {
    // Libraries
    using SafeERC20 for IERC20;

    CurveSwapParams internal _harvestSwapParams;
    uint256 public maxTotalAssets;

    constructor(
        address asset_,
        address yearnStakingDelegate_,
        address dYfi_,
        address curveRouter_
    )
        BaseStrategy(asset_, "Wrapped YearnV3 Strategy")
        CurveRouterSwapper(curveRouter_)
        WrappedYearnV3(asset_, yearnStakingDelegate_, dYfi_)
    {
        _approveTokenForSwap(dYfi_);
    }

    function setHarvestSwapParams(CurveSwapParams memory curveSwapParams) external virtual onlyManagement {
        // Checks (includes external view calls)
        _validateSwapParams(curveSwapParams, dYfi, vaultAsset);

        // Effects
        _harvestSwapParams = curveSwapParams;
    }

    function setMaxTotalAssets(uint256 maxTotalAssets_) external virtual onlyManagement {
        maxTotalAssets = maxTotalAssets_;
    }

    function availableDepositLimit(address) public view virtual override returns (uint256) {
        uint256 currentTotalAssets = TokenizedStrategy.totalAssets();
        uint256 maxTotalAssets_ = maxTotalAssets;
        if (currentTotalAssets >= maxTotalAssets_) {
            return 0;
        }
        unchecked {
            return maxTotalAssets_ - currentTotalAssets;
        }
    }

    function _deployFunds(uint256 _amount) internal virtual override {
        _depositToYSD(address(asset), _amount);
    }

    function _freeFunds(uint256 _amount) internal override {
        _withdrawFromYSD(address(asset), _amount);
    }

    function _emergencyWithdraw(uint256 amount) internal override {
        uint256 currentTotalBalance = TokenizedStrategy.totalDebt();
        uint256 withdrawAmount = amount > currentTotalBalance ? currentTotalBalance : amount;
        _withdrawFromYSD(address(asset), withdrawAmount);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // Get any dYFI rewards
        address stakingDelegateRewards = IYearnStakingDelegate(yearnStakingDelegate).gaugeStakingRewards(address(asset));
        IStakingDelegateRewards(stakingDelegateRewards).getReward(address(asset));
        uint256 dYFIBalance = IERC20(dYfi).balanceOf(address(this));
        // If dYFI was received, swap it for vault asset
        if (dYFIBalance > 0) {
            uint256 receivedBaseTokens = _swap(_harvestSwapParams, dYFIBalance, 0, address(this));
            uint256 receivedVaultTokens = IERC4626(vault).deposit(receivedBaseTokens, address(this));
            uint256 receivedGaugeTokens = IERC4626(address(asset)).deposit(receivedVaultTokens, address(this));

            // If the strategy is not shutdown, deploy the funds
            // Else add the received tokens to the idle balance
            if (!TokenizedStrategy.isShutdown()) {
                _deployFunds(receivedGaugeTokens);
            }
        }
        // Return the total idle assets and the deployed assets
        return IERC20(asset).balanceOf(address(this))
            + IYearnStakingDelegate(yearnStakingDelegate).balanceOf(address(this), address(asset));
    }
}

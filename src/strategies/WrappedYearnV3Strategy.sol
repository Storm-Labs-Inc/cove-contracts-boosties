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
        _validateSwapParams(curveSwapParams, dYfi(), _VAULT_ASSET);

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
        _depositToYSD(TokenizedStrategy.asset(), _amount);
    }

    function _freeFunds(uint256 _amount) internal override {
        _withdrawFromYSD(TokenizedStrategy.asset(), _amount);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // Get any dYFI rewards
        address _asset = address(asset);
        address stakingDelegateRewards = IYearnStakingDelegate(yearnStakingDelegate()).gaugeStakingRewards(_asset);
        IStakingDelegateRewards(stakingDelegateRewards).getReward(_asset);
        uint256 dYFIBalance = IERC20(dYfi()).balanceOf(address(this));
        uint256 newIdleBalance = 0;
        // If dYFI was received, swap it for vault asset
        if (dYFIBalance > 0) {
            uint256 receivedBaseTokens = _swap(_harvestSwapParams, dYFIBalance, 0, address(this));
            uint256 receivedVaultTokens = IERC4626(_VAULT).deposit(receivedBaseTokens, address(this));
            uint256 receivedGaugeTokens = IERC4626(_asset).deposit(receivedVaultTokens, address(this));

            // If the strategy is not shutdown, deploy the funds
            // Else add the received tokens to the idle balance
            if (!TokenizedStrategy.isShutdown()) {
                _deployFunds(receivedGaugeTokens);
            } else {
                newIdleBalance = receivedGaugeTokens;
            }
        }
        // TODO: below may not be accurate accounting as the underlying vault may not have realized gains/losses
        // additionally profits may have been awarded but not fully unlocked yet, these are concerns to be investigated
        // off-chain by management in the timing of calling _harvestAndReport
        return newIdleBalance + IYearnStakingDelegate(yearnStakingDelegate()).balances(_asset, address(this));
    }
}

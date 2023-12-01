// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { BaseStrategy } from "@tokenized-strategy/BaseStrategy.sol";
import { IVault } from "yearn-vaults-v3/interfaces/IVault.sol";
import { IStakingDelegateRewards } from "src/interfaces/deps/yearn/veYFI/IStakingDelegateRewards.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { Errors } from "../libraries/Errors.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { WrappedYearnV3 } from "./WrappedYearnV3.sol";

contract WrappedYearnV3Strategy is BaseStrategy, CurveRouterSwapper, WrappedYearnV3 {
    // Libraries
    using SafeERC20 for IERC20;

    constructor(
        address _asset,
        address _vault,
        address _yearnStakingDelegate,
        address _dYFI,
        address _curveRouter
    )
        BaseStrategy(_asset, "Wrapped YearnV3 Strategy")
        CurveRouterSwapper(_curveRouter)
        WrappedYearnV3(_vault, _yearnStakingDelegate, _dYFI)
    {
        // Checks
        // Check if the given asset is the same as the given vault's asset
        if (_asset != IVault(_vault).asset()) {
            revert Errors.VaultAssetDiffers();
        }

        // Interactions
        _approveTokenForSwap(_dYFI);
        IERC20(_asset).forceApprove(_vault, type(uint256).max);
        IERC20(_vault).forceApprove(_yearnStakingDelegate, type(uint256).max);
    }

    function setHarvestSwapParams(CurveSwapParams memory curveSwapParams) external onlyManagement {
        _setHarvestSwapParams(address(asset), curveSwapParams);
    }

    function _deployFunds(uint256 _amount) internal virtual override {
        _depositGaugeToYSD(address(asset), _amount);
    }

    function _freeFunds(uint256 _amount) internal override {
        _withdrawGaugeFromYSD(address(asset), _amount);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // Get any dYFI rewards
        uint256 dYFIBalance = IStakingDelegateRewards(_YEARN_STAKING_DELEGATE).getReward(address(asset));
        uint256 newIdleBalance = 0;
        // If dYFI was received, swap it for vault asset
        if (dYFIBalance > 0) {
            uint256 receivedBaseTokens = _swap(_harvestSwapParams, dYFIBalance, 0, address(this));
            uint256 receivedGaugeTokens =
                IGauge(IGauge(address(asset)).asset()).deposit(receivedBaseTokens, address(this));

            // If the strategy is not shutdown, deploy the funds
            // Else add the received tokens to the idle balance
            if (!TokenizedStrategy.isShutdown()) {
                _deployFunds(receivedGaugeTokens);
            } else {
                // todo: do we return vault tokens or gauge
                newIdleBalance = receivedGaugeTokens;
            }
        }
        // TODO: below may not be accurate accounting as the underlying vault may not have realized gains/losses
        // additionally profits may have been awarded but not fully unlocked yet, these are concerns to be investigated
        // off-chain by management in the timing of calling _harvestAndReport
        return newIdleBalance + IVault(_VAULT).convertToAssets(totalUnderlyingVaultShares);
    }
}

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { BaseStrategy } from "@tokenized-strategy/BaseStrategy.sol";
import { IStakingDelegateRewards } from "src/interfaces/deps/yearn/veYFI/IStakingDelegateRewards.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { YearnGaugeStrategyBase } from "./YearnGaugeStrategyBase.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { ICurveTwoAssetPool } from "src/interfaces/deps/curve/ICurveTwoAssetPool.sol";
import { Errors } from "src/libraries/Errors.sol";

contract SingleAssetYearnGaugeStrategy is BaseStrategy, CurveRouterSwapper, YearnGaugeStrategyBase {
    // Libraries
    using SafeERC20 for IERC20;

    CurveSwapParams internal _harvestSwapParams;
    address public depositToken;
    uint96 public depositTokenIndex;
    uint256 public maxTotalAssets;

    constructor(
        address asset_,
        address yearnStakingDelegate_,
        address dYfi_,
        address curveRouter_
    )
        BaseStrategy(asset_, "Wrapped YearnV3 Strategy")
        CurveRouterSwapper(curveRouter_)
        YearnGaugeStrategyBase(asset_, yearnStakingDelegate_, dYfi_)
    {
        _approveTokenForSwap(dYfi_);
    }

    function _validateDepositToken(address curvePool, address depositToken_, uint96 depositTokenIndex_) internal view {
        // Check that the deposit token index is valid
        if (depositToken_ != ICurveTwoAssetPool(curvePool).coins(depositTokenIndex_)) {
            revert Errors.InvalidDepositToken();
        }
    }

    function setHarvestSwapParams(
        CurveSwapParams memory curveSwapParams,
        address depositToken_,
        uint96 depositTokenIndex_
    )
        external
        virtual
        onlyManagement
    {
        // Checks (includes external view calls)
        _validateDepositToken(vaultAsset, depositToken_, depositTokenIndex_);
        _validateSwapParams(curveSwapParams, dYfi, depositToken_);

        // Effects
        _harvestSwapParams = curveSwapParams;
        depositToken = depositToken_;
        depositTokenIndex = depositTokenIndex_;

        // Interactions
        IERC20(depositToken_).forceApprove(vaultAsset, type(uint256).max);
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

    function _depositToCurveTwoAssetPool(
        address curvePool,
        uint96 depositTokenIndex_,
        uint256 amount,
        uint256 minMintAmount
    )
        internal
        virtual
        returns (uint256)
    {
        // Deposit the amount to the Curve pool
        uint256[2] memory amounts = [uint256(0), uint256(0)];
        amounts[depositTokenIndex_] = amount;
        return ICurveTwoAssetPool(curvePool).add_liquidity(amounts, minMintAmount);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // Get any dYFI rewards
        address stakingDelegateRewards = IYearnStakingDelegate(yearnStakingDelegate).gaugeStakingRewards(address(asset));
        IStakingDelegateRewards(stakingDelegateRewards).getReward(address(asset));
        uint256 dYFIBalance = IERC20(dYfi).balanceOf(address(this));
        // If dYFI was received, swap it for vault asset
        if (dYFIBalance > 0) {
            // @dev This is a dangerous swap call that will get sandwiched if sent to a public network
            // Must be sent to a private network
            uint256 receivedDepositTokens = _swap(_harvestSwapParams, dYFIBalance, 0, address(this));
            // @dev This is a dangerous deposit call that will get sandwiched if sent to a public network
            // Must be sent to a private network
            uint256 receivedBaseTokens =
                _depositToCurveTwoAssetPool(vaultAsset, depositTokenIndex, receivedDepositTokens, 0);
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

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { BaseStrategy } from "@tokenized-strategy/BaseStrategy.sol";
import { IStakingDelegateRewards } from "src/interfaces/deps/yearn/veYFI/IStakingDelegateRewards.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { YearnGaugeStrategyBase } from "./YearnGaugeStrategyBase.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";

contract YearnGaugeStrategy is BaseStrategy, CurveRouterSwapper, YearnGaugeStrategyBase {
    // Libraries
    using SafeERC20 for IERC20;

    /// @notice Parameters for Curve swap used during harvest
    CurveSwapParams internal _harvestSwapParams;

    /// @notice Maximum total assets that the strategy can manage
    uint256 public maxTotalAssets;

    /// @notice Address of the contract that will be redeeming dYFI
    address public dYfiRedeemer;

    /// @dev Address of WETH
    address internal constant _WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    //// events ////
    event DYfiRedeemerSet(address oldDYfiRedeemer, address newDYfiRedeemer);

    /// @notice Initializes the YearnGaugeStrategy
    /// @param asset_ The address of the asset (gauge token)
    /// @param yearnStakingDelegate_ The address of the YearnStakingDelegate
    /// @param curveRouter_ The address of the Curve router
    constructor(
        address asset_,
        address yearnStakingDelegate_,
        address curveRouter_
    )
        BaseStrategy(asset_, "Wrapped YearnV3 Strategy")
        CurveRouterSwapper(curveRouter_)
        YearnGaugeStrategyBase(asset_, yearnStakingDelegate_)
    {
        _approveTokenForSwap(yfi);
    }

    /// @notice Sets the parameters for the Curve swap used in the harvest function
    /// @param curveSwapParams The parameters for the Curve swap
    function setHarvestSwapParams(CurveSwapParams memory curveSwapParams) external virtual onlyManagement {
        // Checks (includes external view calls)
        _validateSwapParams(curveSwapParams, yfi, vaultAsset);

        // Effects
        _harvestSwapParams = curveSwapParams;
    }

    /// @notice Sets the maximum total assets the strategy can manage
    /// @param maxTotalAssets_ The maximum total assets
    function setMaxTotalAssets(uint256 maxTotalAssets_) external virtual onlyManagement {
        maxTotalAssets = maxTotalAssets_;
    }

    /// @notice Calculates the available deposit limit for the strategy
    /// @return The strategy's available deposit limit
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

    /// @dev Deploys funds into the YearnStakingDelegate by depositing the asset.
    /// @param _amount The amount of the asset to deposit.
    function _deployFunds(uint256 _amount) internal virtual override {
        _depositToYSD(address(asset), _amount);
    }

    /// @dev Withdraws funds from the YearnStakingDelegate by withdrawing the asset.
    /// @param _amount The amount of the asset to withdraw.
    function _freeFunds(uint256 _amount) internal override {
        _withdrawFromYSD(address(asset), _amount);
    }

    /// @dev Performs an emergency withdrawal from the YearnStakingDelegate.
    /// @param amount The amount to withdraw in case of an emergency.
    function _emergencyWithdraw(uint256 amount) internal override {
        uint256 currentTotalBalance = TokenizedStrategy.totalDebt();
        uint256 withdrawAmount = amount > currentTotalBalance ? currentTotalBalance : amount;
        _withdrawFromYSD(address(asset), withdrawAmount);
    }

    /// @notice Harvests dYfi rewards, swaps YFI for the vault asset, and re-deposits or adds to idle balance
    /// @return _totalAssets The total assets after harvest and redeposit/idle balance update
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // Transfers unlocked dYfi rewards to this contract
        address stakingDelegateRewards = IYearnStakingDelegate(yearnStakingDelegate).gaugeStakingRewards(address(asset));
        IStakingDelegateRewards(stakingDelegateRewards).getReward(address(asset));
        // Check for any dYfi that has been redeemed for Yfi
        uint256 yfiBalance = IERC20(yfi).balanceOf(address(this));
        // If dfi has been redeemed for Yfi, swap it for vault asset and deploy it to the strategy
        if (yfiBalance > 0) {
            // This is a dangerous swap call that will get sandwiched if sent to a public network
            // Must be sent to a private network or use a minAmount derived from a price oracle
            uint256 receivedBaseTokens = _swap(_harvestSwapParams, yfiBalance, 0, address(this));
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

    function setDYfiRedeemer(address newDYfiRedeemer) external virtual onlyManagement {
        // Checks
        if (newDYfiRedeemer == address(0)) {
            revert Errors.ZeroAddress();
        }
        address currentDYfiRedeemer = dYfiRedeemer;
        if (newDYfiRedeemer == currentDYfiRedeemer) {
            revert Errors.SameAddress();
        }
        // Effects
        dYfiRedeemer = newDYfiRedeemer;
        // Interactions
        emit DYfiRedeemerSet(currentDYfiRedeemer, newDYfiRedeemer);
        if (currentDYfiRedeemer != address(0)) {
            IERC20(dYfi).forceApprove(currentDYfiRedeemer, 0);
        }
        IERC20(dYfi).forceApprove(newDYfiRedeemer, type(uint256).max);
    }
}

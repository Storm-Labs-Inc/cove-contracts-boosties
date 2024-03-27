// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { BaseStrategy } from "tokenized-strategy/BaseStrategy.sol";
import { IStakingDelegateRewards } from "src/interfaces/IStakingDelegateRewards.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { YearnGaugeStrategyBase } from "./YearnGaugeStrategyBase.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";

/**
 * @title YearnGaugeStrategy
 * @notice Strategy for interacting with Yearn Gauge
 */
contract YearnGaugeStrategy is BaseStrategy, CurveRouterSwapper, YearnGaugeStrategyBase {
    // Libraries
    using SafeERC20 for IERC20;

    /// @notice Parameters for Curve swap used during harvest
    CurveSwapParams internal _harvestSwapParams;

    /// @notice Maximum total assets that the strategy can manage
    uint256 private _maxTotalAssets;

    /// @notice Address of the contract that will be redeeming dYFI for YFI for this strategy
    address private _dYfiRedeemer;

    //// events ////
    event DYfiRedeemerSet(address oldDYfiRedeemer, address newDYfiRedeemer);

    /**
     * @notice Initializes the YearnGaugeStrategy
     * @param asset_ The address of the asset (gauge token)
     * @param yearnStakingDelegate_ The address of the YearnStakingDelegate
     * @param curveRouter_ The address of the Curve router
     */
    constructor(
        address asset_,
        address yearnStakingDelegate_,
        address curveRouter_
    )
        payable
        BaseStrategy(asset_, "Wrapped YearnV3 Strategy")
        CurveRouterSwapper(curveRouter_)
        YearnGaugeStrategyBase(asset_, yearnStakingDelegate_)
    {
        _approveTokenForSwap(_YFI);
    }

    /**
     * @notice Sets the parameters for the Curve swap used in the harvest function
     * @param curveSwapParams The parameters for the Curve swap
     */
    function setHarvestSwapParams(CurveSwapParams calldata curveSwapParams) external onlyManagement {
        // Checks (includes external view calls)
        _validateSwapParams(curveSwapParams, _YFI, _VAULT_ASSET);

        // Effects
        _harvestSwapParams = curveSwapParams;
    }

    /**
     * @notice Sets the maximum total assets the strategy can manage
     * @param newMaxTotalAssets The maximum total assets
     */
    function setMaxTotalAssets(uint256 newMaxTotalAssets) external onlyManagement {
        _maxTotalAssets = newMaxTotalAssets;
    }

    /**
     * @notice Sets the address of the contract that will be redeeming dYFI
     * @param newDYfiRedeemer The address of the new dYFI redeemer contract
     */
    function setDYfiRedeemer(address newDYfiRedeemer) external onlyManagement {
        // Checks
        if (newDYfiRedeemer == address(0)) {
            revert Errors.ZeroAddress();
        }
        address currentDYfiRedeemer = _dYfiRedeemer;
        if (newDYfiRedeemer == currentDYfiRedeemer) {
            revert Errors.SameAddress();
        }
        // Effects
        _dYfiRedeemer = newDYfiRedeemer;
        // Interactions
        emit DYfiRedeemerSet(currentDYfiRedeemer, newDYfiRedeemer);
        if (currentDYfiRedeemer != address(0)) {
            IERC20(_DYFI).forceApprove(currentDYfiRedeemer, 0);
        }
        IERC20(_DYFI).forceApprove(newDYfiRedeemer, type(uint256).max);
    }

    /**
     * @notice Get the max total assets the strategy can manage
     * @return The maximum total assets
     */
    function maxTotalAssets() external view returns (uint256) {
        return _maxTotalAssets;
    }

    /**
     * @notice Get the address of the contract that will be redeeming dYFI from this strategy
     * @return The address of the dYFI redeemer contract
     */
    function dYfiRedeemer() external view returns (address) {
        return _dYfiRedeemer;
    }

    /**
     * @notice Calculates the available deposit limit for the strategy
     * @return The strategy's available deposit limit
     */
    function availableDepositLimit(address) public view override returns (uint256) {
        uint256 currentTotalAssets = TokenizedStrategy.totalAssets();
        uint256 currentMaxTotalAssets = _maxTotalAssets;
        if (currentTotalAssets >= currentMaxTotalAssets) {
            return 0;
        }
        // Return the difference between the max total assets and the current total assets, an underflow is not possible
        // due to the above check
        unchecked {
            return currentMaxTotalAssets - currentTotalAssets;
        }
    }

    /**
     * @dev Deploys funds into the YearnStakingDelegate by depositing the asset.
     * @param _amount The amount of the asset to deposit.
     */
    function _deployFunds(uint256 _amount) internal override {
        _depositToYSD(address(asset), _amount);
    }

    /**
     * @dev Withdraws funds from the YearnStakingDelegate by withdrawing the asset.
     * @param _amount The amount of the asset to withdraw.
     */
    function _freeFunds(uint256 _amount) internal override {
        _withdrawFromYSD(address(asset), _amount);
    }

    /**
     * @dev Performs an emergency withdrawal from the YearnStakingDelegate, withdrawing the asset to the strategy.
     * @param amount The amount to withdraw in case of an emergency.
     */
    function _emergencyWithdraw(uint256 amount) internal override {
        uint256 deployedAmount = depositedInYSD(address(asset));
        uint256 withdrawAmount = amount > deployedAmount ? deployedAmount : amount;
        _withdrawFromYSD(address(asset), withdrawAmount);
    }

    /**
     * @notice Harvests dYfi rewards, swaps YFI for the vault asset, and re-deposits or adds to idle balance
     * @return _totalAssets The total assets after harvest and redeposit/idle balance update
     */
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // Check for any dYfi that has been redeemed for Yfi
        uint256 yfiBalance = IERC20(_YFI).balanceOf(address(this));
        // If dfi has been redeemed for Yfi, swap it for vault asset and deploy it to the strategy
        if (yfiBalance > 0) {
            // This is a dangerous swap call that will get sandwiched if sent to a public network
            // Must be sent to a private network or use a minAmount derived from a price oracle
            uint256 receivedBaseTokens = _swap(_harvestSwapParams, yfiBalance, 0, address(this));
            uint256 receivedVaultTokens = IERC4626(_VAULT).deposit(receivedBaseTokens, address(this));
            uint256 receivedGaugeTokens = IERC4626(address(asset)).deposit(receivedVaultTokens, address(this));

            // If the strategy is not shutdown, deploy the funds
            // Else add the received tokens to the idle balance
            if (!TokenizedStrategy.isShutdown()) {
                _deployFunds(receivedGaugeTokens);
            }
        }
        // Return the total idle assets and the deployed assets
        return IERC20(asset).balanceOf(address(this)) + depositedInYSD(address(asset));
    }
}

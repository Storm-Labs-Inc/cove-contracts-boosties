// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IYearnStakingDelegate } from "../interfaces/IYearnStakingDelegate.sol";
import { IStakingDelegateRewards } from "../interfaces/IStakingDelegateRewards.sol";
import { BaseRewardsGauge } from "./BaseRewardsGauge.sol";
import {
    SafeERC20Upgradeable,
    IERC20Upgradeable
} from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
/**
 * @title YSD Rewards Gauge
 * @notice Gauge contract for managing and distributing YSD rewards to stakers within the Yearn ecosystem.
 * @dev Extends from BaseRewardsGauge, adding specific logic for Yearn staking and strategy interactions.
 *      It includes functionality to set reward receivers and handle deposits and withdrawals in coordination with Yearn
 * contracts.
 */

contract YSDRewardsGauge is BaseRewardsGauge {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Address of the Yearn staking delegate contract.
    address public yearnStakingDelegate;
    /// @notice Address of the Cove Yearn strategy contract.
    address public coveYearnStrategy;

    /// @notice Error thrown when the total assets exceed the maximum allowed.
    error MaxTotalAssetsExceeded();
    /// @notice Error thrown when the contract is not initialized properly.
    error InvalidInitialization();

    /**
     * @notice Initializes the YSDRewardsGauge with the asset, Yearn staking delegate, and strategy addresses.
     * @param asset_ The asset token that will be used for deposits.
     * @param ysd_ The address of the Yearn staking delegate.
     * @param strategy The address of the Yearn strategy.
     */
    function initialize(address asset_, address ysd_, address strategy) external virtual initializer {
        if (ysd_ == address(0) || strategy == address(0)) {
            revert ZeroAddress();
        }
        __BaseRewardsGauge_init(asset_);
        yearnStakingDelegate = ysd_;
        coveYearnStrategy = strategy;
        // approve yearnStakingDelegate to spend asset_
        IERC20Upgradeable(asset()).forceApprove(yearnStakingDelegate, type(uint256).max);
    }

    /**
     * @notice Sets the receiver of staking delegate rewards.
     * @dev Sets the address that will receive rewards from the Yearn staking delegate.
     * @param receiver The address to receive the staking rewards.
     */
    function setStakingDelegateRewardsReceiver(address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address stakingDelegateRewards = IYearnStakingDelegate(yearnStakingDelegate).gaugeStakingRewards(asset());
        IStakingDelegateRewards(stakingDelegateRewards).setRewardReceiver(receiver);
    }

    /**
     * @notice Returns the maximum amount of assets that can be deposited into the gauge.
     * @dev Overrides the {BaseRewardsGauge-maxDeposit} function to include interaction with the YearnStakingDelegate.
     * @return The maximum amount of assets that can be deposited.
     */
    function maxDeposit(address) public view virtual override(BaseRewardsGauge) returns (uint256) {
        if (paused()) {
            return 0;
        }
        return _availableDepositLimit();
    }

    /**
     * @notice Returns the maximum amount of shares that can be minted from the gauge
     * @dev Overrides the {BaseRewardsGauge-maxMint} function to include interaction with the YearnStakingDelegate.
     * @return The maximum amount of shares that can be minted.
     */
    function maxMint(address) public view virtual override(BaseRewardsGauge) returns (uint256) {
        if (paused()) {
            return 0;
        }
        return convertToShares(_availableDepositLimit());
    }

    function _availableDepositLimit() internal view returns (uint256) {
        return IYearnStakingDelegate(yearnStakingDelegate).availableDepositLimit(asset());
    }

    /**
     * @dev Internal function to handle deposits into the gauge.
     *      Overrides the {ERC4626Upgradeable-_deposit} function to include interaction with the Yearn staking
     * delegate.
     * @param caller The address initiating the deposit.
     * @param receiver The address that will receive the shares.
     * @param assets The amount of assets to deposit.
     * @param shares The amount of shares to mint.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    )
        internal
        virtual
        override(ERC4626Upgradeable)
    {
        ERC4626Upgradeable._deposit(caller, receiver, assets, shares);
        IYearnStakingDelegate(yearnStakingDelegate).deposit(asset(), assets);
    }

    /**
     * @dev Internal function to handle withdrawals from the gauge.
     *      Overrides the {ERC4626Upgradeable-_withdraw} function to include interaction with the Yearn staking
     * delegate.
     * @param caller The address initiating the withdrawal.
     * @param receiver The address that will receive the assets.
     * @param owner The address that owns the shares being withdrawn.
     * @param assets The amount of assets to withdraw.
     * @param shares The amount of shares to burn.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
        virtual
        override(ERC4626Upgradeable)
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);
        IYearnStakingDelegate(yearnStakingDelegate).withdraw(asset(), assets, receiver);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}

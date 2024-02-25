// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { IYearnStakingDelegate } from "../interfaces/IYearnStakingDelegate.sol";
import { IStakingDelegateRewards } from "../interfaces/IStakingDelegateRewards.sol";
import { YearnGaugeStrategy } from "../strategies/YearnGaugeStrategy.sol";
import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import { BaseRewardsGauge } from "./BaseRewardsGauge.sol";
import {
    SafeERC20Upgradeable,
    IERC20Upgradeable
} from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

/**
 * @title YSD Rewards Gauge
 * @notice Gauge contract for managing and distributing YSD rewards to stakers within the Yearn ecosystem.
 * @dev Extends from BaseRewardsGauge, adding specific logic for Yearn staking and strategy interactions.
 *      It includes functionality to set reward receivers and handle deposits and withdrawals in coordination with Yearn
 * contracts.
 */
contract YSDRewardsGauge is BaseRewardsGauge {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public yearnStakingDelegate;
    address public coveYearnStrategy;

    error MaxTotalAssetsExceeded();
    error InvalidInitialization();

    constructor() payable BaseRewardsGauge() { }

    function initialize(address) public virtual override {
        revert InvalidInitialization();
    }

    /**
     * @notice Initializes the YSDRewardsGauge with the asset, Yearn staking delegate, and strategy addresses.
     * @dev Overrides the BaseRewardsGauge initialize function to include initialization of Yearn-specific parameters.
     * @param asset_ The asset token that will be used for deposits.
     * @param ysd_ The address of the Yearn staking delegate.
     * @param strategy The address of the Yearn strategy.
     */
    function initialize(address asset_, address ysd_, address strategy) public virtual /* initializer */ {
        super.initialize(asset_);
        if (ysd_ == address(0) || strategy == address(0)) {
            revert ZeroAddress();
        }
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
     * @notice Calculates the maximum total assets that can be deposited into the gauge.
     * @dev Determines the maximum assets that can be managed by the gauge based on the strategy's limits.
     * @return The maximum amount of assets that can be deposited.
     */
    function maxTotalAssets() public view virtual returns (uint256) {
        uint256 maxAssets = YearnGaugeStrategy(coveYearnStrategy).maxTotalAssets();
        uint256 totalAssetsInStrategy = ITokenizedStrategy(coveYearnStrategy).totalAssets();
        if (totalAssetsInStrategy >= maxAssets) {
            return 0;
        } else {
            return maxAssets - totalAssetsInStrategy;
        }
    }

    /**
     * @dev Internal function to handle deposits into the gauge.
     *      Overrides the BaseRewardsGauge _deposit function to include interaction with the Yearn staking delegate.
     * @param caller The address initiating the deposit.
     * @param receiver The address that will receive the shares.
     * @param assets The amount of assets to deposit.
     * @param shares The amount of shares to mint.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        if (totalAssets() + assets > maxTotalAssets()) {
            revert MaxTotalAssetsExceeded();
        }
        super._deposit(caller, receiver, assets, shares);
        IYearnStakingDelegate(yearnStakingDelegate).deposit(asset(), assets);
    }

    /**
     * @dev Internal function to handle withdrawals from the gauge.
     *      Overrides the BaseRewardsGauge _withdraw function to include interaction with the Yearn staking delegate.
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
        override
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

    /**
     * @notice Returns the total amount of the underlying asset that the gauge has.
     * @dev Provides the total assets managed by the gauge, which is the same as the total supply of the gauge's shares.
     *      Overrides the BaseRewardsGauge totalAssets function to include the balance from the Yearn staking delegate.
     * @return The total assets held by the gauge.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return IYearnStakingDelegate(yearnStakingDelegate).balanceOf(address(this), asset());
    }
}

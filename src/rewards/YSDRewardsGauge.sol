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
 * @title YSDRewardsGauge
 * @notice Solidity implementation of a tokenized liquidity gauge with support for multi rewards distribution
 */
contract YSDRewardsGauge is BaseRewardsGauge {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public yearnStakingDelegate;
    address public coveYearnStrategy;

    error MaxTotalAssetsExceeded();
    error InvalidInitialization();

    constructor() BaseRewardsGauge() { }

    function initialize(address) public virtual override {
        revert InvalidInitialization();
    }

    /**
     * @notice Initialize the contract
     * @param asset_ Address of the asset token that will be deposited
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

    function setStakingDelegateRewardsReceiver(address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address stakingDelegateRewards = IYearnStakingDelegate(yearnStakingDelegate).gaugeStakingRewards(asset());
        IStakingDelegateRewards(stakingDelegateRewards).setRewardReceiver(receiver);
    }

    /**
     * @notice Get the maximum number of assets that can be deposited.
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

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        if (totalAssets() + assets > maxTotalAssets()) {
            revert MaxTotalAssetsExceeded();
        }
        super._deposit(caller, receiver, assets, shares);
        IYearnStakingDelegate(yearnStakingDelegate).deposit(asset(), assets);
    }

    /**
     * @dev Withdraw/redeem common workflow.
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
     * @dev Overried as assets held within the staking delegate contract.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return IYearnStakingDelegate(yearnStakingDelegate).balanceOf(address(this), asset());
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { IYearnStakingDelegate } from "../interfaces/IYearnStakingDelegate.sol";
import { IStakingDelegateRewards } from "../interfaces/IStakingDelegateRewards.sol";
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

    constructor() BaseRewardsGauge() { }

    /**
     * @notice Initialize the contract
     * @param asset_ Address of the asset token that will be deposited
     */
    function initialize(address asset_, bytes calldata encodedExtraData) public override {
        super.initialize(asset_, encodedExtraData);
        // parse extraData as an address
        address ysd_ = abi.decode(encodedExtraData, (address));
        if (ysd_ == address(0)) {
            revert ZeroAddress();
        }
        yearnStakingDelegate = ysd_;

        // approve yearnStakingDelegate to spend asset_
        IERC20Upgradeable(asset()).forceApprove(yearnStakingDelegate, type(uint256).max);
    }

    function setStakingDelegateRewardsReceiver(address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address stakingDelegateRewards = IYearnStakingDelegate(yearnStakingDelegate).gaugeStakingRewards(asset());
        // TODO: modify staking delegate to allow setting rewards receiver
        IStakingDelegateRewards(stakingDelegateRewards).setRewardReceiver(receiver);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        // If _asset is ERC777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(asset()), caller, address(this), assets);
        _mint(receiver, shares);
        IYearnStakingDelegate(yearnStakingDelegate).deposit(asset(), assets);

        emit Deposit(caller, receiver, assets, shares);
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
        // TODO: modify staking delegate to allow specifying receiver on withdraw
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { BaseRewardsGauge } from "./BaseRewardsGauge.sol";
/**
 * @title ERC20 Rewards Gauge
 * @notice A RewardsGauge contract for staking ERC20 tokens and earning rewards.
 */

contract ERC20RewardsGauge is BaseRewardsGauge {
    /**
     * @notice Initialize the contract
     * @param asset_ Address of the asset token that will be deposited
     */
    function initialize(address asset_) external virtual initializer {
        __BaseRewardsGauge_init(asset_);
    }
}

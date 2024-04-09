// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
import { console2 as console } from "forge-std/console2.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import { CoveYearnGaugeFactory } from "src/registries/CoveYearnGaugeFactory.sol";
import { TokenizedStrategy } from "tokenized-strategy/TokenizedStrategy.sol";
import { YearnGaugeStrategy } from "src/strategies/YearnGaugeStrategy.sol";
import { ERC20RewardsGauge } from "src/rewards/ERC20RewardsGauge.sol";
import { RewardForwarder } from "src/rewards/RewardForwarder.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @notice Add YFI and COVE token as a reward token for the CoveYFI rewards gauge.
 * This makes CoveYFI rewards gauge distribute dYFI, YFI, and COVE.
 */
contract OpsMultisig20240408 is BaseDeployScript {
    function deploy() public override {
        vm.startBroadcast(MAINNET_COVE_OPS_MULTISIG);
        address coveYfiRewardsGauge = deployer.getAddress("CoveYfiRewardsGauge");
        address coveToken = deployer.getAddress("CoveToken");
        address coveYfiRewardsGaugeRewardForwarder = deployer.getAddress("CoveYFIRewardsGaugeRewardForwarder");

        // Add YFI as a reward token for the CoveYFI rewards gauge
        ERC20RewardsGauge(coveYfiRewardsGauge).addReward(MAINNET_YFI, coveYfiRewardsGaugeRewardForwarder);
        RewardForwarder(coveYfiRewardsGaugeRewardForwarder).approveRewardToken(MAINNET_YFI);

        ERC20RewardsGauge(coveYfiRewardsGauge).addReward(coveToken, coveYfiRewardsGaugeRewardForwarder);
        RewardForwarder(coveYfiRewardsGaugeRewardForwarder).approveRewardToken(coveToken);

        require(
            ERC20RewardsGauge(coveYfiRewardsGauge).getRewardData(MAINNET_DYFI).distributor
                == coveYfiRewardsGaugeRewardForwarder,
            "Invalid reward token"
        );
        require(
            ERC20RewardsGauge(coveYfiRewardsGauge).getRewardData(MAINNET_YFI).distributor
                == coveYfiRewardsGaugeRewardForwarder,
            "Invalid reward token"
        );
        require(
            ERC20RewardsGauge(coveYfiRewardsGauge).getRewardData(coveToken).distributor
                == coveYfiRewardsGaugeRewardForwarder,
            "Invalid reward token"
        );
    }
}

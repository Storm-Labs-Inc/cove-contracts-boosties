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
 * @notice For each reward forwarder for each rewards gauge, grant the MANAGER_ROLE to the Defender Relayer
 * This allows the Defender Relayer to call the forwardRewardToken function on the reward forwarders.
 */
contract CommunityMultisig20240408 is BaseDeployScript {
    function deploy() public override {
        vm.startBroadcast(MAINNET_COVE_COMMUNITY_MULTISIG);
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));
        CoveYearnGaugeFactory.GaugeInfo[] memory info = factory.getAllGaugeInfo(100, 0);

        // For the CoveYfi rewards gauge forwader
        address coveYfiRewardsGaugeRewardForwarder = deployer.getAddress("CoveYFIRewardsGaugeRewardForwarder");
        AccessControl(coveYfiRewardsGaugeRewardForwarder).grantRole(MANAGER_ROLE, MAINNET_DEFENDER_RELAYER);

        // For other rewards gauge forwarders
        address coveToken = deployer.getAddress("CoveToken");
        for (uint256 i = 0; i < info.length; i++) {
            address autoCompoundingGaugeRewardForwarder =
                ERC20RewardsGauge(info[i].autoCompoundingGauge).getRewardData(coveToken).distributor;
            address nonComoundingGaugeRewardForwarder =
                ERC20RewardsGauge(info[i].nonAutoCompoundingGauge).getRewardData(coveToken).distributor;
            AccessControl(autoCompoundingGaugeRewardForwarder).grantRole(MANAGER_ROLE, MAINNET_DEFENDER_RELAYER);
            AccessControl(nonComoundingGaugeRewardForwarder).grantRole(MANAGER_ROLE, MAINNET_DEFENDER_RELAYER);
        }
    }
}

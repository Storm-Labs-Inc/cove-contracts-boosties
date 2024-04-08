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
import { CoveToken } from "src/governance/CoveToken.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";

/**
 * @notice For each reward forwarder for each rewards gauge, grant the MANAGER_ROLE to the Defender Relayer
 * This allows the Defender Relayer to call the forwardRewardToken function on the reward forwarders.
 */
contract CommunityMultisig20240408 is BaseDeployScript {
    function deploy() public override {
        vm.startBroadcast(MAINNET_COVE_COMMUNITY_MULTISIG);
        CoveToken coveToken = CoveToken(deployer.getAddress("CoveToken"));
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));
        CoveYearnGaugeFactory.GaugeInfo[] memory info = factory.getAllGaugeInfo(100, 0);

        bytes[] memory multicallData = new bytes[](info.length * 4 + 2);
        uint256 i = 0;

        // For the CoveYfi rewards gauge forwader
        address coveYfiRewardsGauge = deployer.getAddress("CoveYfiRewardsGauge");
        address coveYfiRewardsGaugeRewardForwarder = deployer.getAddress("CoveYFIRewardsGaugeRewardForwarder");
        AccessControl(coveYfiRewardsGaugeRewardForwarder).grantRole(MANAGER_ROLE, MAINNET_DEFENDER_RELAYER);
        AccessControl(coveYfiRewardsGaugeRewardForwarder).grantRole(MANAGER_ROLE, MAINNET_COVE_COMMUNITY_MULTISIG);
        require(coveToken.allowedSender(coveYfiRewardsGauge) == false, "Already allowed sender");
        require(coveToken.allowedSender(coveYfiRewardsGaugeRewardForwarder) == false, "Already allowed sender");
        multicallData[i++] = abi.encodeWithSelector(coveToken.addAllowedSender.selector, coveYfiRewardsGauge);
        multicallData[i++] =
            abi.encodeWithSelector(coveToken.addAllowedSender.selector, coveYfiRewardsGaugeRewardForwarder);

        // For other rewards gauge forwarders
        for (uint256 j = 0; j < info.length; j++) {
            address autoCompoundingGaugeRewardForwarder =
                ERC20RewardsGauge(info[j].autoCompoundingGauge).getRewardData(address(coveToken)).distributor;
            address nonComoundingGaugeRewardForwarder =
                ERC20RewardsGauge(info[j].nonAutoCompoundingGauge).getRewardData(address(coveToken)).distributor;
            AccessControl(autoCompoundingGaugeRewardForwarder).grantRole(MANAGER_ROLE, MAINNET_DEFENDER_RELAYER);
            AccessControl(nonComoundingGaugeRewardForwarder).grantRole(MANAGER_ROLE, MAINNET_DEFENDER_RELAYER);
            require(coveToken.allowedSender(info[j].autoCompoundingGauge) == false, "Already allowed sender");
            require(coveToken.allowedSender(info[j].nonAutoCompoundingGauge) == false, "Already allowed sender");
            require(coveToken.allowedSender(autoCompoundingGaugeRewardForwarder) == false, "Already allowed sender");
            require(coveToken.allowedSender(nonComoundingGaugeRewardForwarder) == false, "Already allowed sender");
            multicallData[i++] =
                abi.encodeWithSelector(coveToken.addAllowedSender.selector, info[j].autoCompoundingGauge);
            multicallData[i++] =
                abi.encodeWithSelector(coveToken.addAllowedSender.selector, info[j].nonAutoCompoundingGauge);
            multicallData[i++] =
                abi.encodeWithSelector(coveToken.addAllowedSender.selector, autoCompoundingGaugeRewardForwarder);
            multicallData[i++] =
                abi.encodeWithSelector(coveToken.addAllowedSender.selector, nonComoundingGaugeRewardForwarder);
        }

        // Queue up timelock'd transaction
        TimelockController timelock = TimelockController(deployer.getAddress("TimelockController"));
        bytes memory data = abi.encodeWithSelector(Multicall.multicall.selector, multicallData);
        timelock.schedule({
            target: address(coveToken),
            value: 0,
            data: data,
            predecessor: bytes32(0),
            salt: 0,
            delay: 2 days
        });
        vm.stopBroadcast();

        // Test the timelock'd transaction
        vm.warp(block.timestamp + 2 days);
        vm.prank(MAINNET_COVE_COMMUNITY_MULTISIG);
        timelock.execute({ target: address(coveToken), value: 0, payload: data, predecessor: bytes32(0), salt: 0 });
    }
}

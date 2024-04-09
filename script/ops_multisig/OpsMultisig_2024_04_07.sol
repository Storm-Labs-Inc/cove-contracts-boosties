// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
import { console2 as console } from "forge-std/console2.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import { CoveYearnGaugeFactory } from "src/registries/CoveYearnGaugeFactory.sol";
import { TokenizedStrategy } from "tokenized-strategy/TokenizedStrategy.sol";
import { YearnGaugeStrategy } from "src/strategies/YearnGaugeStrategy.sol";

contract OpsMultisig20240407 is BaseDeployScript {
    function deploy() public override {
        vm.startBroadcast(MAINNET_COVE_OPS_MULTISIG);
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));
        CoveYearnGaugeFactory.GaugeInfo[] memory info = factory.getAllGaugeInfo(100, 0);
        address dYfiRedeemer = deployer.getAddress("dYfiRedeemer");
        for (uint256 i = 0; i < info.length; i++) {
            TokenizedStrategy(info[i].coveYearnStrategy).acceptManagement();
            YearnGaugeStrategy(info[i].coveYearnStrategy).setDYfiRedeemer(dYfiRedeemer);
        }
    }
}

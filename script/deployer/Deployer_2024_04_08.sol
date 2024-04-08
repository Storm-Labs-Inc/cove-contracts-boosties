// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import { CoveYearnGaugeFactory } from "src/registries/CoveYearnGaugeFactory.sol";
import { Yearn4626RouterExt } from "src/Yearn4626RouterExt.sol";
import { PeripheryPayments } from "Yearn-ERC4626-Router/external/PeripheryPayments.sol";

contract OpsMultisig20240407 is BaseDeployScript {
    function deploy() public override {
        vm.startBroadcast(MAINNET_COVE_DEPLOYER);
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));
        CoveYearnGaugeFactory.GaugeInfo[] memory info = new CoveYearnGaugeFactory.GaugeInfo[](3);
        info[0] = factory.getGaugeInfo(MAINNET_YVWETH_GAUGE);
        info[1] = factory.getGaugeInfo(MAINNET_YVDAI_GAUGE);
        info[2] = factory.getGaugeInfo(MAINNET_YVUSDC_GAUGE);

        Yearn4626RouterExt router = Yearn4626RouterExt(deployer.getAddress("Yearn4626RouterExt"));
        bytes[] memory data = new bytes[](info.length * 5);
        for (uint256 i = 0; i < data.length;) {
            CoveYearnGaugeFactory.GaugeInfo memory gaugeInfo = info[i / 5];
            data[i++] = abi.encodeWithSelector(
                PeripheryPayments.approve.selector, gaugeInfo.yearnVaultAsset, gaugeInfo.yearnVault, _MAX_UINT256
            );
            data[i++] = abi.encodeWithSelector(
                PeripheryPayments.approve.selector, gaugeInfo.yearnVault, gaugeInfo.yearnGauge, _MAX_UINT256
            );
            data[i++] = abi.encodeWithSelector(
                PeripheryPayments.approve.selector, gaugeInfo.yearnGauge, gaugeInfo.coveYearnStrategy, _MAX_UINT256
            );
            data[i++] = abi.encodeWithSelector(
                PeripheryPayments.approve.selector,
                gaugeInfo.coveYearnStrategy,
                gaugeInfo.autoCompoundingGauge,
                _MAX_UINT256
            );
            data[i++] = abi.encodeWithSelector(
                PeripheryPayments.approve.selector,
                gaugeInfo.yearnGauge,
                gaugeInfo.nonAutoCompoundingGauge,
                _MAX_UINT256
            );
        }
        router.multicall(data);
    }
}

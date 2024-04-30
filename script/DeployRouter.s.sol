// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
import { console2 as console } from "forge-std/console2.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import { DeployerFunctions, DefaultDeployerFunction, Deployer } from "generated/deployer/DeployerFunctions.g.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { CoveYearnGaugeFactory } from "src/registries/CoveYearnGaugeFactory.sol";
import { Yearn4626RouterExt } from "src/Yearn4626RouterExt.sol";
import { PeripheryPayments } from "Yearn-ERC4626-Router/external/PeripheryPayments.sol";

// Could also import the default deployer functions
// import "forge-deploy/DefaultDeployerFunction.sol";

contract Deployments is BaseDeployScript {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    address public broadcaster;
    address public admin;
    address public treasury;
    address public manager;
    address public pauser;
    address public timeLock;

    function deploy() public override {
        broadcaster = vm.envAddress("DEPLOYER_ADDRESS");
        require(broadcaster == msg.sender, "Deployer address mismatch. Is --sender set?");
        admin = vm.envOr("COMMUNITY_MULTISIG_ADDRESS", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 1)));
        manager = vm.envOr("OPS_MULTISIG_ADDRESS", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 2)));
        pauser = vm.envOr("PAUSER_ADDRESS", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 3)));
        treasury = admin; // TODO: Determine treasury multisig before prod deployment

        vm.label(broadcaster, "broadcaster");
        vm.label(admin, "admin");
        vm.label(manager, "manager");
        vm.label(pauser, "pauser");

        console.log("==========================================================");
        console.log("Using below addresses for deployment:");
        console.log("  Broadcaster:", broadcaster);
        console.log("  Admin:", admin);
        console.log("  Manager:", manager);
        console.log("  Pauser:", pauser);
        console.log("  Treasury:", treasury);
        console.log("==========================================================");

        deployer.setAutoBroadcast(true);

        deployYearn4626RouterExt();

        approveDepositsInRouter();

        registerContractsInMasterRegistry();
    }

    function deployYearn4626RouterExt() public deployIfMissing("Yearn4626RouterExt2") returns (address) {
        address yearn4626RouterExt = address(
            deployer.deploy_Yearn4626RouterExt(
                "Yearn4626RouterExt2", "Yearn4626RouterExt2", MAINNET_WETH, MAINNET_PERMIT2, options
            )
        );
        return yearn4626RouterExt;
    }

    function _populateApproveMulticall(
        bytes[] memory data,
        uint256 i,
        CoveYearnGaugeFactory.GaugeInfo[] memory gi
    )
        internal
        pure
        returns (uint256)
    {
        bytes4 selector = PeripheryPayments.approve.selector;
        for (uint256 j = 0; j < gi.length; j++) {
            data[i++] = abi.encodeWithSelector(selector, gi[j].yearnVaultAsset, gi[j].yearnVault, _MAX_UINT256);
            data[i++] = abi.encodeWithSelector(selector, gi[j].yearnVault, gi[j].yearnGauge, _MAX_UINT256);
            data[i++] = abi.encodeWithSelector(selector, gi[j].yearnGauge, gi[j].coveYearnStrategy, _MAX_UINT256);
            data[i++] =
                abi.encodeWithSelector(selector, gi[j].coveYearnStrategy, gi[j].autoCompoundingGauge, _MAX_UINT256);
            data[i++] = abi.encodeWithSelector(selector, gi[j].yearnGauge, gi[j].nonAutoCompoundingGauge, _MAX_UINT256);
        }
        return i;
    }

    function approveDepositsInRouter() public broadcast {
        Yearn4626RouterExt yearn4626RouterExt = Yearn4626RouterExt(deployer.getAddress("Yearn4626RouterExt2"));
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));

        // For each curve LP token -> yearn vault -> yearn gauge -> yearn strategy -> compounding cove gauge
        // and yearn gauge -> non-compounding cove gauge
        // we should include the following approvals:
        // yearn4626RouterExt.approve(address token, address vaultAddress, type(uint256).max)
        bytes[] memory data = new bytes[](8 * 5 + 2);
        uint256 i = 0;
        i = _populateApproveMulticall(data, i, factory.getAllGaugeInfo(100, 0));
        address coveYfi = deployer.getAddress("CoveYFI");
        address coveYfiRewardsGauge = deployer.getAddress("CoveYFIRewardsGauge");
        data[i++] = abi.encodeWithSelector(PeripheryPayments.approve.selector, MAINNET_YFI, coveYfi, _MAX_UINT256);
        data[i++] =
            abi.encodeWithSelector(PeripheryPayments.approve.selector, coveYfi, coveYfiRewardsGauge, _MAX_UINT256);
        require(i == data.length, "Incorrect number of approves");
        yearn4626RouterExt.multicall(data);
    }

    function registerContractsInMasterRegistry() public broadcast {
        MasterRegistry masterRegistry = MasterRegistry(deployer.getAddress("MasterRegistry"));
        masterRegistry.updateRegistry(bytes32("Yearn4626RouterExt"), deployer.getAddress("Yearn4626RouterExt2"));
    }
}

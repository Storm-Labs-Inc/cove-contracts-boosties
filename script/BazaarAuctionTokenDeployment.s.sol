// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
import { console2 as console } from "forge-std/console2.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import { DeployerFunctions, DefaultDeployerFunction, Deployer } from "generated/deployer/DeployerFunctions.g.sol";

// Could also import the default deployer functions
// import "forge-deploy/DefaultDeployerFunction.sol";

contract Deployments is BaseDeployScript {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    address public broadcaster;
    address public admin;
    address public manager;

    function deploy() public override {
        broadcaster = vm.envAddress("DEPLOYER_ADDRESS");
        require(broadcaster == msg.sender, "Deployer address mismatch. Is --sender set?");
        admin = vm.envOr("COMMUNITY_MULTISIG_ADDRESS", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 1)));
        manager = vm.envOr("OPS_MULTISIG_ADDRESS", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 2)));

        vm.label(broadcaster, "broadcaster");
        vm.label(admin, "admin");
        vm.label(manager, "manager");

        console.log("==========================================================");
        console.log("Using below addresses for deployment:");
        console.log("  Broadcaster:", broadcaster);
        console.log("  Admin:", admin);
        console.log("  Manager:", manager);
        console.log("==========================================================");

        deployer.setAutoBroadcast(true);

        deployer.deploy_CoveTokenBazaarAuction("CoveTokenBazaarAuction", admin, options);
    }
}
// example run in current setup:
// source .env
// DEPLOYMENT_CONTEXT='1' forge script script/BazaarAuctionTokenDeployment.s.sol --rpc-url $MAINNET_RPC_URL --sender
// $DEPLOYER_ADDRESS --account deployer --broadcast --verify -vvv && ./forge-deploy sync

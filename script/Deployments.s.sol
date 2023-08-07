// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { DeployScript } from "forge-deploy/DeployScript.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import {
    DeployerFunctions,
    DefaultDeployerFunction,
    Deployer,
    DeployOptions
} from "generated/deployer/DeployerFunctions.g.sol";
import { Counter } from "src/Counter.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
// Could also import the default deployer functions
// import "forge-deploy/DefaultDeployerFunction.sol";

contract Deployments is DeployScript {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    DeployOptions public options;

    function deployCounter() external returns (Counter) {
        // Using generated function with name deploy_<contract_name>
        options = DeployOptions({ salt: 1337 });
        return deployer.deploy_Counter("Counter", options);
        // Using default deployer function
        // return Counter(deployer.deploy("Counter", "Counter.sol:Counter", ""));
    }

    function deployMasterRegistry(address admin) external returns (MasterRegistry) {
        options = DeployOptions({ salt: 1337 });
        return deployer.deploy_MasterRegistry("Counter", admin, options);
    }

    function getCurrentDeployer() external view returns (Deployer) {
        return deployer;
    }
}
// exmaple run in current setup: DEPLOYMENT_CONTEXT=localhost forge script script/Deployments.s.sol --rpc-url
// http://localhost:8545 --broadcast --private-key ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -v
// && ./forge-deploy sync;

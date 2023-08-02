// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-deploy/DeployScript.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import "generated/deployer/DeployerFunctions.g.sol";
// Could also import the default deployer functions
// import "forge-deploy/DefaultDeployerFunction.sol";

contract Deployments is DeployScript {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    function deploy() external returns (Counter) {
        // Using generated function with name deploy_<contract_name>
        return deployer.deploy_Counter("Counter");
        // Using default deployer function
        // return Counter(deployer.deploy("Counter", "Counter.sol:Counter", ""));
    }
}
// exmaple run in current setup: DEPLOYMENT_CONTEXT=localhost forge script script/Counter.s.sol --rpc-url http://localhost:8545 --broadcast --private-key ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -v && ./forge-deploy sync;

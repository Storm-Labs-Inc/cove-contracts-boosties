// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-deploy/DeployScript.sol";
import "generated/deployer/DeployerFunctions.g.sol";

contract Deployments is DeployScript {
    using DeployerFunctions for Deployer;

    function deploy() external returns (Counter) {
        return deployer.deploy_Counter("Counter");
    }
}
// DEPLOYMENT_CONTEXT=localhost forge script script/Counter.s.sol --rpc-url http://localhost:8545 --broadcast --private-key ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -v && ./forge-deploy sync;

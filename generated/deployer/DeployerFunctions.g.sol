// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Deployer} from "forge-deploy/Deployer.sol";
import {DefaultDeployerFunction, DeployOptions} from "forge-deploy/DefaultDeployerFunction.sol";

// --------------------------------------------------------------------------------------------
// GENERATED
// --------------------------------------------------------------------------------------------

import "src/ConterFactory.sol" as _CounterFactory;
import { CounterFactory } from "src/ConterFactory.sol";

import "src/Counter.sol" as _Counter;
import { Counter } from "src/Counter.sol";



string constant Artifact_CounterFactory = "ConterFactory.sol:CounterFactory";

string constant Artifact_Counter = "Counter.sol:Counter";

// --------------------------------------------------------------------------------------------
 

library DeployerFunctions{

    // --------------------------------------------------------------------------------------------
    // GENERATED
    // --------------------------------------------------------------------------------------------
    
    function deploy_CounterFactory(
        Deployer deployer,
        string memory name 
        
    ) internal returns (CounterFactory) {
        bytes memory args = abi.encode();
        return CounterFactory(DefaultDeployerFunction.deploy(deployer, name, Artifact_CounterFactory, args));
    }
    function deploy_CounterFactory(
        Deployer deployer,
        string memory name,
        
        DeployOptions memory options
    ) internal returns (CounterFactory) {
        bytes memory args = abi.encode();
        return CounterFactory(DefaultDeployerFunction.deploy(deployer, name, Artifact_CounterFactory, args, options));
    }
    
    function deploy_Counter(
        Deployer deployer,
        string memory name 
        
    ) internal returns (Counter) {
        bytes memory args = abi.encode();
        return Counter(DefaultDeployerFunction.deploy(deployer, name, Artifact_Counter, args));
    }
    function deploy_Counter(
        Deployer deployer,
        string memory name,
        
        DeployOptions memory options
    ) internal returns (Counter) {
        bytes memory args = abi.encode();
        return Counter(DefaultDeployerFunction.deploy(deployer, name, Artifact_Counter, args, options));
    }
    
    // --------------------------------------------------------------------------------------------
}
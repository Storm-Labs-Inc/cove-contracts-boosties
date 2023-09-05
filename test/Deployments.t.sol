pragma solidity ^0.8.18;

// import {Vm} from "forge-std/Vm.sol";
import { Counter } from "src/Counter.sol";
import { BaseTest } from "./utils/BaseTest.t.sol";
import { Deployments } from "script/Deployments.s.sol";
import { Deployer } from "forge-deploy/Deployer.sol";

contract DeploymentsTest is BaseTest {
    Counter public counter;

    function setUp() public override {
        BaseTest.setUp();
    }

    function testDeployments() public {
        Deployments deployments = new Deployments();
        counter = deployments.deployCounter();
        Deployer currentDeployer = deployments.getCurrentDeployer();
        currentDeployer.has("Counter");
    }
}
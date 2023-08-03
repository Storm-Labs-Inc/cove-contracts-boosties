pragma solidity ^0.8.17;

// import {Vm} from "forge-std/Vm.sol";
import "../src/Counter.sol";
import "./utils/BaseTest.t.sol";
import "../script/Deploy.s.sol";
import "forge-deploy/Deployer.sol";

contract ExampleTest is Test, BaseTest {
    Counter public counter;

    function setUp() public override {
        BaseTest.setUp();
    }

    function testDeploy() public {
        Deployments deployments = new Deployments();
        counter = deployments.deploy();
        Deployer currentDeployer = deployments.getCurrentDeployer();
        currentDeployer.has("Counter");
    }
}

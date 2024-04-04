// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { DeployScript } from "forge-deploy/DeployScript.sol";
import { BaseScript } from "script/BaseScript.s.sol";
import { console2 as console } from "forge-std/console2.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import {
    DeployerFunctions,
    DefaultDeployerFunction,
    Deployer,
    DeployOptions
} from "generated/deployer/DeployerFunctions.g.sol";

abstract contract BaseDeployScript is DeployScript, BaseScript {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    DeployOptions public options = DeployOptions({ salt: uint256(keccak256("Cove")) });

    function deploy() public virtual;

    modifier deployIfMissing(string memory name) {
        if (_checkDeployment(name) != address(0)) {
            return;
        }
        _;
    }

    function _checkDeployment(string memory name) internal view returns (address addr) {
        if (deployer.has(name)) {
            addr = deployer.getAddress(name);
            console.log("Deployment already exists for", name, " at", vm.toString(addr));
        }
    }
}

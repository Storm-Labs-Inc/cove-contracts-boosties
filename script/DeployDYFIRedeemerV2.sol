// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
import { DeployerFunctions, DefaultDeployerFunction, Deployer } from "generated/deployer/DeployerFunctions.g.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { DYFIRedeemerV2 } from "src/DYFIRedeemerV2.sol";

contract DeployDYFIRedeemerV2 is BaseDeployScript {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    address public dYfiRedeemerV2;
    address public admin;

    function deploy() public override {
        require(MAINNET_COVE_DEPLOYER == msg.sender, "Sender must be mainnet deployer");
        deployer.setAutoBroadcast(true);

        admin = MAINNET_COVE_COMMUNITY_MULTISIG;

        // Deploy DYFIRedeemerV2
        dYfiRedeemerV2 = deployDYFIRedeemerV2();

        // Registry in MasterRegistry
        address masterRegistry = deployer.getAddress("MasterRegistry");
        vm.broadcast();
        MasterRegistry(masterRegistry).updateRegistry("DYFIRedeemer", dYfiRedeemerV2);

        // Verify deployments
        verifyPostDeploymentState();
    }

    function deployDYFIRedeemerV2() public deployIfMissing("DYFIRedeemerV2") returns (address) {
        return address(deployer.deploy_DYFIRedeemerV2("DYFIRedeemerV2", admin, options));
    }

    function verifyPostDeploymentState() public view {
        // Verify roles have been properly set for DYFIRedeemerV2
        _verifyRole("DYFIRedeemerV2", DEFAULT_ADMIN_ROLE, admin);
        _verifyRoleCount("DYFIRedeemerV2", DEFAULT_ADMIN_ROLE, 1);
    }

    function _verifyRole(string memory contractName, bytes32 role, address user) internal view {
        AccessControlEnumerable contractInstance = AccessControlEnumerable(deployer.getAddress(contractName));
        require(contractInstance.hasRole(role, user), string.concat("Incorrect role for: ", contractName));
    }

    function _verifyRoleCount(string memory contractName, bytes32 role, uint256 count) internal view {
        AccessControlEnumerable contractInstance = AccessControlEnumerable(deployer.getAddress(contractName));
        require(
            contractInstance.getRoleMemberCount(role) == count,
            string.concat("Incorrect role count for: ", contractName)
        );
    }
}

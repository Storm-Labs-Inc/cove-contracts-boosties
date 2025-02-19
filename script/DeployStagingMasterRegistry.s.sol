// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
import { DeployerFunctions, DefaultDeployerFunction, Deployer } from "generated/deployer/DeployerFunctions.g.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract DeployStagingMasterRegistry is BaseDeployScript {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    address public stagingMasterRegistry;

    function deploy() public override {
        require(MAINNET_COVE_DEPLOYER == msg.sender, "Sender must be mainnet deployer");
        deployer.setAutoBroadcast(true);

        // Deploy Staging Master Registry
        stagingMasterRegistry = deployStagingMasterRegistry();

        // Verify deployments
        verifyPostDeploymentState();
    }

    function deployStagingMasterRegistry() public deployIfMissing("Staging_MasterRegistry") returns (address) {
        return address(
            deployer.deploy_MasterRegistry(
                "Staging_MasterRegistry", COVE_STAGING_COMMUNITY_MULTISIG, COVE_STAGING_OPS_MULTISIG, options
            )
        );
    }

    function verifyPostDeploymentState() public view {
        // Verify roles have been properly set for MasterRegistry
        _verifyRole("Staging_MasterRegistry", DEFAULT_ADMIN_ROLE, COVE_STAGING_COMMUNITY_MULTISIG);
        _verifyRole("Staging_MasterRegistry", MANAGER_ROLE, COVE_STAGING_OPS_MULTISIG);
        _verifyRoleCount("Staging_MasterRegistry", DEFAULT_ADMIN_ROLE, 1);
        _verifyRoleCount("Staging_MasterRegistry", MANAGER_ROLE, 2);
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

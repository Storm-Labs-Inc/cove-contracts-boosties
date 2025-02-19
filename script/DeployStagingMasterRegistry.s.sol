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

    address public broadcaster;
    address public stagingMasterRegistry;
    address public constant COVE_STAGING_COMMUNITY_MULTISIG = 0xC8edE693E4B8cdf4F3C42bf141D9054050E5a728;
    address public constant COVE_STAGING_OPS_MULTISIG = 0xaAc26aee89DeEFf5D0BE246391FABDfa547dc70C;

    function deploy() public override {
        broadcaster = vm.envAddress("DEPLOYER_ADDRESS");
        require(broadcaster == msg.sender, "Deployer address mismatch. Is --sender set?");
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

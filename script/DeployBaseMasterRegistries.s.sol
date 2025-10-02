// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
import { DeployerFunctions, DefaultDeployerFunction, Deployer } from "generated/deployer/DeployerFunctions.g.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { DeployOptions } from "generated/deployer/DeployerFunctions.g.sol";
import { console2 as console } from "forge-std/console2.sol";

contract DeployBaseMasterRegistries is BaseDeployScript {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    address public stagingMasterRegistry;
    address public masterRegistry;

    // Base network deployer address
    address public constant BASE_COVE_DEPLOYER = MAINNET_COVE_DEPLOYER;

    // Base and Mainnet have the same multisig addresses
    // Staging addresses
    address public constant STAGING_ADMIN = COVE_STAGING_COMMUNITY_MULTISIG;
    address public constant STAGING_MANAGER = BASE_COVE_DEPLOYER;

    // Production addresses
    address public constant PRODUCTION_ADMIN = MAINNET_COVE_COMMUNITY_MULTISIG;
    address public constant PRODUCTION_MANAGER = BASE_COVE_DEPLOYER;

    function deploy() public override {
        require(BASE_COVE_DEPLOYER == msg.sender, "Sender must be base deployer");
        deployer.setAutoBroadcast(true);

        // Deploy Staging Master Registry
        stagingMasterRegistry = deployStagingMasterRegistry();
        console.log("Staging Master Registry deployed to:", stagingMasterRegistry);

        // Deploy Production Master Registry
        masterRegistry = deployMasterRegistry();
        console.log("Production Master Registry deployed to:", masterRegistry);

        // Verify deployments
        verifyPostDeploymentState();
    }

    function deployStagingMasterRegistry() public deployIfMissing("Staging_MasterRegistry") returns (address) {
        return
            address(deployer.deploy_MasterRegistry("Staging_MasterRegistry", STAGING_ADMIN, STAGING_MANAGER, options));
    }

    function deployMasterRegistry() public deployIfMissing("MasterRegistry") returns (address) {
        // Base and Mainnet have the same multisig addresses
        return address(deployer.deploy_MasterRegistry("MasterRegistry", PRODUCTION_ADMIN, PRODUCTION_MANAGER, options));
    }

    function verifyPostDeploymentState() public view {
        // Verify roles have been properly set for Staging_MasterRegistry
        _verifyRole("Staging_MasterRegistry", DEFAULT_ADMIN_ROLE, STAGING_ADMIN);
        _verifyRole("Staging_MasterRegistry", MANAGER_ROLE, STAGING_ADMIN);
        _verifyRole("Staging_MasterRegistry", MANAGER_ROLE, STAGING_MANAGER);
        _verifyRoleCount("Staging_MasterRegistry", DEFAULT_ADMIN_ROLE, 1);
        _verifyRoleCount("Staging_MasterRegistry", MANAGER_ROLE, 2);

        // Verify roles have been properly set for MasterRegistry
        _verifyRole("MasterRegistry", DEFAULT_ADMIN_ROLE, PRODUCTION_ADMIN);
        _verifyRole("MasterRegistry", MANAGER_ROLE, PRODUCTION_ADMIN);
        _verifyRole("MasterRegistry", MANAGER_ROLE, PRODUCTION_MANAGER);
        _verifyRoleCount("MasterRegistry", DEFAULT_ADMIN_ROLE, 1);
        _verifyRoleCount("MasterRegistry", MANAGER_ROLE, 2);
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

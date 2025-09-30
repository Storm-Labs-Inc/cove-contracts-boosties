// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
import { DeployerFunctions, DefaultDeployerFunction, Deployer } from "generated/deployer/DeployerFunctions.g.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract DeployBaseMasterRegistries is BaseDeployScript {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    address public stagingMasterRegistry;
    address public masterRegistry;

    // Base network deployer address
    address public constant BASE_COVE_DEPLOYER = 0x8842fe65A7Db9BB5De6d50e49aF19496da09F9b5;

    // Placeholder addresses for staging
    address public constant STAGING_ADMIN = 0x1111111111111111111111111111111111111111;
    address public constant STAGING_MANAGER = 0x2222222222222222222222222222222222222222;

    // Production addresses (can be overridden via env vars)
    address public admin;
    address public manager;

    function deploy() public override {
        require(BASE_COVE_DEPLOYER == msg.sender, "Sender must be base deployer");
        deployer.setAutoBroadcast(true);

        // Load production addresses from env or use test derivation
        admin = vm.envOr("COMMUNITY_MULTISIG_ADDRESS", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 1)));
        manager = vm.envOr("OPS_MULTISIG_ADDRESS", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 2)));

        // Deploy Staging Master Registry
        stagingMasterRegistry = deployStagingMasterRegistry();
        vm.label(stagingMasterRegistry, "Staging_MasterRegistry");

        // Deploy Production Master Registry
        masterRegistry = deployMasterRegistry();
        vm.label(masterRegistry, "MasterRegistry");

        // Verify deployments
        verifyPostDeploymentState();
    }

    function deployStagingMasterRegistry() public deployIfMissing("Staging_MasterRegistry") returns (address) {
        return
            address(deployer.deploy_MasterRegistry("Staging_MasterRegistry", STAGING_ADMIN, STAGING_MANAGER, options));
    }

    function deployMasterRegistry() public deployIfMissing("MasterRegistry") returns (address) {
        return address(deployer.deploy_MasterRegistry("MasterRegistry", admin, BASE_COVE_DEPLOYER, options));
    }

    function verifyPostDeploymentState() public view {
        // Verify roles have been properly set for Staging_MasterRegistry
        _verifyRole("Staging_MasterRegistry", DEFAULT_ADMIN_ROLE, STAGING_ADMIN);
        _verifyRole("Staging_MasterRegistry", MANAGER_ROLE, STAGING_ADMIN);
        _verifyRole("Staging_MasterRegistry", MANAGER_ROLE, STAGING_MANAGER);
        _verifyRoleCount("Staging_MasterRegistry", DEFAULT_ADMIN_ROLE, 1);
        _verifyRoleCount("Staging_MasterRegistry", MANAGER_ROLE, 2);

        // Verify roles have been properly set for MasterRegistry
        _verifyRole("MasterRegistry", DEFAULT_ADMIN_ROLE, admin);
        _verifyRole("MasterRegistry", MANAGER_ROLE, admin);
        _verifyRole("MasterRegistry", MANAGER_ROLE, BASE_COVE_DEPLOYER);
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

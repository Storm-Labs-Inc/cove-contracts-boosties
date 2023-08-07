// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { BaseTest } from "../../utils/BaseTest.t.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { Deployments } from "script/Deployments.s.sol";

contract MasterRegistryTest is BaseTest {
    MasterRegistry public masterRegistry;

    function setUp() public override {
        super.setUp();
        vm.startPrank(users["admin"]);
        masterRegistry = new MasterRegistry(users["admin"]);
    }

    function testInit() public view {
        assert(masterRegistry.hasRole(masterRegistry.DEFAULT_ADMIN_ROLE(), users["admin"]));
    }

    function testEmptyString() public {
        vm.expectRevert("MR: name cannot be empty");
        masterRegistry.addRegistry("", address(1));
    }

    function testEmptyAddress() public {
        vm.expectRevert("MR: address cannot be empty");
        masterRegistry.addRegistry("test", address(0));
    }

    function testDuplicateAddress() public {
        masterRegistry.addRegistry("test", address(1));
        vm.expectRevert("MR: duplicate registry address");
        masterRegistry.addRegistry("test2", address(1));
    }

    function testAddRegistry() public {
        masterRegistry.addRegistry("test1", address(1));
        assertEq(masterRegistry.resolveNameToLatestAddress("test1"), address(1));
    }

    function testAddRegistryWithSameName() public {
        masterRegistry.addRegistry("test1", address(1));
        masterRegistry.addRegistry("test1", address(2));
        assertEq(masterRegistry.resolveNameToLatestAddress("test1"), address(2));
    }

    function testResolveNameToLatestNotFoundName() public {
        vm.expectRevert("MR: no match found for name");
        masterRegistry.resolveNameToLatestAddress("test1");
    }

    function testResolveToAllAddressesNotFoundName() public {
        vm.expectRevert("MR: no match found for name");
        masterRegistry.resolveNameToAllAddresses("test1");
    }

    function testResolveNameToAllAddresses() public {
        masterRegistry.addRegistry("test1", address(1));
        masterRegistry.addRegistry("test1", address(2));
        masterRegistry.resolveNameToAllAddresses("test1");
        address[] memory res = masterRegistry.resolveNameToAllAddresses("test1");
        assertEq(res[0], address(1));
        assertEq(res[1], address(2));
    }

    function testResolveNameAndVersionAddresseNotFound() public {
        vm.expectRevert("MR: no match found for name and version");
        masterRegistry.resolveNameAndVersionToAddress("test1", 0);
        masterRegistry.addRegistry("test1", address(1));
        vm.expectRevert("MR: no match found for name and version");
        masterRegistry.resolveNameAndVersionToAddress("test1", 1);
    }

    function testResolveNameAndVersionToAddress() public {
        masterRegistry.addRegistry("test1", address(1));
        masterRegistry.addRegistry("test1", address(2));
        assertEq(masterRegistry.resolveNameAndVersionToAddress("test1", 0), address(1));
        assertEq(masterRegistry.resolveNameAndVersionToAddress("test1", 1), address(2));
    }

    function testResolveAddressToRegistryNotFound() public {
        vm.expectRevert("MR: no match found for address");
        masterRegistry.resolveAddressToRegistryData(address(1));
    }

    function testResolveAddressToRegistryData() public {
        masterRegistry.addRegistry("test1", address(1));
        masterRegistry.addRegistry("test1", address(2));
        masterRegistry.addRegistry("test2", address(3));
        (bytes32 name, uint256 version, bool isLatest) = masterRegistry.resolveAddressToRegistryData(address(1));
        assertEq(name, "test1");
        assertEq(version, 0);
        assertEq(isLatest, false);
        (name, version, isLatest) = masterRegistry.resolveAddressToRegistryData(address(2));
        assertEq(name, "test1");
        assertEq(version, 1);
        assertEq(isLatest, true);
        (name, version, isLatest) = masterRegistry.resolveAddressToRegistryData(address(3));
        assertEq(name, "test2");
        assertEq(version, 0);
        assertEq(isLatest, true);
    }

    // Find the manager role
    bytes32 _managerRole = keccak256("PROTOCOL_MANAGER_ROLE");
    // TODO: why below no work
    // bytes32 _managerRole = masterRegistry.PROTOCOL_MANAGER_ROLE();

    // Expect the admin role of the manager role to be zero (0x0000...0000)
    function testManagerRole() public {
        assertEq(masterRegistry.getRoleAdmin(_managerRole), bytes32(0));
    }

    // Try granting manager role from an account without admin role
    function testGrantManagerRoleWithoutAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // TODO: is there a better way to check this error
        vm.expectRevert(
            "AccessControl: account 0x328809bc894f92807417d2dad6b7c998c1afdac6 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        masterRegistry.grantRole(_managerRole, users["alice"]);
    }

    // Try granting manager role from an account with admin role
    function testGrantManagerRoleWithAdmin() public {
        // Check the user does not have the manager role
        assert(!masterRegistry.hasRole(_managerRole, users["alice"]));

        // Grant the manager role to the user from the owner
        masterRegistry.grantRole(_managerRole, users["alice"]);

        // Check the user now has the manager role
        assert(masterRegistry.hasRole(_managerRole, users["alice"]));
    }

    // Find admin role
    bytes32 _adminRole = 0x00;
    // TODO why below no work while is works on line 10
    // bytes32 _adminRole = masterRegistry.DEFAULT_ADMIN_ROLE();

    function testGrantAdminRole() public {
        // Check the user does not have the admin role
        assert(!masterRegistry.hasRole(_adminRole, users["alice"]));

        // Grant the admin role to the user from the owner
        masterRegistry.grantRole(_adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(masterRegistry.hasRole(_adminRole, users["alice"]));

        // Verify the user can grant the manager role
        vm.prank(users["alice"]);
        masterRegistry.grantRole(_managerRole, users["bob"]);
    }

    function testRevokeRoleWithoutAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // TODO why below no work
        bytes memory errorMsg =
            abi.encodePacked("AccessControl: account", users["alice"], "is missing role", bytes32(0));
        vm.expectRevert(
            "AccessControl: account 0x328809bc894f92807417d2dad6b7c998c1afdac6 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        masterRegistry.revokeRole(_managerRole, users["admin"]);
        vm.stopPrank();
    }

    function testRevokeRole() public {
        // Check the user does not have the admin role
        assert(!masterRegistry.hasRole(_adminRole, users["alice"]));

        // Grant the admin role to the user from the owner
        masterRegistry.grantRole(_adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(masterRegistry.hasRole(_adminRole, users["alice"]));

        // Revoke the admin role from the user from the owner
        masterRegistry.revokeRole(_adminRole, users["alice"]);

        // Check the user no longer has the admin role
        assert(!masterRegistry.hasRole(_adminRole, users["alice"]));
    }

    function testRevokeRoleFromSelf() public {
        // Check the user does not have the admin role
        assert(!masterRegistry.hasRole(_adminRole, users["alice"]));

        // Grant the admin role to the user from the owner

        masterRegistry.grantRole(_adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(masterRegistry.hasRole(_adminRole, users["alice"]));

        // Revoke the admin role from the user from the owner
        vm.prank(users["alice"]);
        masterRegistry.revokeRole(_adminRole, users["alice"]);

        // Check the user no longer has the admin role
        assert(!masterRegistry.hasRole(_adminRole, users["alice"]));
    }

    function testRenouceRoleManager() public {
        // Check the admin has the manager role
        assert(masterRegistry.hasRole(_managerRole, users["admin"]));

        // Renouce the manager role from the admin
        masterRegistry.renounceRole(_managerRole, users["admin"]);

        // Check the user no longer has the manager role
        assert(!masterRegistry.hasRole(_managerRole, users["admin"]));
    }

    function testRenouceRoleAdmin() public {
        // Check the user has the admin role
        assert(masterRegistry.hasRole(_adminRole, users["admin"]));

        // Renouce the admin role from the admin
        masterRegistry.renounceRole(_adminRole, users["admin"]);

        // Check the user no longer has the admin role
        assert(!masterRegistry.hasRole(_adminRole, users["admin"]));
    }
}

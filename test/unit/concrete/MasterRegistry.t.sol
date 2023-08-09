// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "../../utils/BaseTest.t.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { Deployments } from "script/Deployments.s.sol";
import { Errors } from "src/interfaces/Errors.sol";

contract MasterRegistryTest is BaseTest {
    MasterRegistry public masterRegistry;
    bytes32 public adminRole;
    bytes32 public managerRole;

    function setUp() public override {
        super.setUp();
        vm.startPrank(users["admin"]);
        masterRegistry = new MasterRegistry(users["admin"]);
        adminRole = masterRegistry.DEFAULT_ADMIN_ROLE();
        managerRole = masterRegistry.PROTOCOL_MANAGER_ROLE();
    }

    function testInit() public view {
        assert(masterRegistry.hasRole(adminRole, users["admin"]));
        assert(masterRegistry.hasRole(managerRole, users["admin"]));
    }

    function testEmptyStringAdd() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NameEmpty.selector));
        masterRegistry.addRegistry("", address(1));
    }

    function testEmptyAddressAdd() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressEmpty.selector));
        masterRegistry.addRegistry("test", address(0));
    }

    function testDuplicateAddressAdd() public {
        masterRegistry.addRegistry("test", address(1));
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicateRegistryAddress.selector, address(1)));
        masterRegistry.addRegistry("test2", address(1));
    }

    function testDuplicateAddRegistry() public {
        masterRegistry.addRegistry("test", address(1));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameFound.selector, bytes32("test")));
        masterRegistry.addRegistry("test", address(2));
    }

    function testEmptyStringUpdate() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NameEmpty.selector));
        masterRegistry.updateRegistry("", address(1));
    }

    function testEmptyAddressUpdate() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressEmpty.selector));
        masterRegistry.updateRegistry("test", address(0));
    }

    function testDuplicateAddressUpdate() public {
        masterRegistry.addRegistry("test", address(1));
        masterRegistry.addRegistry("test2", address(2));
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicateRegistryAddress.selector, address(1)));
        masterRegistry.updateRegistry("test", address(1));
    }

    function testNonExistantUpdate() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameNotFound.selector, bytes32("test")));
        masterRegistry.updateRegistry("test", address(1));
    }

    function testAddRegistry() public {
        masterRegistry.addRegistry("test1", address(1));
        assertEq(masterRegistry.resolveNameToLatestAddress("test1"), address(1));
    }

    function testAddRegistryWithSameName() public {
        masterRegistry.addRegistry("test1", address(1));
        masterRegistry.updateRegistry("test1", address(2));
        assertEq(masterRegistry.resolveNameToLatestAddress("test1"), address(2));
    }

    function testResolveNameToLatestNotFoundName() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameNotFound.selector, bytes32("test1")));
        masterRegistry.resolveNameToLatestAddress("test1");
    }

    function testResolveToAllAddressesNotFoundName() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameNotFound.selector, bytes32("test1")));
        masterRegistry.resolveNameToAllAddresses("test1");
    }

    function testResolveNameToAllAddresses() public {
        masterRegistry.addRegistry("test1", address(1));
        masterRegistry.updateRegistry("test1", address(2));
        masterRegistry.resolveNameToAllAddresses("test1");
        address[] memory res = masterRegistry.resolveNameToAllAddresses("test1");
        assertEq(res[0], address(1));
        assertEq(res[1], address(2));
    }

    function testResolveNameAndVersionAddresseNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameVersionNotFound.selector, bytes32("test1"), 0));
        masterRegistry.resolveNameAndVersionToAddress("test1", 0);
        masterRegistry.addRegistry("test1", address(1));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameVersionNotFound.selector, bytes32("test1"), 1));
        masterRegistry.resolveNameAndVersionToAddress("test1", 1);
    }

    function testResolveNameAndVersionToAddress() public {
        masterRegistry.addRegistry("test1", address(1));
        masterRegistry.updateRegistry("test1", address(2));
        assertEq(masterRegistry.resolveNameAndVersionToAddress("test1", 0), address(1));
        assertEq(masterRegistry.resolveNameAndVersionToAddress("test1", 1), address(2));
    }

    function testResolveAddressToRegistryNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryAddressNotFound.selector, address(1)));
        masterRegistry.resolveAddressToRegistryData(address(1));
    }

    function testResolveAddressToRegistryData() public {
        masterRegistry.addRegistry("test1", address(1));
        masterRegistry.updateRegistry("test1", address(2));
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

    function testManagerRole() public {
        assertEq(masterRegistry.getRoleAdmin(managerRole), bytes32(0));
    }

    function testAddRegistryPermissions() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        vm.expectRevert(abi.encodeWithSelector(Errors.CallerNotProtocolManager.selector, users["alice"]));
        masterRegistry.addRegistry("test1", address(1));
    }

    function testUpdateRegistryPermissions() public {
        masterRegistry.addRegistry("test1", address(1));
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        vm.expectRevert(abi.encodeWithSelector(Errors.CallerNotProtocolManager.selector, users["alice"]));
        masterRegistry.updateRegistry("test1", address(2));
    }

    // Try granting manager role from an account without admin role
    function testGrantManagerRoleWithoutAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        vm.expectRevert(
            "AccessControl: account 0x328809bc894f92807417d2dad6b7c998c1afdac6 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        masterRegistry.grantRole(managerRole, users["alice"]);
    }

    // Try granting manager role from an account with admin role
    function testGrantManagerRoleWithAdmin() public {
        // Check the user does not have the manager role
        assert(!masterRegistry.hasRole(managerRole, users["alice"]));

        // Grant the manager role to the user from the owner
        masterRegistry.grantRole(managerRole, users["alice"]);

        // Check the user now has the manager role
        assert(masterRegistry.hasRole(managerRole, users["alice"]));
    }

    function testGrantAdminRole() public {
        // Check the user does not have the admin role
        assert(!masterRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner
        masterRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(masterRegistry.hasRole(adminRole, users["alice"]));

        // Verify the user can grant the manager role
        vm.stopPrank();
        vm.prank(users["alice"]);
        masterRegistry.grantRole(managerRole, users["bob"]);
    }

    function testRevokeRoleWithoutAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        vm.expectRevert(
            "AccessControl: account 0x328809bc894f92807417d2dad6b7c998c1afdac6 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        masterRegistry.revokeRole(managerRole, users["admin"]);
        vm.stopPrank();
    }

    function testRevokeRole() public {
        // Check the user does not have the admin role
        assert(!masterRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner
        masterRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(masterRegistry.hasRole(adminRole, users["alice"]));

        // Revoke the admin role from the user from the owner
        masterRegistry.revokeRole(adminRole, users["alice"]);

        // Check the user no longer has the admin role
        assert(!masterRegistry.hasRole(adminRole, users["alice"]));
    }

    function testRevokeRoleFromSelf() public {
        // Check the user does not have the admin role
        assert(!masterRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner

        masterRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(masterRegistry.hasRole(adminRole, users["alice"]));

        // Revoke the admin role from the user from the owner
        vm.stopPrank();
        vm.prank(users["alice"]);
        masterRegistry.revokeRole(adminRole, users["alice"]);

        // Check the user no longer has the admin role
        assert(!masterRegistry.hasRole(adminRole, users["alice"]));
    }

    function testRenouceRoleManager() public {
        // Check the admin has the manager role
        assert(masterRegistry.hasRole(managerRole, users["admin"]));

        // Renouce the manager role from the admin
        masterRegistry.renounceRole(managerRole, users["admin"]);

        // Check the user no longer has the manager role
        assert(!masterRegistry.hasRole(managerRole, users["admin"]));
    }

    function testRenouceRoleAdmin() public {
        // Check the user has the admin role
        assert(masterRegistry.hasRole(adminRole, users["admin"]));

        // Renouce the admin role from the admin
        masterRegistry.renounceRole(adminRole, users["admin"]);

        // Check the user no longer has the admin role
        assert(!masterRegistry.hasRole(adminRole, users["admin"]));
    }

    function testMulticallAdd() public {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(masterRegistry.addRegistry.selector, bytes32("test1"), address(1));
        calls[1] = abi.encodeWithSelector(masterRegistry.addRegistry.selector, bytes32("test2"), address(2));
        masterRegistry.multicall(calls);
        assertEq(masterRegistry.resolveNameToLatestAddress("test1"), address(1));
        assertEq(masterRegistry.resolveNameToLatestAddress("test2"), address(2));
    }

    function testMulticallUpdate() public {
        masterRegistry.addRegistry("test1", address(1));
        masterRegistry.addRegistry("test2", address(2));
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(masterRegistry.updateRegistry.selector, bytes32("test1"), address(11));
        calls[1] = abi.encodeWithSelector(masterRegistry.updateRegistry.selector, bytes32("test2"), address(22));
        masterRegistry.multicall(calls);
        assertEq(masterRegistry.resolveNameAndVersionToAddress("test1", 0), address(1));
        assertEq(masterRegistry.resolveNameAndVersionToAddress("test2", 0), address(2));
        assertEq(masterRegistry.resolveNameToLatestAddress("test1"), address(11));
        assertEq(masterRegistry.resolveNameToLatestAddress("test2"), address(22));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { Deployments } from "script/Deployments.s.sol";
import { Errors } from "src/libraries/Errors.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract MasterRegistryTest is BaseTest {
    MasterRegistry public masterRegistry;
    bytes32 public adminRole;
    bytes32 public managerRole;

    function setUp() public override {
        super.setUp();
        createUser("admin");
        createUser("alice");
        vm.startPrank(users["admin"]);
        masterRegistry = new MasterRegistry(users["admin"]);
        adminRole = masterRegistry.DEFAULT_ADMIN_ROLE();
        managerRole = masterRegistry.PROTOCOL_MANAGER_ROLE();
    }

    function _formatAccessControlError(address addr, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(addr),
            " is missing role ",
            Strings.toHexString(uint256(role), 32)
        );
    }

    function test_init() public view {
        assert(masterRegistry.hasRole(adminRole, users["admin"]));
        assert(masterRegistry.hasRole(managerRole, users["admin"]));
    }

    function test_addRegistry_revertWhenCalledWithEmptyString(address addr) public {
        vm.assume(addr != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.NameEmpty.selector));
        masterRegistry.addRegistry("", addr);
    }

    function test_addRegistry_revertWhenCalledWithEmptyAddress(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressEmpty.selector));
        masterRegistry.addRegistry(name, address(0));
    }

    function test_addRegistry_revertWhenCalledWithDuplicateAddress(bytes32 name, bytes32 name2, address addr) public {
        vm.assume(name != name2);
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        masterRegistry.addRegistry(name, addr);
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicateRegistryAddress.selector, addr));
        masterRegistry.addRegistry(name2, addr);
    }

    function test_addRegistry_revertWhenCalledWithDuplicateName(bytes32 name, address addr, address addr2) public {
        vm.assume(addr != addr2);
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));

        masterRegistry.addRegistry(name, addr);
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameFound.selector, name));
        masterRegistry.addRegistry(name, addr2);
    }

    function testFuzz_updateRegistry_revertWhenCalledWithEmptyString(address addr) public {
        vm.assume(addr != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.NameEmpty.selector));
        masterRegistry.updateRegistry("", addr);
    }

    function testFuzz_updateRegistry_revertWhenCalledWithEmptyAddress(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressEmpty.selector));
        masterRegistry.updateRegistry(name, address(0));
    }

    function testFuzz_updateRegistry_revertWhenCalledWithDuplicateAddress(
        bytes32 name,
        bytes32 name2,
        address addr,
        address addr2
    )
        public
    {
        vm.assume(addr != addr2);
        vm.assume(name != name2);
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        masterRegistry.addRegistry(name, addr);
        masterRegistry.addRegistry(name2, addr2);
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicateRegistryAddress.selector, addr2));
        masterRegistry.updateRegistry(name, addr2);
    }

    function test_updateRegistry_revertWhenNameNotFound(bytes32 name, address addr) public {
        vm.assume(addr != address(0));
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameNotFound.selector, name));
        masterRegistry.updateRegistry(name, addr);
    }

    function testFuzz_addRegistry(bytes32 name, address addr) public {
        vm.assume(addr != address(0));
        vm.assume(name != bytes32(0));
        masterRegistry.addRegistry(name, addr);
        assertEq(masterRegistry.resolveNameToLatestAddress(name), addr);
    }

    function testFuzz_updateRegistry(bytes32 name, address addr, address addr2) public {
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(name != bytes32(0));
        vm.assume(addr != addr2);
        masterRegistry.addRegistry(name, addr);
        masterRegistry.updateRegistry(name, addr2);
        assertEq(masterRegistry.resolveNameToLatestAddress(name), addr2);
    }

    function testFuzz_resolveNameToLatestAddress_revertWhenNameNotFound(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameNotFound.selector, name));
        masterRegistry.resolveNameToLatestAddress(name);
    }

    function testFuzz_resolveNameToAllAddresses(bytes32 name, address addr, address addr2) public {
        vm.assume(addr != addr2);
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        masterRegistry.addRegistry(name, addr);
        masterRegistry.updateRegistry(name, addr2);
        address[] memory res = masterRegistry.resolveNameToAllAddresses(name);
        assertEq(res[0], addr);
        assertEq(res[1], addr2);
    }

    function testFuzz_resolveNameToAllAddresses_revertWhenNamNotFound(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameNotFound.selector, name));
        masterRegistry.resolveNameToAllAddresses(name);
    }

    function testFuzz_resolveNameAndVersionToAddress_revertWhenNameAndVersionNotFound(
        bytes32 name,
        address addr
    )
        public
    {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameVersionNotFound.selector, name, 0));
        masterRegistry.resolveNameAndVersionToAddress(name, 0);
        masterRegistry.addRegistry(name, addr);
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameVersionNotFound.selector, name, 1));
        masterRegistry.resolveNameAndVersionToAddress(name, 1);
    }

    function testFuzz_resolveNameAndVersionToAddress(bytes32 name, address addr, address addr2) public {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr != addr2);
        masterRegistry.addRegistry(name, addr);
        masterRegistry.updateRegistry(name, addr2);
        assertEq(masterRegistry.resolveNameAndVersionToAddress(name, 0), addr);
        assertEq(masterRegistry.resolveNameAndVersionToAddress(name, 1), addr2);
    }

    function testFuzz_resolveAddressToRegistryData_revertWhenRegistryAddressNotFound(address addr) public {
        vm.assume(addr != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryAddressNotFound.selector, addr));
        masterRegistry.resolveAddressToRegistryData(addr);
    }

    function testFuzz_resolveAddressToRegistryData(
        bytes32 name,
        bytes32 name2,
        address addr,
        address addr2,
        address addr3
    )
        public
    {
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr3 != address(0));
        vm.assume(addr != addr2);
        vm.assume(addr2 != addr3);
        vm.assume(addr != addr3);
        masterRegistry.addRegistry(name, addr);
        masterRegistry.updateRegistry(name, addr2);
        masterRegistry.addRegistry(name2, addr3);
        (bytes32 resloveName, uint256 version, bool isLatest) = masterRegistry.resolveAddressToRegistryData(addr);
        assertEq(resloveName, name);
        assertEq(version, 0);
        assertEq(isLatest, false);
        (resloveName, version, isLatest) = masterRegistry.resolveAddressToRegistryData(addr2);
        assertEq(resloveName, name);
        assertEq(version, 1);
        assertEq(isLatest, true);
        (resloveName, version, isLatest) = masterRegistry.resolveAddressToRegistryData(addr3);
        assertEq(resloveName, name2);
        assertEq(version, 0);
        assertEq(isLatest, true);
    }

    function test_getRoleAdmin_managerRole() public {
        assertEq(masterRegistry.getRoleAdmin(managerRole), bytes32(0));
    }

    function testFuzz_addRegistry_revertWhenCalledByNonManager(bytes32 name, address addr) public {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        vm.expectRevert(_formatAccessControlError(users["alice"], managerRole));
        masterRegistry.addRegistry(name, addr);
    }

    function testFuzz_updateRegistry_revertWhenCalledByNonManager(bytes32 name, address addr, address addr2) public {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr != addr2);
        masterRegistry.addRegistry(name, addr);
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        vm.expectRevert(_formatAccessControlError(users["alice"], managerRole));
        masterRegistry.updateRegistry(name, addr2);
    }

    // Try granting manager role from an account without admin role
    function test_grantRole_revertWhenCalledByNonAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        vm.expectRevert(_formatAccessControlError(users["alice"], adminRole));
        masterRegistry.grantRole(managerRole, users["alice"]);
    }

    // Try granting manager role from an account with admin role
    function test_grantRole_managerRole() public {
        // Check the user does not have the manager role
        assert(!masterRegistry.hasRole(managerRole, users["alice"]));

        // Grant the manager role to the user from the owner
        masterRegistry.grantRole(managerRole, users["alice"]);

        // Check the user now has the manager role
        assert(masterRegistry.hasRole(managerRole, users["alice"]));
    }

    function test_grantRole_adminRole() public {
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

    function test_revokeRole_managerRole_revertWhenRevokeRoleWithoutAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        vm.expectRevert(_formatAccessControlError(users["alice"], adminRole));
        masterRegistry.revokeRole(managerRole, users["admin"]);
        vm.stopPrank();
    }

    function test_revokeRole_adminRole() public {
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

    function test_revokeRoleF_adminRole() public {
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

    function test_renouceRole_managerRole() public {
        // Check the admin has the manager role
        assert(masterRegistry.hasRole(managerRole, users["admin"]));

        // Renouce the manager role from the admin
        masterRegistry.renounceRole(managerRole, users["admin"]);

        // Check the user no longer has the manager role
        assert(!masterRegistry.hasRole(managerRole, users["admin"]));
    }

    function test_renouceRole_adminRole() public {
        // Check the user has the admin role
        assert(masterRegistry.hasRole(adminRole, users["admin"]));

        // Renouce the admin role from the admin
        masterRegistry.renounceRole(adminRole, users["admin"]);

        // Check the user no longer has the admin role
        assert(!masterRegistry.hasRole(adminRole, users["admin"]));
    }

    function testFuzz_multicall_addRegistry(bytes32 name, bytes32 name2, address addr, address addr2) public {
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(name != name2);
        vm.assume(addr != addr2);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(masterRegistry.addRegistry.selector, name, addr);
        calls[1] = abi.encodeWithSelector(masterRegistry.addRegistry.selector, name2, addr2);
        masterRegistry.multicall(calls);
        assertEq(masterRegistry.resolveNameToLatestAddress(name), addr);
        assertEq(masterRegistry.resolveNameToLatestAddress(name2), addr2);
    }

    function testFuzz_multicall_updateRegistry(
        bytes32 name,
        bytes32 name2,
        address addr,
        address addr2,
        address addr3,
        address addr4
    )
        public
    {
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr3 != address(0));
        vm.assume(addr4 != address(0));
        vm.assume(name != name2);
        vm.assume(addr != addr2);
        vm.assume(addr != addr3);
        vm.assume(addr != addr4);
        vm.assume(addr2 != addr3);
        vm.assume(addr2 != addr4);
        vm.assume(addr3 != addr4);
        masterRegistry.addRegistry(name, addr);
        masterRegistry.addRegistry(name2, addr2);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(masterRegistry.updateRegistry.selector, name, addr3);
        calls[1] = abi.encodeWithSelector(masterRegistry.updateRegistry.selector, name2, addr4);
        masterRegistry.multicall(calls);
        assertEq(masterRegistry.resolveNameAndVersionToAddress(name, 0), addr);
        assertEq(masterRegistry.resolveNameAndVersionToAddress(name2, 0), addr2);
        assertEq(masterRegistry.resolveNameToLatestAddress(name), addr3);
        assertEq(masterRegistry.resolveNameToLatestAddress(name2), addr4);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { Errors } from "src/libraries/Errors.sol";

contract MasterRegistry_Test is BaseTest {
    MasterRegistry public masterRegistry;

    address public admin;
    address public alice;

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        alice = createUser("alice");
        masterRegistry = new MasterRegistry(admin, address(this));
    }

    function test_init() public view {
        assert(masterRegistry.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assert(masterRegistry.hasRole(_MANAGER_ROLE, admin));
        assert(masterRegistry.hasRole(_MANAGER_ROLE, address(this)));
    }

    function test_addRegistry_revertWhen_CalledWithEmptyString(address addr) public {
        vm.assume(addr != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.NameEmpty.selector));
        masterRegistry.addRegistry("", addr);
    }

    function test_addRegistry_revertWhen_CalledWithEmptyAddress(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressEmpty.selector));
        masterRegistry.addRegistry(name, address(0));
    }

    function test_addRegistry_revertWhen_CalledWithDuplicateAddress(bytes32 name, bytes32 name2, address addr) public {
        vm.assume(name != name2);
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        masterRegistry.addRegistry(name, addr);
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicateRegistryAddress.selector, addr));
        masterRegistry.addRegistry(name2, addr);
    }

    function test_addRegistry_revertWhen_CalledWithDuplicateName(bytes32 name, address addr, address addr2) public {
        vm.assume(addr != addr2);
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));

        masterRegistry.addRegistry(name, addr);
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameFound.selector, name));
        masterRegistry.addRegistry(name, addr2);
    }

    function testFuzz_updateRegistry_revertWhen_CalledWithEmptyString(address addr) public {
        vm.assume(addr != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.NameEmpty.selector));
        masterRegistry.updateRegistry("", addr);
    }

    function testFuzz_updateRegistry_revertWhen_CalledWithEmptyAddress(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressEmpty.selector));
        masterRegistry.updateRegistry(name, address(0));
    }

    function testFuzz_updateRegistry_revertWhen_CalledWithDuplicateAddress(
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

    function test_updateRegistry_revertWhen_NameNotFound(bytes32 name, address addr) public {
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

    function testFuzz_resolveNameToLatestAddress_revertWhen_NameNotFound(bytes32 name) public {
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

    function testFuzz_resolveNameToAllAddresses_revertWhen_NamNotFound(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameNotFound.selector, name));
        masterRegistry.resolveNameToAllAddresses(name);
    }

    function testFuzz_resolveNameAndVersionToAddress_revertWhen_NameAndVersionNotFound(
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

    function testFuzz_resolveAddressToRegistryData_revertWhen_RegistryAddressNotFound(address addr) public {
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
        // Assume non-zero
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr3 != address(0));
        // Assume not equal
        vm.assume(name != name2);
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
        assertEq(masterRegistry.getRoleAdmin(_MANAGER_ROLE), bytes32(0));
    }

    function testFuzz_addRegistry_revertWhen_CalledByNonManager(bytes32 name, address addr) public {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(_formatAccessControlError(alice, _MANAGER_ROLE));
        masterRegistry.addRegistry(name, addr);
    }

    function testFuzz_updateRegistry_revertWhen_CalledByNonManager(bytes32 name, address addr, address addr2) public {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr != addr2);
        masterRegistry.addRegistry(name, addr);
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(_formatAccessControlError(alice, _MANAGER_ROLE));
        masterRegistry.updateRegistry(name, addr2);
    }

    // Try granting manager role from an account without admin role
    function test_grantRole_revertWhen_CalledByNonAdmin() public {
        vm.stopPrank();
        vm.startPrank(alice);
        // account is alice's address, role is bytes(0) as defined in the contract
        vm.expectRevert(_formatAccessControlError(alice, DEFAULT_ADMIN_ROLE));
        masterRegistry.grantRole(_MANAGER_ROLE, alice);
    }

    // Try granting manager role from an account with admin role
    function test_grantRole_managerRole() public {
        // Check the user does not have the manager role
        assert(!masterRegistry.hasRole(_MANAGER_ROLE, alice));

        // Grant the manager role to the user from the owner
        vm.prank(admin);
        masterRegistry.grantRole(_MANAGER_ROLE, alice);

        // Check the user now has the manager role
        assert(masterRegistry.hasRole(_MANAGER_ROLE, alice));
    }

    function test_grantRole_adminRole() public {
        // Check the user does not have the admin role
        assert(!masterRegistry.hasRole(DEFAULT_ADMIN_ROLE, alice));

        // Grant the admin role to the user from the owner
        vm.prank(admin);
        masterRegistry.grantRole(DEFAULT_ADMIN_ROLE, alice);

        // Check the user now has the admin role
        assert(masterRegistry.hasRole(DEFAULT_ADMIN_ROLE, alice));

        // Verify the user can grant the manager role
        vm.stopPrank();
        vm.prank(alice);
        masterRegistry.grantRole(_MANAGER_ROLE, users["bob"]);
    }

    function test_revokeRole_managerRole_revertWhen_RevokeRoleWithoutAdmin() public {
        vm.stopPrank();
        vm.startPrank(alice);
        // account is alice's address, role is bytes(0) as defined in the contract
        vm.expectRevert(_formatAccessControlError(alice, DEFAULT_ADMIN_ROLE));
        masterRegistry.revokeRole(_MANAGER_ROLE, admin);
        vm.stopPrank();
    }

    function test_revokeRole_adminRole() public {
        // Check the user does not have the admin role
        assert(!masterRegistry.hasRole(DEFAULT_ADMIN_ROLE, alice));

        // Grant the admin role to the user from the owner
        vm.prank(admin);
        masterRegistry.grantRole(DEFAULT_ADMIN_ROLE, alice);

        // Check the user now has the admin role
        assert(masterRegistry.hasRole(DEFAULT_ADMIN_ROLE, alice));

        // Revoke the admin role from the user from the owner
        vm.prank(admin);
        masterRegistry.revokeRole(DEFAULT_ADMIN_ROLE, alice);

        // Check the user no longer has the admin role
        assert(!masterRegistry.hasRole(DEFAULT_ADMIN_ROLE, alice));
    }

    function test_revokeRoleF_adminRole() public {
        // Check the user does not have the admin role
        assert(!masterRegistry.hasRole(DEFAULT_ADMIN_ROLE, alice));

        // Grant the admin role to the user from the owner
        vm.prank(admin);
        masterRegistry.grantRole(DEFAULT_ADMIN_ROLE, alice);

        // Check the user now has the admin role
        assert(masterRegistry.hasRole(DEFAULT_ADMIN_ROLE, alice));

        // Revoke the admin role from the user from the owner
        vm.stopPrank();
        vm.prank(alice);
        masterRegistry.revokeRole(DEFAULT_ADMIN_ROLE, alice);

        // Check the user no longer has the admin role
        assert(!masterRegistry.hasRole(DEFAULT_ADMIN_ROLE, alice));
    }

    function test_renouceRole_managerRole() public {
        // Check the admin has the manager role
        assert(masterRegistry.hasRole(_MANAGER_ROLE, admin));

        // Renouce the manager role from the admin
        vm.prank(admin);
        masterRegistry.renounceRole(_MANAGER_ROLE, admin);

        // Check the user no longer has the manager role
        assert(!masterRegistry.hasRole(_MANAGER_ROLE, admin));
    }

    function test_renouceRole_adminRole() public {
        // Check the user has the admin role
        assert(masterRegistry.hasRole(DEFAULT_ADMIN_ROLE, admin));

        // Renouce the admin role from the admin
        vm.prank(admin);
        masterRegistry.renounceRole(DEFAULT_ADMIN_ROLE, admin);

        // Check the user no longer has the admin role
        assert(!masterRegistry.hasRole(DEFAULT_ADMIN_ROLE, admin));
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

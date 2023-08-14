// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { BasketRegistry } from "src/BasketRegistry.sol";
import { Deployments } from "script/Deployments.s.sol";
import { Errors } from "src/libraries/Errors.sol";

contract BasketRegistryTest is BaseTest {
    BasketRegistry public basketRegistry;
    bytes32 public adminRole;
    bytes32 public managerRole;

    function setUp() public override {
        super.setUp();
        vm.startPrank(users["admin"]);
        basketRegistry = new BasketRegistry(users["admin"]);
        adminRole = basketRegistry.DEFAULT_ADMIN_ROLE();
        managerRole = basketRegistry.PROTOCOL_MANAGER_ROLE();
    }

    function test_init() public view {
        assert(basketRegistry.hasRole(adminRole, users["admin"]));
        assert(basketRegistry.hasRole(managerRole, users["admin"]));
    }

    function test_revertWhenCalledWithEmptyString_addRegistry(address addr, address baseAsset) public {
        vm.assume(addr != address(0));
        vm.assume(baseAsset != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.NameEmpty.selector));
        basketRegistry.addRegistry("", addr, baseAsset);
    }

    function test_revertWhenCalledWithEmptyAddress_addRegistry(bytes32 name, address baseAsset) public {
        vm.assume(name != bytes32(0));
        vm.assume(baseAsset != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressEmpty.selector));
        basketRegistry.addRegistry(name, address(0), baseAsset);
    }

    function test_revertWhenCalledWithDuplicateAddress_addRegistry(
        bytes32 name,
        bytes32 name2,
        address addr,
        address baseAsset
    )
        public
    {
        vm.assume(name != name2);
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(baseAsset != address(0));

        basketRegistry.addRegistry(name, addr, baseAsset);
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicateRegistryAddress.selector, addr));
        basketRegistry.addRegistry(name2, addr, baseAsset);
    }

    function test_revertWhenCalledWithDuplicateName_addRegistry(
        bytes32 name,
        address addr,
        address addr2,
        address baseAsset
    )
        public
    {
        vm.assume(addr != addr2);
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(baseAsset != address(0));

        basketRegistry.addRegistry(name, addr, baseAsset);
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameFound.selector, name));
        basketRegistry.addRegistry(name, addr2, baseAsset);
    }

    function testFuzz_revertWhenCalledWithEmptyString_updateRegistry(address addr, address baseAsset) public {
        vm.assume(addr != address(0));
        vm.assume(baseAsset != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.NameEmpty.selector));
        basketRegistry.updateRegistry("", addr, baseAsset);
    }

    function testFuzz_revertWhenCalledWithEmptyAddress_updateRegistry(bytes32 name, address baseAsset) public {
        vm.assume(name != bytes32(0));
        vm.assume(baseAsset != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressEmpty.selector));
        basketRegistry.updateRegistry(name, address(0), baseAsset);
    }

    function testFuzz_revertWhenCalledWithDuplicateAddress_updateRegistry(
        bytes32 name,
        bytes32 name2,
        address addr,
        address addr2,
        address baseAsset
    )
        public
    {
        vm.assume(addr != addr2);
        vm.assume(name != name2);
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(baseAsset != address(0));
        basketRegistry.addRegistry(name, addr, baseAsset);
        basketRegistry.addRegistry(name2, addr2, baseAsset);
        vm.expectRevert(abi.encodeWithSelector(Errors.DuplicateRegistryAddress.selector, addr2));
        basketRegistry.updateRegistry(name, addr2, baseAsset);
    }

    function test_revertWhenNameNotFound_updateRegistry(bytes32 name, address addr, address baseAsset) public {
        vm.assume(addr != address(0));
        vm.assume(name != bytes32(0));
        vm.assume(baseAsset != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameNotFound.selector, name));
        basketRegistry.updateRegistry(name, addr, baseAsset);
    }

    function testFuzz_addRegistry(bytes32 name, address addr, address baseAsset) public {
        vm.assume(addr != address(0));
        vm.assume(name != bytes32(0));
        vm.assume(baseAsset != address(0));
        basketRegistry.addRegistry(name, addr, baseAsset);
        assertEq(basketRegistry.resolveNameToLatestAddress(name), addr);
    }

    function testFuzz_updateRegistry(bytes32 name, address addr, address addr2, address baseAsset) public {
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(name != bytes32(0));
        vm.assume(addr != addr2);
        vm.assume(baseAsset != address(0));
        basketRegistry.addRegistry(name, addr, baseAsset);
        basketRegistry.updateRegistry(name, addr2, baseAsset);
        assertEq(basketRegistry.resolveNameToLatestAddress(name), addr2);
    }

    function testFuzz_revertWhenNameNotFound_resolveNameToLatestAddress(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameNotFound.selector, name));
        basketRegistry.resolveNameToLatestAddress(name);
    }

    function testFuzz_resolveNameToAllAddresses(bytes32 name, address addr, address addr2, address baseAsset) public {
        vm.assume(addr != addr2);
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(baseAsset != address(0));
        basketRegistry.addRegistry(name, addr, baseAsset);
        basketRegistry.updateRegistry(name, addr2, baseAsset);
        address[] memory res = basketRegistry.resolveNameToAllAddresses(name);
        assertEq(res[0], addr);
        assertEq(res[1], addr2);
    }

    function testFuzz_revertWhenNamNotFound_resolveNameToAllAddresses(bytes32 name) public {
        vm.assume(name != bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameNotFound.selector, name));
        basketRegistry.resolveNameToAllAddresses(name);
    }

    function testFuzz_revertWhenNameAndVersionNotFound_resolveNameAndVersionToAddress(
        bytes32 name,
        address addr,
        address baseAsset
    )
        public
    {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(baseAsset != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameVersionNotFound.selector, name, 0));
        basketRegistry.resolveNameAndVersionToAddress(name, 0);
        basketRegistry.addRegistry(name, addr, baseAsset);
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryNameVersionNotFound.selector, name, 1));
        basketRegistry.resolveNameAndVersionToAddress(name, 1);
    }

    function testFuzz_resolveNameAndVersionToAddress(
        bytes32 name,
        address addr,
        address addr2,
        address baseAsset
    )
        public
    {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr != addr2);
        vm.assume(baseAsset != address(0));
        basketRegistry.addRegistry(name, addr, baseAsset);
        basketRegistry.updateRegistry(name, addr2, baseAsset);
        assertEq(basketRegistry.resolveNameAndVersionToAddress(name, 0), addr);
        assertEq(basketRegistry.resolveNameAndVersionToAddress(name, 1), addr2);
    }

    function testFuzz_revertWhenRegistryAddressNotFound_resolveAddressToRegistryData(address addr) public {
        vm.assume(addr != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.RegistryAddressNotFound.selector, addr));
        basketRegistry.resolveAddressToRegistryData(addr);
    }

    function testFuzz_resolveAddressToRegistryData(
        bytes32 name,
        bytes32 name2,
        address addr,
        address addr2,
        address addr3,
        address baseAsset
    )
        public
    {
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr3 != address(0));
        vm.assume(addr != addr2);
        vm.assume(addr != addr3);
        vm.assume(addr2 != addr3);
        vm.assume(baseAsset != address(0));
        basketRegistry.addRegistry(name, addr, baseAsset);
        basketRegistry.updateRegistry(name, addr2, baseAsset);
        basketRegistry.addRegistry(name2, addr3, baseAsset);
        (bytes32 resloveName, address registryBaseAsset, uint256 version, bool isLatest) =
            basketRegistry.resolveAddressToRegistryData(addr);
        assertEq(resloveName, name);
        assertEq(registryBaseAsset, baseAsset);
        assertEq(version, 0);
        assertEq(isLatest, false);
        (resloveName, registryBaseAsset, version, isLatest) = basketRegistry.resolveAddressToRegistryData(addr2);
        assertEq(resloveName, name);
        assertEq(registryBaseAsset, baseAsset);
        assertEq(version, 1);
        assertEq(isLatest, true);
        (resloveName, registryBaseAsset, version, isLatest) = basketRegistry.resolveAddressToRegistryData(addr3);
        assertEq(resloveName, name2);
        assertEq(registryBaseAsset, baseAsset);
        assertEq(version, 0);
        assertEq(isLatest, true);
    }

    function test_getRoleAdmin_managerRole() public {
        assertEq(basketRegistry.getRoleAdmin(managerRole), bytes32(0));
    }

    function testFuzz_revertWhenCalledByNonManager_addRegistry(bytes32 name, address addr, address baseAsset) public {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(baseAsset != address(0));
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        vm.expectRevert(
            "AccessControl: account 0x328809bc894f92807417d2dad6b7c998c1afdac6 is missing role 0xda3bb1ed6d0047074a23ab55d6b8b4ebc655563ba5a668a4ed7540883cb393b0"
        );
        basketRegistry.addRegistry(name, addr, baseAsset);
    }

    function testFuzz_revertWhenCalledByNonManager_updateRegistry(
        bytes32 name,
        address addr,
        address addr2,
        address baseAsset
    )
        public
    {
        vm.assume(name != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr != addr2);
        vm.assume(baseAsset != address(0));
        basketRegistry.addRegistry(name, addr, baseAsset);
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        vm.expectRevert(
            "AccessControl: account 0x328809bc894f92807417d2dad6b7c998c1afdac6 is missing role 0xda3bb1ed6d0047074a23ab55d6b8b4ebc655563ba5a668a4ed7540883cb393b0"
        );
        basketRegistry.updateRegistry(name, addr2, baseAsset);
    }

    function testFuzz_resolveBaseAssetToBaskets(
        bytes32 name,
        bytes32 name2,
        address addr,
        address addr2,
        address baseAsset
    )
        public
    {
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(name != name2);
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(addr != addr2);
        vm.assume(baseAsset != address(0));
        basketRegistry.addRegistry(name, addr, baseAsset);
        basketRegistry.addRegistry(name2, addr2, baseAsset);
        address[] memory baskets = basketRegistry.resolveBaseAssetToBaskets(baseAsset);
        assertEq(baskets.length, 2);
        assertEq(baskets[0], addr);
        assertEq(baskets[1], addr2);
    }

    function testFuzz_revertWhenBaseAssetNotFound_resolveBaseAssetToBaskets(bytes32 name, address baseAsset) public {
        vm.assume(name != bytes32(0));
        vm.assume(baseAsset != address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.BaseAssetNotFound.selector, baseAsset));
        basketRegistry.resolveBaseAssetToBaskets(baseAsset);
    }

    // Try granting manager role from an account without admin role
    function test_revertWhenCalledByNonAdmin_grantRole() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        vm.expectRevert(
            "AccessControl: account 0x328809bc894f92807417d2dad6b7c998c1afdac6 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        basketRegistry.grantRole(managerRole, users["alice"]);
    }

    // Try granting manager role from an account with admin role
    function test_grantRole_managerRole() public {
        // Check the user does not have the manager role
        assert(!basketRegistry.hasRole(managerRole, users["alice"]));

        // Grant the manager role to the user from the owner
        basketRegistry.grantRole(managerRole, users["alice"]);

        // Check the user now has the manager role
        assert(basketRegistry.hasRole(managerRole, users["alice"]));
    }

    function test_grantRole_adminRole() public {
        // Check the user does not have the admin role
        assert(!basketRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner
        basketRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(basketRegistry.hasRole(adminRole, users["alice"]));

        // Verify the user can grant the manager role
        vm.stopPrank();
        vm.prank(users["alice"]);
        basketRegistry.grantRole(managerRole, users["bob"]);
    }

    function test_revertWhenRevokeRoleWithoutAdmin_revokeRole_managerRole() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        vm.expectRevert(
            "AccessControl: account 0x328809bc894f92807417d2dad6b7c998c1afdac6 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        basketRegistry.revokeRole(managerRole, users["admin"]);
        vm.stopPrank();
    }

    function test_revokeRole_adminRole() public {
        // Check the user does not have the admin role
        assert(!basketRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner
        basketRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(basketRegistry.hasRole(adminRole, users["alice"]));

        // Revoke the admin role from the user from the owner
        basketRegistry.revokeRole(adminRole, users["alice"]);

        // Check the user no longer has the admin role
        assert(!basketRegistry.hasRole(adminRole, users["alice"]));
    }

    function test_revokeRoleF_adminRole() public {
        // Check the user does not have the admin role
        assert(!basketRegistry.hasRole(adminRole, users["alice"]));

        // Grant the admin role to the user from the owner

        basketRegistry.grantRole(adminRole, users["alice"]);

        // Check the user now has the admin role
        assert(basketRegistry.hasRole(adminRole, users["alice"]));

        // Revoke the admin role from the user from the owner
        vm.stopPrank();
        vm.prank(users["alice"]);
        basketRegistry.revokeRole(adminRole, users["alice"]);

        // Check the user no longer has the admin role
        assert(!basketRegistry.hasRole(adminRole, users["alice"]));
    }

    function test_renouceRole_managerRole() public {
        // Check the admin has the manager role
        assert(basketRegistry.hasRole(managerRole, users["admin"]));

        // Renouce the manager role from the admin
        basketRegistry.renounceRole(managerRole, users["admin"]);

        // Check the user no longer has the manager role
        assert(!basketRegistry.hasRole(managerRole, users["admin"]));
    }

    function test_renouceRole_adminRole() public {
        // Check the user has the admin role
        assert(basketRegistry.hasRole(adminRole, users["admin"]));

        // Renouce the admin role from the admin
        basketRegistry.renounceRole(adminRole, users["admin"]);

        // Check the user no longer has the admin role
        assert(!basketRegistry.hasRole(adminRole, users["admin"]));
    }

    function testFuzz_multicall_addRegistry(
        bytes32 name,
        bytes32 name2,
        address addr,
        address addr2,
        address baseAsset
    )
        public
    {
        vm.assume(name != bytes32(0));
        vm.assume(name2 != bytes32(0));
        vm.assume(addr != address(0));
        vm.assume(addr2 != address(0));
        vm.assume(name != name2);
        vm.assume(addr != addr2);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(basketRegistry.addRegistry.selector, name, addr, baseAsset);
        calls[1] = abi.encodeWithSelector(basketRegistry.addRegistry.selector, name2, addr2, baseAsset);
        basketRegistry.multicall(calls);
        assertEq(basketRegistry.resolveNameToLatestAddress(name), addr);
        assertEq(basketRegistry.resolveNameToLatestAddress(name2), addr2);
    }

    function testFuzz_multicall_updateRegistry(
        bytes32 name,
        bytes32 name2,
        address addr,
        address addr2,
        address addr3,
        address addr4,
        address baseAsset
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
        vm.assume(baseAsset != address(0));
        basketRegistry.addRegistry(name, addr, baseAsset);
        basketRegistry.addRegistry(name2, addr2, baseAsset);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(basketRegistry.updateRegistry.selector, name, addr3, baseAsset);
        calls[1] = abi.encodeWithSelector(basketRegistry.updateRegistry.selector, name2, addr4, baseAsset);
        basketRegistry.multicall(calls);
        assertEq(basketRegistry.resolveNameAndVersionToAddress(name, 0), addr);
        assertEq(basketRegistry.resolveNameAndVersionToAddress(name2, 0), addr2);
        assertEq(basketRegistry.resolveNameToLatestAddress(name), addr3);
        assertEq(basketRegistry.resolveNameToLatestAddress(name2), addr4);
    }
}

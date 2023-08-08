// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { BaseTest } from "../../utils/BaseTest.t.sol";
import { BasketRegistry } from "src/BasketRegistry.sol";

contract BasketRegistryTest is BaseTest {
    BasketRegistry public basketRegistry;
    bytes32 public adminRole;
    bytes32 public managerRole;
    address public constant BASE_ASSET_ADDRESS = address(123);

    function setUp() public override {
        super.setUp();
        vm.startPrank(users["admin"]);
        basketRegistry = new BasketRegistry(users["admin"]);
        adminRole = basketRegistry.DEFAULT_ADMIN_ROLE();
        managerRole = basketRegistry.PROTOCOL_MANAGER_ROLE();
    }

    function testInit() public view {
        assert(basketRegistry.hasRole(adminRole, users["admin"]));
        assert(basketRegistry.hasRole(managerRole, users["admin"]));
    }

    function testEmptyStringAdd() public {
        vm.expectRevert("MR: name cannot be empty");
        basketRegistry.addBasket("", address(1), BASE_ASSET_ADDRESS);
    }

    function testEmptyAddressAdd() public {
        vm.expectRevert("MR: address cannot be empty");
        basketRegistry.addBasket("test", address(0), BASE_ASSET_ADDRESS);
    }

    function testDuplicateAddressAdd() public {
        basketRegistry.addBasket("test", address(1), BASE_ASSET_ADDRESS);
        vm.expectRevert("MR: duplicate registry address");
        basketRegistry.addBasket("test2", address(1), BASE_ASSET_ADDRESS);
    }

    function testDuplicateAddBasket() public {
        basketRegistry.addBasket("test", address(1), BASE_ASSET_ADDRESS);
        vm.expectRevert("MR: basket name found, please use updateBasket");
        basketRegistry.addBasket("test", address(2), BASE_ASSET_ADDRESS);
    }

    function testEmptyStringUpdate() public {
        vm.expectRevert("MR: name cannot be empty");
        basketRegistry.updateBasket("", address(1), BASE_ASSET_ADDRESS);
    }

    function testEmptyAddressUpdate() public {
        vm.expectRevert("MR: address cannot be empty");
        basketRegistry.updateBasket("test", address(0), BASE_ASSET_ADDRESS);
    }

    function testDuplicateAddressUpdate() public {
        basketRegistry.addBasket("test", address(1), BASE_ASSET_ADDRESS);
        basketRegistry.addBasket("test2", address(2), BASE_ASSET_ADDRESS);
        vm.expectRevert("MR: duplicate registry address");
        basketRegistry.updateBasket("test", address(1), BASE_ASSET_ADDRESS);
    }

    function testNonExistantUpdate() public {
        vm.expectRevert("MR: basket entry does not exist, please use addBasket");
        basketRegistry.updateBasket("test", address(1), BASE_ASSET_ADDRESS);
    }

    function testAddRegistry() public {
        basketRegistry.addBasket("test1", address(1), BASE_ASSET_ADDRESS);
        assertEq(basketRegistry.resolveNameToLatestAddress("test1"), address(1));
    }

    function testAddRegistryWithSameName() public {
        basketRegistry.addBasket("test1", address(1), BASE_ASSET_ADDRESS);
        basketRegistry.updateBasket("test1", address(2), BASE_ASSET_ADDRESS);
        assertEq(basketRegistry.resolveNameToLatestAddress("test1"), address(2));
    }

    function testResolveNameToLatestNotFoundName() public {
        vm.expectRevert("MR: no match found for name");
        basketRegistry.resolveNameToLatestAddress("test1");
    }

    function testResolveToAllAddressesNotFoundName() public {
        vm.expectRevert("MR: no match found for name");
        basketRegistry.resolveNameToAllAddresses("test1");
    }

    function testResolveNameToAllAddresses() public {
        basketRegistry.addBasket("test1", address(1), BASE_ASSET_ADDRESS);
        basketRegistry.updateBasket("test1", address(2), BASE_ASSET_ADDRESS);
        basketRegistry.resolveNameToAllAddresses("test1");
        address[] memory res = basketRegistry.resolveNameToAllAddresses("test1");
        assertEq(res[0], address(1));
        assertEq(res[1], address(2));
    }

    function testResolveNameAndVersionAddresseNotFound() public {
        vm.expectRevert("MR: no match found for name and version");
        basketRegistry.resolveNameAndVersionToAddress("test1", 0);
        basketRegistry.addBasket("test1", address(1), BASE_ASSET_ADDRESS);
        vm.expectRevert("MR: no match found for name and version");
        basketRegistry.resolveNameAndVersionToAddress("test1", 1);
    }

    function testResolveNameAndVersionToAddress() public {
        basketRegistry.addBasket("test1", address(1), BASE_ASSET_ADDRESS);
        basketRegistry.updateBasket("test1", address(2), BASE_ASSET_ADDRESS);
        assertEq(basketRegistry.resolveNameAndVersionToAddress("test1", 0), address(1));
        assertEq(basketRegistry.resolveNameAndVersionToAddress("test1", 1), address(2));
    }

    function testResolveAddressToRegistryNotFound() public {
        vm.expectRevert("MR: no match found for address");
        basketRegistry.resolveAddressToRegistryData(address(1));
    }

    function testResolveAddressToRegistryData() public {
        basketRegistry.addBasket("test1", address(1), BASE_ASSET_ADDRESS);
        basketRegistry.updateBasket("test1", address(2), BASE_ASSET_ADDRESS);
        basketRegistry.addBasket("test2", address(3), BASE_ASSET_ADDRESS);
        (bytes32 name, uint256 version, address baseAsset, bool isLatest) =
            basketRegistry.resolveAddressToRegistryData(address(1));
        assertEq(name, "test1");
        assertEq(version, 0);
        assertEq(baseAsset, BASE_ASSET_ADDRESS);
        assertEq(isLatest, false);
        (name, version, baseAsset, isLatest) = basketRegistry.resolveAddressToRegistryData(address(2));
        assertEq(name, "test1");
        assertEq(version, 1);
        assertEq(baseAsset, BASE_ASSET_ADDRESS);
        assertEq(isLatest, true);
        (name, version, baseAsset, isLatest) = basketRegistry.resolveAddressToRegistryData(address(3));
        assertEq(name, "test2");
        assertEq(version, 0);
        assertEq(baseAsset, BASE_ASSET_ADDRESS);
        assertEq(isLatest, true);
    }

    function testResolveBaseAssetToBasketsZeroAddress() public {
        vm.expectRevert("MR: baseAsset cannot be empty");
        basketRegistry.resolveBaseAssetToBaskets(address(0));
    }

    function testResolveBaseAssetToBasketsNotFound() public {
        vm.expectRevert("MR: no match found for baseAsset");
        basketRegistry.resolveBaseAssetToBaskets(address(1));
    }

    function testResolveBaseAssetToBaskets() public {
        basketRegistry.addBasket("test1", address(1), BASE_ASSET_ADDRESS);
        basketRegistry.addBasket("test2", address(2), BASE_ASSET_ADDRESS);
        basketRegistry.addBasket("test3", address(3), address(1));
        address[] memory res = basketRegistry.resolveBaseAssetToBaskets(BASE_ASSET_ADDRESS);
        assertEq(res[0], address(1));
        assertEq(res[1], address(2));
    }

    function testManagerRole() public {
        assertEq(basketRegistry.getRoleAdmin(managerRole), bytes32(0));
    }

    function testAddRegistryPermissions() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        vm.expectRevert("MR: msg.sender is not allowed");
        basketRegistry.addBasket("test1", address(1), BASE_ASSET_ADDRESS);
    }

    function testUpdateRegistryPermissions() public {
        basketRegistry.addBasket("test1", address(1), BASE_ASSET_ADDRESS);
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        vm.expectRevert("MR: msg.sender is not allowed");
        basketRegistry.updateBasket("test1", address(2), BASE_ASSET_ADDRESS);
    }

    // Try granting manager role from an account without admin role
    function testGrantManagerRoleWithoutAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        vm.expectRevert(
            "AccessControl: account 0x328809bc894f92807417d2dad6b7c998c1afdac6 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        basketRegistry.grantRole(managerRole, users["alice"]);
    }

    // Try granting manager role from an account with admin role
    function testGrantManagerRoleWithAdmin() public {
        // Check the user does not have the manager role
        assert(!basketRegistry.hasRole(managerRole, users["alice"]));

        // Grant the manager role to the user from the owner
        basketRegistry.grantRole(managerRole, users["alice"]);

        // Check the user now has the manager role
        assert(basketRegistry.hasRole(managerRole, users["alice"]));
    }

    function testGrantAdminRole() public {
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

    function testRevokeRoleWithoutAdmin() public {
        vm.stopPrank();
        vm.startPrank(users["alice"]);
        // account is users["alice"]'s address, role is bytes(0) as defined in the contract
        vm.expectRevert(
            "AccessControl: account 0x328809bc894f92807417d2dad6b7c998c1afdac6 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        basketRegistry.revokeRole(managerRole, users["admin"]);
        vm.stopPrank();
    }

    function testRevokeRole() public {
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

    function testRevokeRoleFromSelf() public {
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

    function testRenouceRoleManager() public {
        // Check the admin has the manager role
        assert(basketRegistry.hasRole(managerRole, users["admin"]));

        // Renouce the manager role from the admin
        basketRegistry.renounceRole(managerRole, users["admin"]);

        // Check the user no longer has the manager role
        assert(!basketRegistry.hasRole(managerRole, users["admin"]));
    }

    function testRenouceRoleAdmin() public {
        // Check the user has the admin role
        assert(basketRegistry.hasRole(adminRole, users["admin"]));

        // Renouce the admin role from the admin
        basketRegistry.renounceRole(adminRole, users["admin"]);

        // Check the user no longer has the admin role
        assert(!basketRegistry.hasRole(adminRole, users["admin"]));
    }
}

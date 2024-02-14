// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { CoveToken } from "src/governance/CoveToken.sol";
import { Errors } from "src/libraries/Errors.sol";

contract CoveTokenTest is BaseTest {
    CoveToken public coveToken;
    address public owner;
    address public alice;
    address public bob;
    bytes32 public minterRole = keccak256("MINTER_ROLE");

    function setUp() public override {
        owner = createUser("Owner");
        alice = createUser("Alice");
        bob = createUser("Bob");
        coveToken = new CoveToken(owner, block.timestamp + 365 days);
        vm.prank(owner);
        coveToken.grantRole(minterRole, owner);
    }

    function test_initialize() public {
        require(coveToken.hasRole(coveToken.DEFAULT_ADMIN_ROLE(), owner), "Owner should have DEFAULT_ADMIN_ROLE");
        assertEq(coveToken.mintingAllowedAfter(), block.timestamp + 365 days);
        require(coveToken.allowedTransferrer(owner), "Owner should be allowed to transfer");
        assertEq(coveToken.paused(), true, "Contract should be paused");
        assertEq(coveToken.balanceOf(owner), 1_000_000_000 ether, "Owner should have initial supply");
    }

    function test_initialize_revertsWhen_mintingAllowedTooEarly() public {
        vm.expectRevert(Errors.MintingAllowedTooEarly.selector);
        new CoveToken(owner, block.timestamp - 1);
    }

    function testFuzz_mint(uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        amount = bound(amount, 0, coveToken.availableSupplyToMint());
        uint256 balanceBefore = coveToken.balanceOf(alice);
        vm.startPrank(owner);
        coveToken.mint(alice, amount);
        assertEq(coveToken.balanceOf(alice), balanceBefore + amount, "Alice should have received the minted tokens");
    }

    function testFuzz_mint_revertsWhen_inflationTooEarly(uint256 amount) public {
        vm.assume(amount > 0);
        vm.warp(coveToken.mintingAllowedAfter() - 1);
        vm.expectRevert(Errors.InflationTooLarge.selector);
        vm.startPrank(owner);
        coveToken.mint(alice, amount);
    }

    function tesFuzz_mint_revertsWhen_inflationTooLarge(uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        amount = bound(amount, coveToken.availableSupplyToMint() + 1, type(uint256).max);
        vm.expectRevert(Errors.InflationTooLarge.selector);
        vm.startPrank(owner);
        coveToken.mint(alice, amount);
    }

    function testFuzz_mint_revertsWhen_notMinter(uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        amount = bound(amount, 0, coveToken.availableSupplyToMint());
        vm.expectRevert(_formatAccessControlError(alice, minterRole));
        vm.startPrank(alice);
        coveToken.mint(alice, amount);
    }

    function test_unpause_owner() public {
        vm.warp(coveToken.ownerCanUnpauseAfter());
        vm.startPrank(owner);
        coveToken.unpause();
        assertEq(coveToken.paused(), false, "Contract should be unpaused");
    }

    function test_unpause_anyone() public {
        vm.warp(coveToken.anyoneCanUnpauseAfter());
        vm.startPrank(alice);
        coveToken.unpause();
        assertFalse(coveToken.paused());
    }

    function test_unpause_revertsWhen_tooEarly() public {
        vm.prank(owner);
        vm.expectRevert(Errors.UnpauseTooEarly.selector);
        coveToken.unpause();
        vm.warp(coveToken.ownerCanUnpauseAfter());
        vm.prank(alice);
        vm.expectRevert(Errors.UnpauseTooEarly.selector);
        coveToken.unpause();
    }

    function test_unpause_revertsWhen_notAdmin() public {
        vm.warp(coveToken.ownerCanUnpauseAfter());
        vm.expectRevert(Errors.UnpauseTooEarly.selector);
        vm.startPrank(alice);
        coveToken.unpause();
    }

    function testFuzz_addAllowedTransferee(uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        amount = bound(amount, 0, coveToken.availableSupplyToMint());
        vm.startPrank(owner);
        coveToken.addAllowedTransferee(alice);
        assertTrue(coveToken.allowedTransferee(alice));
        vm.stopPrank();
        uint256 balanceBefore = coveToken.balanceOf(alice);
        vm.prank(owner);
        assertTrue(coveToken.transfer(bob, amount));
        vm.prank(bob);
        coveToken.transfer(alice, amount);
        assertEq(coveToken.balanceOf(alice), balanceBefore + amount);
    }

    function testFuzz_addAllowedTransferee_revertsWhen_notAdmin(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.expectRevert(_formatAccessControlError(user, coveToken.DEFAULT_ADMIN_ROLE()));
        vm.startPrank(user);
        coveToken.addAllowedTransferee(user);
    }

    function testFuzz_transfer_revertsWhen_notAllowedTransferee(uint256 amount) public {
        amount = bound(amount, 0, 1_000_000_000 ether);
        assertTrue(coveToken.paused(), "Contract should be paused");
        assertTrue(!coveToken.allowedTransferee(alice), "Alice should not be allowed to receive transfer");
        vm.prank(owner);
        coveToken.transfer(bob, amount);
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        vm.prank(bob);
        coveToken.transfer(alice, amount);
    }

    function testFuzz_removeAllowedTransferee(address user, uint256 amount) public {
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 1, 1_000_000_000 ether);
        vm.startPrank(owner);
        coveToken.addAllowedTransferee(user);
        assertTrue(coveToken.allowedTransferee(user), "User should be allowed to receive transfer");
        coveToken.removeAllowedTransferee(user);
        assertTrue(!coveToken.allowedTransferee(user), "User should not be allowed to receive transfer");
        assertTrue(coveToken.paused(), "Contract should be paused");
        assertTrue(!coveToken.allowedTransferrer(alice), "User should not be allowed to send transfer");
        coveToken.transfer(alice, amount);
        vm.stopPrank();
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        vm.prank(alice);
        coveToken.transfer(user, amount);
    }

    function testFuzz_removeFromAllowedTransferee_revertsWhen_notAdmin(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(owner);
        coveToken.addAllowedTransferee(user);
        vm.expectRevert(_formatAccessControlError(user, coveToken.DEFAULT_ADMIN_ROLE()));
        vm.startPrank(user);
        coveToken.removeAllowedTransferee(user);
    }

    function testFuzz_addAllowedTransferrer(address user, uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 0, coveToken.availableSupplyToMint());
        vm.startPrank(owner);
        coveToken.addAllowedTransferrer(user);
        assertTrue(coveToken.allowedTransferrer(user), "User should be allowed to transfer");
        coveToken.mint(user, amount);
        vm.stopPrank();
        vm.prank(user);
        assertTrue(coveToken.transfer(bob, amount), "User should be able to transfer");
    }

    function testFuzz_transfer_revertsWhen_notAllowedTransferrer(address user, uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 0, coveToken.availableSupplyToMint());
        vm.startPrank(owner);
        coveToken.addAllowedTransferee(user);
        coveToken.mint(user, amount);
        vm.stopPrank();
        vm.prank(user);
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        coveToken.transfer(owner, amount);
    }

    function testFuzz_addAllowedTransferrer_revertsWhen_notAdmin(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(user);
        vm.expectRevert(_formatAccessControlError(user, coveToken.DEFAULT_ADMIN_ROLE()));
        coveToken.addAllowedTransferrer(user);
    }

    function testFuzz_removeAllowedTransferrer(address user, uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 0, coveToken.availableSupplyToMint());
        vm.startPrank(owner);
        coveToken.addAllowedTransferrer(user);
        assertTrue(coveToken.allowedTransferrer(user), "User should be allowed to transfer");
        coveToken.removeAllowedTransferrer(user);
        assertTrue(!coveToken.allowedTransferrer(user), "User should not be allowed to transfer");
        coveToken.transfer(user, amount);
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        vm.stopPrank();
        vm.prank(user);
        coveToken.transfer(alice, amount);
    }

    function testFuzz_removeFromAllowedTransferrer_revertsWhen_notAdmin(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(owner);
        coveToken.addAllowedTransferrer(user);
        vm.expectRevert(_formatAccessControlError(user, coveToken.DEFAULT_ADMIN_ROLE()));
        vm.startPrank(user);
        coveToken.removeAllowedTransferrer(user);
    }
}

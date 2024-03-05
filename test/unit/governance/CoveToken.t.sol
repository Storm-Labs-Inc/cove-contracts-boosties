// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { CoveToken } from "src/governance/CoveToken.sol";
import { Errors } from "src/libraries/Errors.sol";

contract CoveToken_Test is BaseTest {
    CoveToken public coveToken;
    address public owner;
    address public alice;
    address public bob;
    bytes32 public minterRole = keccak256("MINTER_ROLE");
    uint256 public deployTimestamp;

    event TransferrerAllowed(address indexed target, uint256 eventId);
    event TransferrerDisallowed(address indexed target, uint256 eventId);
    event TransfereeAllowed(address indexed target, uint256 eventId);
    event TransfereeDisallowed(address indexed target, uint256 eventId);

    function setUp() public override {
        owner = createUser("Owner");
        alice = createUser("Alice");
        bob = createUser("Bob");
        coveToken = new CoveToken(owner);
        deployTimestamp = block.timestamp;
        vm.prank(owner);
        coveToken.grantRole(minterRole, owner);
    }

    function test_initialize() public {
        require(coveToken.hasRole(coveToken.DEFAULT_ADMIN_ROLE(), owner), "Owner should have DEFAULT_ADMIN_ROLE");
        assertEq(
            coveToken.mintingAllowedAfter(), block.timestamp + 3 * 52 weeks, "Minting should be allowed after 3 years"
        );
        require(coveToken.allowedTransferrer(owner), "Owner should be allowed to transfer");
        assertEq(coveToken.paused(), true, "Contract should be paused");
        assertEq(coveToken.balanceOf(owner), 1_000_000_000 ether, "Owner should have initial supply");
    }

    function test_availableSupplyToMint() public {
        uint256 totalSupply = coveToken.totalSupply();
        assertEq(coveToken.availableSupplyToMint(), 0, "Available supply to mint should be 0 before minting is allowed");

        vm.warp(coveToken.mintingAllowedAfter());
        assertEq(
            coveToken.availableSupplyToMint(),
            totalSupply * 600 / 10_000,
            "Available supply to mint should be 6% of the current supply"
        );
        vm.startPrank(owner);
        coveToken.grantRole(minterRole, owner);
        coveToken.mint(owner, coveToken.availableSupplyToMint());
        assertEq(
            coveToken.totalSupply(),
            totalSupply + totalSupply * 600 / 10_000,
            "Total supply should have increased by 6%"
        );
        totalSupply = coveToken.totalSupply();
        assertEq(coveToken.availableSupplyToMint(), 0, "Available supply to mint should be 0 after minting");

        vm.warp(coveToken.mintingAllowedAfter());
        assertEq(
            coveToken.availableSupplyToMint(),
            totalSupply * 600 / 10_000,
            "Available supply to mint should be 6% of the current supply"
        );
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

    function testFuzz_mint_revertsWhen_inflationTooLarge(uint256 amount) public {
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
        vm.warp(coveToken.OWNER_CAN_UNPAUSE_AFTER());
        vm.startPrank(owner);
        coveToken.unpause();
        assertEq(coveToken.paused(), false, "Contract should be unpaused");
    }

    function test_anyoneCanUnpauseAfter() public {
        assertEq(
            coveToken.ANYONE_CAN_UNPAUSE_AFTER(),
            deployTimestamp + 18 * 4 weeks,
            "ANYONE_CAN_UNPAUSE_AFTER should be 18 months after deployment"
        );
    }

    function test_ownerCanUnpauseAfter() public {
        assertEq(
            coveToken.OWNER_CAN_UNPAUSE_AFTER(),
            deployTimestamp + 6 * 4 weeks,
            "OWNER_CAN_UNPAUSE_AFTER should be 6 months after deployment"
        );
    }

    function test_unpause_anyone() public {
        vm.warp(coveToken.ANYONE_CAN_UNPAUSE_AFTER());
        vm.startPrank(alice);
        coveToken.unpause();
        assertFalse(coveToken.paused());
    }

    function test_unpause_anyoneCanTransfer(address user, address user2, uint256 amount) public {
        vm.assume(user != address(0) && user != owner);
        vm.assume(user2 != address(0) && user2 != owner);
        vm.warp(coveToken.ANYONE_CAN_UNPAUSE_AFTER());
        amount = bound(amount, 0, 1_000_000_000 ether);
        vm.prank(user);
        coveToken.unpause();
        assertFalse(coveToken.paused());
        vm.prank(owner);
        coveToken.transfer(user, amount);
        vm.prank(user);
        coveToken.transfer(user2, amount);
        assertEq(coveToken.balanceOf(user2), amount);
    }

    function test_unpause_revertsWhen_tooEarly() public {
        vm.prank(owner);
        vm.expectRevert(Errors.UnpauseTooEarly.selector);
        coveToken.unpause();
        vm.warp(coveToken.OWNER_CAN_UNPAUSE_AFTER());
        vm.prank(alice);
        vm.expectRevert(Errors.UnpauseTooEarly.selector);
        coveToken.unpause();
    }

    function test_unpause_revertsWhen_notAdmin() public {
        vm.warp(coveToken.OWNER_CAN_UNPAUSE_AFTER());
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

    function test_events_eventIdIncrements() public {
        vm.startPrank(owner);

        vm.expectEmit(false, false, false, true);
        // initialize adds the zero address and owner as transferrers so eventId starts at 2
        emit TransferrerAllowed(address(alice), 2);
        coveToken.addAllowedTransferrer(address(alice));

        vm.expectEmit(false, false, false, true);
        emit TransferrerDisallowed(address(alice), 3);
        coveToken.removeAllowedTransferrer(address(alice));

        vm.expectEmit(false, false, false, true);
        emit TransfereeAllowed(address(alice), 4);
        coveToken.addAllowedTransferee(address(alice));

        vm.expectEmit(false, false, false, true);
        emit TransfereeDisallowed(address(alice), 5);
        coveToken.removeAllowedTransferee(address(alice));
    }
}

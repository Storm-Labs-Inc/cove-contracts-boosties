// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { CoveTokenBazaarAuction } from "src/governance/CoveTokenBazaarAuction.sol";
import { Errors } from "src/libraries/Errors.sol";

contract CoveTokenBazaarAuction_Test is BaseTest {
    CoveTokenBazaarAuction public coveTokenBazaarAuction;
    address public owner;
    address public alice;
    address public bob;
    uint256 public deployTimestamp;

    uint256 public constant TOTAL_SUPPLY = 95_000_000 ether;
    bytes public constant OWNER_ERROR_MESSAGE = "Ownable: caller is not the owner";
    address public constant BAZAAR_AUCTION_FACTORY = 0x47612eabFbE65329AeD1ab1BF3FCbAE493aEf460;

    event SenderAllowed(address indexed target, uint256 eventId);
    event SenderDisallowed(address indexed target, uint256 eventId);
    event ReceiverAllowed(address indexed target, uint256 eventId);
    event ReceiverDisallowed(address indexed target, uint256 eventId);

    function setUp() public override {
        owner = createUser("Owner");
        alice = createUser("Alice");
        bob = createUser("Bob");
        coveTokenBazaarAuction = new CoveTokenBazaarAuction(owner);
    }

    function test_initialize() public {
        assertTrue(coveTokenBazaarAuction.allowedSender(address(0)), "zero address should be allowed to transfer");
        assertTrue(coveTokenBazaarAuction.allowedSender(owner), "Owner should be allowed to transfer");
        assertTrue(
            coveTokenBazaarAuction.allowedSender(BAZAAR_AUCTION_FACTORY),
            "Bazaar Auction Factory should be allowed to transfer"
        );
        assertEq(coveTokenBazaarAuction.balanceOf(owner), TOTAL_SUPPLY, "Owner should have total supply");
        assertEq(coveTokenBazaarAuction.totalSupply(), TOTAL_SUPPLY, "Total supply should be total supply");
        assertEq(coveTokenBazaarAuction.owner(), owner, "Owner should be the owner");
        assertEq(coveTokenBazaarAuction.symbol(), "COVE-BAZAAR", "Symbol should be COVE-BAZAAR");
        assertEq(
            coveTokenBazaarAuction.name(),
            "Cove DAO Bazaar Auction Token",
            "Name should be Cove DAO Bazaar Auction Token"
        );
    }

    function testFuzz_addAllowedReceiver(uint256 amount) public {
        amount = bound(amount, 1, TOTAL_SUPPLY);
        vm.startPrank(owner);
        coveTokenBazaarAuction.addAllowedReceiver(alice);
        assertTrue(coveTokenBazaarAuction.allowedReceiver(alice));
        vm.stopPrank();
        uint256 balanceBefore = coveTokenBazaarAuction.balanceOf(alice);
        vm.prank(owner);
        assertTrue(coveTokenBazaarAuction.transfer(bob, amount));
        vm.prank(bob);
        coveTokenBazaarAuction.transfer(alice, amount);
        assertEq(coveTokenBazaarAuction.balanceOf(alice), balanceBefore + amount);
    }

    function testFuzz_addAllowedReceiver_revertWhen_CannotBeBothSenderAndReceiver(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(owner);
        coveTokenBazaarAuction.addAllowedSender(user);
        vm.expectRevert(Errors.CannotBeBothSenderAndReceiver.selector);
        coveTokenBazaarAuction.addAllowedReceiver(user);
    }

    function testFuzz_addAllowedReceiver_revertWhen_CallerIsNotOwner(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.expectRevert(OWNER_ERROR_MESSAGE);
        vm.startPrank(user);
        coveTokenBazaarAuction.addAllowedReceiver(user);
    }

    function testFuzz_transfer_revertWhen_notAllowedReceiver(uint256 amount) public {
        amount = bound(amount, 0, TOTAL_SUPPLY);
        assertTrue(!coveTokenBazaarAuction.allowedReceiver(alice), "Alice should not be allowed to receive transfer");
        vm.prank(owner);
        coveTokenBazaarAuction.transfer(bob, amount);
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        vm.prank(bob);
        coveTokenBazaarAuction.transfer(alice, amount);
    }

    function testFuzz_removeAllowedReceiver(address user, uint256 amount) public {
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 1, TOTAL_SUPPLY);
        vm.startPrank(owner);
        coveTokenBazaarAuction.addAllowedReceiver(user);
        assertTrue(coveTokenBazaarAuction.allowedReceiver(user), "User should be allowed to receive transfer");
        coveTokenBazaarAuction.removeAllowedReceiver(user);
        assertTrue(!coveTokenBazaarAuction.allowedReceiver(user), "User should not be allowed to receive transfer");
        assertTrue(!coveTokenBazaarAuction.allowedSender(alice), "User should not be allowed to send transfer");
        coveTokenBazaarAuction.transfer(alice, amount);
        vm.stopPrank();
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        vm.prank(alice);
        coveTokenBazaarAuction.transfer(user, amount);
    }

    function testFuzz_removeFromAllowedReceiver_revertWhen_CallerIsNotOwner(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(owner);
        coveTokenBazaarAuction.addAllowedReceiver(user);
        vm.expectRevert(OWNER_ERROR_MESSAGE);
        vm.startPrank(user);
        coveTokenBazaarAuction.removeAllowedReceiver(user);
    }

    function testFuzz_addAllowedSender(address user, uint256 amount) public {
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 0, TOTAL_SUPPLY);
        vm.startPrank(owner);
        coveTokenBazaarAuction.addAllowedSender(user);
        assertTrue(coveTokenBazaarAuction.allowedSender(user), "User should be allowed to transfer");
        coveTokenBazaarAuction.transfer(user, amount);
        vm.stopPrank();
        vm.prank(user);
        assertTrue(coveTokenBazaarAuction.transfer(bob, amount), "User should be able to transfer");
    }

    function testFuzz_addAllowedSender_revertWhen_CannotBeBothSenderAndReceiver(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(owner);
        coveTokenBazaarAuction.addAllowedReceiver(user);
        vm.expectRevert(Errors.CannotBeBothSenderAndReceiver.selector);
        coveTokenBazaarAuction.addAllowedSender(user);
    }

    function testFuzz_transfer_revertWhen_notAllowedSender(address user, uint256 amount) public {
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 0, TOTAL_SUPPLY);
        vm.startPrank(owner);
        coveTokenBazaarAuction.addAllowedReceiver(user);
        vm.stopPrank();
        vm.prank(user);
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        coveTokenBazaarAuction.transfer(owner, amount);
    }

    function testFuzz_addAllowedSender_revertWhen_CallerIsNotOwner(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(user);
        vm.expectRevert(OWNER_ERROR_MESSAGE);
        coveTokenBazaarAuction.addAllowedSender(user);
    }

    function testFuzz_removeAllowedSender(address user, uint256 amount) public {
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 0, TOTAL_SUPPLY);
        vm.startPrank(owner);
        coveTokenBazaarAuction.addAllowedSender(user);
        assertTrue(coveTokenBazaarAuction.allowedSender(user), "User should be allowed to transfer");
        coveTokenBazaarAuction.removeAllowedSender(user);
        assertTrue(!coveTokenBazaarAuction.allowedSender(user), "User should not be allowed to transfer");
        coveTokenBazaarAuction.transfer(user, amount);
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        vm.stopPrank();
        vm.prank(user);
        coveTokenBazaarAuction.transfer(alice, amount);
    }

    function testFuzz_removeFromAllowedSender_revertWhen_CallerIsNotOwner(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(owner);
        coveTokenBazaarAuction.addAllowedSender(user);
        vm.expectRevert(OWNER_ERROR_MESSAGE);
        vm.startPrank(user);
        coveTokenBazaarAuction.removeAllowedSender(user);
    }

    function test_events_eventIdIncrements() public {
        vm.startPrank(owner);

        vm.expectEmit();
        // initialize adds the zero address and owner as transferrers so eventId starts at 3
        emit SenderAllowed(address(alice), 3);
        coveTokenBazaarAuction.addAllowedSender(address(alice));

        vm.expectEmit();
        emit SenderDisallowed(address(alice), 4);
        coveTokenBazaarAuction.removeAllowedSender(address(alice));

        vm.expectEmit();
        emit ReceiverAllowed(address(alice), 5);
        coveTokenBazaarAuction.addAllowedReceiver(address(alice));

        vm.expectEmit();
        emit ReceiverDisallowed(address(alice), 6);
        coveTokenBazaarAuction.removeAllowedReceiver(address(alice));
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { CoveToken } from "src/governance/CoveToken.sol";
import { Errors } from "src/libraries/Errors.sol";

contract CoveToken_Test is BaseTest {
    CoveToken public coveToken;
    address public owner;
    address public alice;
    address public bob;
    uint256 public deployTimestamp;

    event SenderAllowed(address indexed target, uint256 eventId);
    event SenderDisallowed(address indexed target, uint256 eventId);
    event ReceiverAllowed(address indexed target, uint256 eventId);
    event ReceiverDisallowed(address indexed target, uint256 eventId);

    function setUp() public override {
        owner = createUser("Owner");
        alice = createUser("Alice");
        bob = createUser("Bob");
        coveToken = new CoveToken(owner);
        deployTimestamp = block.timestamp;
        vm.prank(owner);
        coveToken.grantRole(MINTER_ROLE, owner);
    }

    function test_initialize() public {
        assertTrue(coveToken.hasRole(DEFAULT_ADMIN_ROLE, owner), "Owner should have DEFAULT_ADMIN_ROLE");
        assertTrue(coveToken.hasRole(TIMELOCK_ROLE, owner), "Owner should have TIMELOCK_ROLE");
        assertEq(
            coveToken.mintingAllowedAfter(), block.timestamp + 3 * 52 weeks, "Minting should be allowed after 3 years"
        );
        assertTrue(coveToken.allowedSender(owner), "Owner should be allowed to transfer");
        assertEq(coveToken.paused(), true, "Contract should be paused");
        assertEq(coveToken.balanceOf(owner), 1_000_000_000 ether, "Owner should have initial supply");
        assertEq(coveToken.CLOCK_MODE(), "mode=timestamp", "CLOCK_MODE should be mode=timestamp");
        assertEq(coveToken.clock(), block.timestamp, "Clock should return the current block timestamp");
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
        coveToken.grantRole(MINTER_ROLE, owner);
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

    function testFuzz_mint_revertWhen_inflationTooEarly(uint256 amount) public {
        vm.assume(amount > 0);
        vm.warp(coveToken.mintingAllowedAfter() - 1);
        vm.expectRevert(Errors.InflationTooLarge.selector);
        vm.startPrank(owner);
        coveToken.mint(alice, amount);
    }

    function testFuzz_mint_revertWhen_inflationTooLarge(uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        amount = bound(amount, coveToken.availableSupplyToMint() + 1, type(uint256).max);
        vm.expectRevert(Errors.InflationTooLarge.selector);
        vm.startPrank(owner);
        coveToken.mint(alice, amount);
    }

    function testFuzz_mint_revertWhen_notMinter(uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        amount = bound(amount, 0, coveToken.availableSupplyToMint());
        vm.expectRevert(_formatAccessControlError(alice, MINTER_ROLE));
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

    function test_unpause_revertWhen_tooEarly() public {
        vm.prank(owner);
        vm.expectRevert(Errors.UnpauseTooEarly.selector);
        coveToken.unpause();
        vm.warp(coveToken.OWNER_CAN_UNPAUSE_AFTER());
        vm.prank(alice);
        vm.expectRevert(Errors.UnpauseTooEarly.selector);
        coveToken.unpause();
    }

    function test_unpause_revertWhen_notAdmin() public {
        vm.warp(coveToken.OWNER_CAN_UNPAUSE_AFTER());
        vm.expectRevert(Errors.UnpauseTooEarly.selector);
        vm.startPrank(alice);
        coveToken.unpause();
    }

    function testFuzz_addAllowedReceiver(uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        amount = bound(amount, 0, coveToken.availableSupplyToMint());
        vm.startPrank(owner);
        coveToken.addAllowedReceiver(alice);
        assertTrue(coveToken.allowedReceiver(alice));
        vm.stopPrank();
        uint256 balanceBefore = coveToken.balanceOf(alice);
        vm.prank(owner);
        assertTrue(coveToken.transfer(bob, amount));
        vm.prank(bob);
        coveToken.transfer(alice, amount);
        assertEq(coveToken.balanceOf(alice), balanceBefore + amount);
    }

    function testFuzz_addAllowedReceiver_revertWhen_CannotBeBothSenderAndReceiver(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(owner);
        coveToken.addAllowedSender(user);
        vm.expectRevert(Errors.CannotBeBothSenderAndReceiver.selector);
        coveToken.addAllowedReceiver(user);
    }

    function testFuzz_addAllowedReceiver_revertWhen_CallerIsNotTimelock(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.expectRevert(_formatAccessControlError(user, TIMELOCK_ROLE));
        vm.startPrank(user);
        coveToken.addAllowedReceiver(user);
    }

    function testFuzz_transfer_revertWhen_notAllowedReceiver(uint256 amount) public {
        amount = bound(amount, 0, 1_000_000_000 ether);
        assertTrue(coveToken.paused(), "Contract should be paused");
        assertTrue(!coveToken.allowedReceiver(alice), "Alice should not be allowed to receive transfer");
        vm.prank(owner);
        coveToken.transfer(bob, amount);
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        vm.prank(bob);
        coveToken.transfer(alice, amount);
    }

    function testFuzz_removeAllowedReceiver(address user, uint256 amount) public {
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 1, 1_000_000_000 ether);
        vm.startPrank(owner);
        coveToken.addAllowedReceiver(user);
        assertTrue(coveToken.allowedReceiver(user), "User should be allowed to receive transfer");
        coveToken.removeAllowedReceiver(user);
        assertTrue(!coveToken.allowedReceiver(user), "User should not be allowed to receive transfer");
        assertTrue(coveToken.paused(), "Contract should be paused");
        assertTrue(!coveToken.allowedSender(alice), "User should not be allowed to send transfer");
        coveToken.transfer(alice, amount);
        vm.stopPrank();
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        vm.prank(alice);
        coveToken.transfer(user, amount);
    }

    function testFuzz_removeFromAllowedReceiver_revertWhen_CallerIsNotTimelock(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(owner);
        coveToken.addAllowedReceiver(user);
        vm.expectRevert(_formatAccessControlError(user, TIMELOCK_ROLE));
        vm.startPrank(user);
        coveToken.removeAllowedReceiver(user);
    }

    function testFuzz_addAllowedSender(address user, uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 0, coveToken.availableSupplyToMint());
        vm.startPrank(owner);
        coveToken.addAllowedSender(user);
        assertTrue(coveToken.allowedSender(user), "User should be allowed to transfer");
        coveToken.mint(user, amount);
        vm.stopPrank();
        vm.prank(user);
        assertTrue(coveToken.transfer(bob, amount), "User should be able to transfer");
    }

    function testFuzz_addAllowedSender_revertWhen_CannotBeBothSenderAndReceiver(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(owner);
        coveToken.addAllowedReceiver(user);
        vm.expectRevert(Errors.CannotBeBothSenderAndReceiver.selector);
        coveToken.addAllowedSender(user);
    }

    function testFuzz_transfer_revertWhen_notAllowedSender(address user, uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 0, coveToken.availableSupplyToMint());
        vm.startPrank(owner);
        coveToken.addAllowedReceiver(user);
        coveToken.mint(user, amount);
        vm.stopPrank();
        vm.prank(user);
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        coveToken.transfer(owner, amount);
    }

    function testFuzz_addAllowedSender_revertWhen_CallerIsNotTimelock(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(user);
        vm.expectRevert(_formatAccessControlError(user, TIMELOCK_ROLE));
        coveToken.addAllowedSender(user);
    }

    function testFuzz_removeAllowedSender(address user, uint256 amount) public {
        vm.warp(coveToken.mintingAllowedAfter());
        vm.assume(user != address(0) && user != owner);
        amount = bound(amount, 0, coveToken.availableSupplyToMint());
        vm.startPrank(owner);
        coveToken.addAllowedSender(user);
        assertTrue(coveToken.allowedSender(user), "User should be allowed to transfer");
        coveToken.removeAllowedSender(user);
        assertTrue(!coveToken.allowedSender(user), "User should not be allowed to transfer");
        coveToken.transfer(user, amount);
        vm.expectRevert(Errors.TransferNotAllowedYet.selector);
        vm.stopPrank();
        vm.prank(user);
        coveToken.transfer(alice, amount);
    }

    function testFuzz_removeFromAllowedSender_revertWhen_CallerIsNotTimelock(address user) public {
        vm.assume(user != address(0) && user != owner);
        vm.startPrank(owner);
        coveToken.addAllowedSender(user);
        vm.expectRevert(_formatAccessControlError(user, TIMELOCK_ROLE));
        vm.startPrank(user);
        coveToken.removeAllowedSender(user);
    }

    function test_events_eventIdIncrements() public {
        vm.startPrank(owner);

        vm.expectEmit();
        // initialize adds the zero address and owner as transferrers so eventId starts at 2
        emit SenderAllowed(address(alice), 2);
        coveToken.addAllowedSender(address(alice));

        vm.expectEmit();
        emit SenderDisallowed(address(alice), 3);
        coveToken.removeAllowedSender(address(alice));

        vm.expectEmit();
        emit ReceiverAllowed(address(alice), 4);
        coveToken.addAllowedReceiver(address(alice));

        vm.expectEmit();
        emit ReceiverDisallowed(address(alice), 5);
        coveToken.removeAllowedReceiver(address(alice));
    }

    function test_grantRole_TimelockRole_revertWhen_CallerIsNotTimelock() public {
        vm.prank(owner);
        coveToken.grantRole(DEFAULT_ADMIN_ROLE, alice);
        vm.expectRevert(_formatAccessControlError(alice, TIMELOCK_ROLE));
        vm.prank(alice);
        coveToken.grantRole(TIMELOCK_ROLE, alice);
    }

    function test_getVotes() public {
        // Set block number to 100
        vm.roll(100);

        // 0 Votes before any delegation
        assertEq(coveToken.getVotes(owner), 0, "Owner should have 0 votes");
        assertEq(coveToken.getVotes(alice), 0, "Alice should have 0 votes");

        // Owner delegates to self
        vm.startPrank(owner);
        coveToken.delegate(owner);

        // Check for votes after delegation
        assertEq(
            coveToken.getVotes(owner),
            1_000_000_000 ether,
            "Owner should have 1_000_000_000 votes after self-delegation"
        );
        uint256 t0 = block.timestamp;

        // Move time forward by 1 week
        vm.roll(block.number + _WEEK / 12);
        vm.warp(block.timestamp + _WEEK);

        // 1 week after delegation, votes should still be the same
        assertEq(coveToken.getVotes(owner), 1_000_000_000 ether, "Owner should have 1_000_000_000 votes after 1 week");

        // Transfer 500_000_000 tokens to Alice
        coveToken.transfer(alice, 500_000_000 ether);

        // Owner should have 500_000_000 votes after transfer
        // Alice should have 0 votes before delegation
        assertEq(coveToken.getVotes(owner), 500_000_000 ether, "Owner should have 500_000_000 votes after transfer");
        assertEq(coveToken.getVotes(alice), 0, "Alice should have 0 votes before delegation");
        uint256 t1 = block.timestamp;

        assertEq(coveToken.getPastVotes(owner, t0), 1_000_000_000 ether, "Owner should have 1_000_000_000 votes at t0");

        // Move time forward by 1 week
        vm.roll(block.number + _WEEK / 12);
        vm.warp(block.timestamp + _WEEK);

        // 1 week after transfer, votes should still be the same
        assertEq(coveToken.getVotes(owner), 500_000_000 ether, "Owner should still have 500_000_000 votes");
        assertEq(coveToken.getPastVotes(owner, t0 - 1), 0 ether, "Owner should have 0 votes before t0");
        assertEq(coveToken.getPastVotes(owner, t0), 1_000_000_000 ether, "Owner should have 1_000_000_000 votes at t0");
        assertEq(
            coveToken.getPastVotes(owner, t1 - 1),
            1_000_000_000 ether,
            "Owner should have 1_000_000_000 votes at t1 - 1"
        );
        assertEq(coveToken.getPastVotes(owner, t1), 500_000_000 ether, "Owner should have 500_000_000 votes at t1");
    }
}

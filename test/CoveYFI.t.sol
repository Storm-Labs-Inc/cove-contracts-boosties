// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Pausable } from "@openzeppelin-5.0/contracts/utils/Pausable.sol";
import { BaseTest } from "./utils/BaseTest.t.sol";
import { CoveYFI } from "src/CoveYFI.sol";
import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";

contract CoveYFITest is BaseTest {
    CoveYFI public coveYFI;

    // Addresses
    address public admin;
    address public bob;

    function setUp() public override {
        super.setUp();

        // create admin user that would be the default owner of deployed contracts unless specified
        admin = createUser("admin");
        bob = createUser("bob");

        vm.prank(admin);
        coveYFI = new CoveYFI();
    }

    function test_init() public {
        assertEq(coveYFI.name(), "Cove YFI");
        assertEq(coveYFI.symbol(), "coveYFI");
        assertEq(coveYFI.owner(), admin);
    }

    function test_pause_revertsOnTransfer() public {
        airdrop(ERC20(coveYFI), admin, 1e18);

        vm.startPrank(admin);
        CoveYFI(coveYFI).pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        ERC20(coveYFI).transfer(bob, 1e18);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { CoveYFI } from "src/CoveYFI.sol";

contract CoveYFITest is BaseTest {
    address public admin;
    CoveYFI public coveYFI;

    function setUp() public override {
        super.setUp();

        // create admin user that would be the default owner of deployed contracts unless specified
        admin = createUser("admin");

        vm.prank(admin);
        coveYFI = new CoveYFI();
    }

    function test_init() public {
        assertEq(coveYFI.name(), "Cove YFI");
        assertEq(coveYFI.symbol(), "coveYFI");
        assertEq(coveYFI.owner(), admin);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { CoveToken } from "src/governance/CoveToken.sol";
import { CoveTokenHandler } from "test/invariant/handler/CoveTokenHandler.sol";

contract CoveToken_InvariantTest is BaseTest {
    CoveToken public coveToken;
    CoveTokenHandler public handler;

    function setUp() public override {
        handler = new CoveTokenHandler();
        coveToken = handler.coveToken();
        // targetContract(address(handler.coveToken()));
        targetContract(address(handler));
    }

    function invariant_totalSupplyMin() public {
        assertGe(coveToken.totalSupply(), 1_000_000_000 ether, "totalSupply() must be at least 1_000_000_000");
    }

    function invariant_totalSupply() public {
        assertEq(coveToken.totalSupply(), handler.totalSupply(), "totalSupply() must return the correct total supply");
    }

    function invariant_paused() public {
        assertEq(coveToken.paused(), handler.paused(), "paused() must return the correct pause status");
    }
}

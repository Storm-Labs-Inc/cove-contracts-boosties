// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { MockPausable } from "test/mocks/MockPausable.sol";

contract Pausable_Test is BaseTest {
    MockPausable public pausable;

    function setUp() public override {
        pausable = new MockPausable();
        super.setUp();
    }

    function test_pause() public {
        pausable.pause();
        assertTrue(pausable.paused());
    }

    function test_unpause() public {
        pausable.pause();
        pausable.unpause();
        assertFalse(pausable.paused());
    }

    function test_pause_revertsWhen_alreadyPaused() public {
        pausable.pause();
        vm.expectRevert();
        pausable.pause();
    }

    function test_unpause_revertsWhen_notPaused() public {
        vm.expectRevert();
        pausable.unpause();
    }
}

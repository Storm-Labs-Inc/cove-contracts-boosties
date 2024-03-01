// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Pausable } from "src/Pausable.sol";

contract MockPausable is Pausable {
    // solhint-disable-next-line no-empty-blocks
    constructor() { }

    function pause() external {
        _pause();
    }

    function unpause() external {
        _unpause();
    }
}

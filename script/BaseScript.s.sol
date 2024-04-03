// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Script } from "forge-std/Script.sol";
import { Constants } from "test/utils/Constants.sol";

contract BaseScript is Script, Constants {
    /// @dev Included to enable compilation of the script without a $MNEMONIC environment variable.
    string public constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev Needed for the deterministic deployments.
    bytes32 public constant ZERO_SALT = bytes32(0);

    modifier broadcast() {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }
}

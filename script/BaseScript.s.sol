// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { Script } from "forge-std/Script.sol";
import { Constants } from "test/utils/Constants.sol";

contract BaseScript is Script, Constants {
    /// @dev Needed for the deterministic deployments.
    bytes32 public constant ZERO_SALT = bytes32(0);

    modifier broadcast() {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }
}

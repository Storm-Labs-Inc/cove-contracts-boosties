// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable no-console
pragma solidity >=0.8.18;

import { console2 as console } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";

contract BaseScript is Script {
    /// @dev Included to enable compilation of the script without a $MNEMONIC environment variable.
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev Needed for the deterministic deployments.
    bytes32 internal constant ZERO_SALT = bytes32(0);

    /// @dev The private key of the transaction broadcaster.
    uint256 internal broadcasterPK;

    /// @dev The address of the transaction broadcaster.
    address internal broadcaster;

    /// @dev Initializes the transaction broadcaster like this:
    ///
    /// - If $ETH_FROM is defined, use it.
    /// - Otherwise, derive the broadcaster address from $MNEMONIC.
    /// - If $MNEMONIC is not defined, default to a test mnemonic.
    ///
    /// The use case for $ETH_FROM is to specify the broadcaster key and its address via the command line.
    constructor() {
        broadcasterPK = vm.envOr({ name: "DEPLOYER_PRIVATE_KEY", defaultValue: uint256(0) });
        if (broadcasterPK != uint256(0)) {
            broadcaster = vm.rememberKey(broadcasterPK);
        } else {
            // Anvil address
            // (0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000.000000000000000000 ETH)
            (broadcaster, broadcasterPK) = deriveRememberKey({ mnemonic: TEST_MNEMONIC, index: 0 });
        }
    }

    modifier broadcast() {
        vm.startBroadcast(broadcaster);
        _;
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { Script } from "forge-std/Script.sol";
import { Constants } from "test/utils/Constants.sol";

contract BaseScript is Script, Constants {
    /// @dev Needed for the deterministic deployments.
    bytes32 public constant ZERO_SALT = bytes32(0);

    /// @dev The private key of the transaction broadcaster. Needed for vm.sign().
    uint256 public broadcasterPK;

    /// @dev The address of the transaction broadcaster.
    address public broadcaster;

    /// @dev Initializes the transaction broadcaster like this:
    ///
    /// - If $DEPLOYER_PRIVATE_KEY is defined, use it.
    /// - Otherwise, derive the broadcaster address the test mnemonic.
    ///
    /// The use case for $DEPLOYER_PRIVATE_KEY is to specify the broadcaster key and its address via the command line.
    constructor() {
        broadcasterPK = vm.envOr({ name: "DEPLOYER_PRIVATE_KEY", defaultValue: uint256(0) });
        if (broadcasterPK != uint256(0)) {
            broadcaster = vm.rememberKey(broadcasterPK);
        } else {
            // Anvil address
            // (0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000.000000000000000000 ETH)
            (broadcaster, broadcasterPK) = deriveRememberKey({ mnemonic: TEST_MNEMONIC, index: 0 });
        }
        vm.label(broadcaster, "Broadcaster");
    }

    modifier broadcast() {
        vm.startBroadcast(broadcaster);
        _;
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { CommonBase } from "forge-std/Base.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Constants } from "test/utils/Constants.sol";
import { IGasliteDrop } from "src/deps/gaslite/IGasliteDrop.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract GasliteDropSender is CommonBase, Constants {
    using SafeCast for uint256;

    struct NoVestingData {
        address recipient;
        uint256 amount;
    }

    /**
     * @notice Batch transfer tokens to multiple addresses
     * @param token The token to be streamed
     * @param filePath The path to the JSON file containing the streams data
     * The file format should be as follows:
     * [
     *     "noVestingTotal": 1000000000000000000,
     *     "noVestingData" : [{
     *             "0_recipient": "0x000000000000000000000000000000000000dead",
     *             "1_amount": 1000000000000000000
     *         },
     *     ...]
     * ]
     */
    function batchSendTokens(address token, string memory filePath) public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, filePath);
        string memory json = vm.readFile(path);
        NoVestingData[] memory noVestingData = abi.decode(vm.parseJson(json, ".noVestingData"), (NoVestingData[]));
        uint256 totalAmount = abi.decode(vm.parseJson(json, ".noVestingTotal"), (uint256));
        console.log("No vesting data length: %d", noVestingData.length);
        address[] memory addresses = new address[](noVestingData.length);
        uint256[] memory amounts = new uint256[](noVestingData.length);
        for (uint256 i = 0; i < noVestingData.length; i++) {
            addresses[i] = noVestingData[i].recipient;
            amounts[i] = noVestingData[i].amount;
        }
        IGasliteDrop(MAINNET_GASLITE_AIRDROP).airdropERC20(token, addresses, amounts, totalAmount);
        for (uint256 i = 0; i < noVestingData.length; i++) {
            require(
                IERC20(token).balanceOf(noVestingData[i].recipient) == noVestingData[i].amount, "Failed to send tokens"
            );
            console.log("Sent %d to %s", noVestingData[i].amount, vm.toString(noVestingData[i].recipient));
        }
    }
}

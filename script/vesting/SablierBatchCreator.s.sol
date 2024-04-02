// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/interfaces/IERC721.sol";
import { CommonBase } from "forge-std/Base.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Constants } from "test/utils/Constants.sol";
import { ISablierV2Batch } from "src/interfaces/deps/sablier/ISablierV2Batch.sol";
import { ISablierV2LockupLinear } from "src/interfaces/deps/sablier/ISablierV2LockupLinear.sol";
import { Batch, LockupLinear } from "src/interfaces/deps/sablier/DataTypes.sol";

contract SablierBatchCreator is CommonBase, Constants {
    /**
     * @notice Using forge deploy a set of streams using the SablierV2Batch contract
     * @param token The token to be streamed
     * @param filePath The path to the JSON file containing the streams data
     * The file format should be as follows:
     * [
     *     {
     *         "0_sender": "0x01",
     *         "1_recepient": "0x02",
     *         "2_totalAmount": 10,
     *         "3_cancelable": true,
     *         "4_trasnferable": false,
     *         "5_durations": {
     *             "0_cliff": 0,
     *             "1_total": 31449600
     *         },
     *         "6_broker": {
     *             "0_account": "0x00",
     *             "1_brokerFee": 0
     *         }
     *     },
     *     ...
     * ]
     * @return streamIds The ids of the newly created streams
     */
    function batchCreateStreams(IERC20 token, string memory filePath) public returns (uint256[] memory streamIds) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, filePath);
        string memory json = vm.readFile(path);
        Batch.CreateWithDurations[] memory batch =
            abi.decode(vm.parseJson(json, ".data"), (Batch.CreateWithDurations[]));
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < batch.length; i++) {
            totalAmount += batch[i].totalAmount;
        }
        console.log("Total amount: %d", totalAmount);
        token.approve(MAINNET_SABLIER_V2_BATCH, totalAmount);
        streamIds = ISablierV2Batch(MAINNET_SABLIER_V2_BATCH).createWithDurations(
            MAINNET_SABLIER_V2_LOCKUP_LINEAR, token, batch
        );
        // Log out recipient, amount, and stream id
        console.log("Sablier V2 streams created:", streamIds.length);
        for (uint256 i = 0; i < streamIds.length; i++) {
            LockupLinear.Stream memory stream =
                ISablierV2LockupLinear(MAINNET_SABLIER_V2_LOCKUP_LINEAR).getStream(streamIds[i]);
            require(batch[i].sender == stream.sender, "Sender mismatch");
            address recipient = IERC721(MAINNET_SABLIER_V2_LOCKUP_LINEAR).ownerOf(streamIds[i]);
            require(batch[i].recipient == recipient, "Recipient mismatch");
            require(batch[i].totalAmount == stream.amounts.deposited, "Deposit mismatch");
            require(batch[i].durations.cliff == stream.cliffTime - stream.startTime, "Cliff mismatch");
            require(batch[i].durations.total == stream.endTime - stream.startTime, "Duration mismatch");
            require(batch[i].cancelable == stream.isCancelable, "Cancelable mismatch");
            require(batch[i].transferable == stream.isTransferable, "Transferable mismatch");
            require(stream.isStream, "Stream not found");
            require(!stream.isDepleted, "Stream depleted");
            require(stream.asset == token, "Asset mismatch");
            console.log("Stream ID: ", streamIds[i]);
            console.log("  Recipient: ", recipient);
            console.log("  Amount: ", stream.amounts.deposited);
        }
    }
}

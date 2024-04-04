// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/interfaces/IERC721.sol";
import { CommonBase } from "forge-std/Base.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Constants } from "test/utils/Constants.sol";
import { ISablierV2Batch } from "src/interfaces/deps/sablier/ISablierV2Batch.sol";
import { ISablierV2LockupLinear } from "src/interfaces/deps/sablier/ISablierV2LockupLinear.sol";
import { Batch, LockupLinear, Broker } from "src/interfaces/deps/sablier/DataTypes.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract SablierBatchCreator is CommonBase, Constants {
    using SafeCast for uint256;

    struct VestingJsonData {
        address recipient;
        uint256 amount;
        uint256 duration;
    }

    /**
     * @notice Using forge deploy a set of streams using the SablierV2Batch contract
     * @param token The token to be streamed
     * @param filePath The path to the JSON file containing the streams data
     * The file format should be as follows:
     * [
     *     "totalLocked": 1000000000000000000,
     *     "data" : [{
     *             "0_recipient": "0x000000000000000000000000000000000000dead",
     *             "1_amount": 1000000000000000000,
     *             "2_duration": 63072000
     *         },
     *     ...]
     * ]
     * @return streamIds The ids of the newly created streams
     */
    function batchCreateStreams(
        address sender,
        IERC20 token,
        string memory filePath
    )
        public
        returns (uint256[] memory streamIds)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, filePath);
        string memory json = vm.readFile(path);
        VestingJsonData[] memory vestingData = abi.decode(vm.parseJson(json, ".data"), (VestingJsonData[]));
        uint256 totalLocked = abi.decode(vm.parseJson(json, ".totalLocked"), (uint256));
        console.log("Vesting data length: %d", vestingData.length);
        Batch.CreateWithDurations[] memory batch = new Batch.CreateWithDurations[](vestingData.length);
        uint256 countedTotalAmount = 0;
        for (uint256 i = 0; i < batch.length; i++) {
            countedTotalAmount += vestingData[i].amount;
            batch[i] = Batch.CreateWithDurations({
                sender: sender,
                recipient: vestingData[i].recipient,
                totalAmount: vestingData[i].amount.toUint128(),
                cancelable: true,
                transferable: false,
                durations: LockupLinear.Durations({ cliff: 0, total: vestingData[i].duration.toUint40() }),
                broker: Broker({ account: address(0), fee: 0 })
            });
        }
        require(
            totalLocked == countedTotalAmount, "Total locked amount does not match the sum of the individual amounts"
        );
        console.log("Total amount: %d", countedTotalAmount);
        token.approve(MAINNET_SABLIER_V2_BATCH, totalLocked);
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
            console.log("  Duration: ", stream.endTime - stream.startTime);
        }
    }
}

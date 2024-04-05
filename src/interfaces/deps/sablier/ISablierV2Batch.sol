// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Batch } from "./DataTypes.sol";

interface ISablierV2Batch {
    /// @notice Creates a batch of Lockup Linear streams using `createWithDurations`.
    ///
    /// @dev Requirements:
    /// - There must be at least one element in `batch`.
    /// - All requirements from {ISablierV2LockupLinear.createWithDurations} must be met for each stream.
    ///
    /// @param lockupLinear The address of the {SablierV2LockupLinear} contract.
    /// @param asset The contract address of the ERC-20 asset used for streaming.
    /// @param batch An array of structs, each encapsulating a subset of the parameters of
    /// {SablierV2LockupLinear.createWithDurations}.
    /// @return streamIds The ids of the newly created streams.
    function createWithDurations(
        address lockupLinear,
        IERC20 asset,
        Batch.CreateWithDurations[] calldata batch
    )
        external
        returns (uint256[] memory streamIds);
}

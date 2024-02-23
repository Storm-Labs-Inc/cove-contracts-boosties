// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Struct encapsulating the broker parameters passed to the create functions. Both can be set to zero.
/// @param account The address receiving the broker's fee.
/// @param fee The broker's percentage fee from the total amount, denoted as a fixed-point number where 1e18 is
/// 100%.
struct Broker {
    address account;
    uint256 /* UD60x18 */ fee;
}

library LockupLinear {
    /// @notice Struct encapsulating the cliff duration and the total duration.
    /// @param cliff The cliff duration in seconds.
    /// @param total The total duration in seconds.
    struct Durations {
        uint40 cliff;
        uint40 total;
    }
}

library Batch {
    /// @notice Struct encapsulating the parameters for the {ISablierV2Batch.createWithDurations} function. The function
    /// takes an array of these structs to create multiple streams in a single transaction.
    /// @param sender The address streaming the assets, with the ability to cancel the stream. It doesn't have to be the
    /// same as `msg.sender`.
    /// @param recipient The address receiving the assets.
    /// @param totalAmount The total amount of ERC-20 assets to be paid, including the stream deposit and any potential
    /// fees, all denoted in units of the asset's decimals.
    /// @param cancelable Indicates if the stream is cancelable.
    /// @param transferable Indicates if the stream NFT is transferable.
    /// @param durations Struct containing (i) cliff period duration and (ii) total stream duration, both in seconds.
    /// @param broker Struct containing (i) the address of the broker assisting in creating the stream, and (ii) the
    /// percentage fee paid to the broker from `totalAmount`, denoted as a fixed-point number. Both can be set to zero.
    struct CreateWithDurations {
        address sender;
        address recipient;
        uint128 totalAmount;
        bool cancelable;
        bool transferable;
        LockupLinear.Durations durations;
        Broker broker;
    }
}

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

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { LockupLinear } from "./DataTypes.sol";

interface ISablierV2LockupLinear {
    function getStream(uint256 streamId) external view returns (LockupLinear.Stream memory stream);
}

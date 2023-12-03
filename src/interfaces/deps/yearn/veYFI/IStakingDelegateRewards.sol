// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IAccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

interface IStakingDelegateRewards is IAccessControl {
    function getReward(address stakingToken) external;
}

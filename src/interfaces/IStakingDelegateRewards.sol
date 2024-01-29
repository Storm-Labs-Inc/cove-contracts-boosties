// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { IAccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

interface IStakingDelegateRewards is IAccessControl {
    function getReward(address stakingToken) external;
    function setRewardReceiver(address receiver) external;
}

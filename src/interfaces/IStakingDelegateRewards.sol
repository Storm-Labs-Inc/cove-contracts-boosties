// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { IAccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

interface IStakingDelegateRewards is IAccessControlEnumerable {
    function getReward(address stakingToken) external;
    function setRewardReceiver(address receiver) external;
}

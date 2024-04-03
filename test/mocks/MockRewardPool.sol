// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockRewardPool {
    address public immutable REWARD_TOKEN;

    constructor(address rewardToken_) {
        REWARD_TOKEN = rewardToken_;
    }

    function claim() public returns (uint256) {
        IERC20(REWARD_TOKEN).transfer(msg.sender, IERC20(REWARD_TOKEN).balanceOf(address(this)));
    }
}

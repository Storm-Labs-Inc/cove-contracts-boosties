pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockGauge {
    address private immutable _REWARD_TOKEN;

    constructor(address rewardToken) {
        _REWARD_TOKEN = rewardToken;
    }

    function getReward(address) external returns (uint256) {
        SafeERC20.safeTransfer(IERC20(_REWARD_TOKEN), msg.sender, IERC20(_REWARD_TOKEN).balanceOf(address(this)));
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockStakingDelegateRewards {
    address private immutable _REWARDS_TOKEN;
    address public receiver;

    constructor(address _rewardsToken) {
        _REWARDS_TOKEN = _rewardsToken;
    }

    function addStakingToken(address, address) external { }

    function notifyRewardAmount(address, uint256 amount) external {
        SafeERC20.safeTransferFrom(IERC20(_REWARDS_TOKEN), msg.sender, address(this), amount);
    }

    function getReward(address) external returns (uint256) {
        uint256 toSend = IERC20(_REWARDS_TOKEN).balanceOf(address(this));
        if (toSend > 0) {
            SafeERC20.safeTransfer(IERC20(_REWARDS_TOKEN), msg.sender, toSend);
        }
        return toSend;
    }

    function getReward(address user, address) external returns (uint256) {
        uint256 toSend = IERC20(_REWARDS_TOKEN).balanceOf(address(this));
        if (toSend > 0) {
            SafeERC20.safeTransfer(IERC20(_REWARDS_TOKEN), user, toSend);
        }
        return toSend;
    }

    function setRewardReceiver(address receiver_) external {
        receiver = receiver_;
    }
}

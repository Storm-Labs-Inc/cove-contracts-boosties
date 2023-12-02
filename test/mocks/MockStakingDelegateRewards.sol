pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockStakingDelegateRewards {
    address private immutable _REWARDS_TOKEN;

    constructor(address _rewardsToken, address) {
        _REWARDS_TOKEN = _rewardsToken;
    }

    function notifyRewardAmount(address, uint256 amount) external {
        SafeERC20.safeTransferFrom(IERC20(_REWARDS_TOKEN), msg.sender, address(this), amount);
    }
}

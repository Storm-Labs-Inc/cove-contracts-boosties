pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockBaseRewardsGauge {
    function initialize(address) external { }

    function depositRewardToken(address _rewardToken, uint256 _amount) external {
        IERC20(_rewardToken).transferFrom(msg.sender, address(this), _amount);
    }
}

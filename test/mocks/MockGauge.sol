pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626Mock } from "@openzeppelin/contracts/mocks/ERC4626Mock.sol";

contract MockGauge is ERC4626Mock {
    address public REWARD_TOKEN;

    constructor(address asset_) ERC4626Mock(asset_) { }

    function getReward(address) external returns (uint256) {
        SafeERC20.safeTransfer(IERC20(REWARD_TOKEN), msg.sender, IERC20(REWARD_TOKEN).balanceOf(address(this)));
    }

    function setRewardToken(address rewardToken_) external {
        REWARD_TOKEN = rewardToken_;
    }
}

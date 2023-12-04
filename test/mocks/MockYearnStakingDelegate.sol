// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";

contract MockYearnStakingDelegate {
    using SafeERC20 for IERC20;

    address private _mockgaugeStakingRewards;
    address private constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;

    mapping(address user => mapping(address token => uint256)) public balanceOf;

    function deposit(address gauge, uint256 amount) external {
        // Effects
        uint256 newBalance = balanceOf[msg.sender][gauge] + amount;
        balanceOf[msg.sender][gauge] = newBalance;
        // Interactions
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(address gauge, uint256 amount) external {
        // Effects
        uint256 newBalance = balanceOf[msg.sender][gauge] - amount;
        balanceOf[msg.sender][gauge] = newBalance;
        // Interactions
        IERC20(gauge).safeTransfer(msg.sender, amount);
    }

    function gaugeStakingRewards(address) external view returns (address) {
        return _mockgaugeStakingRewards;
    }

    function setGaugeStakingRewards(address rewards) external {
        _mockgaugeStakingRewards = rewards;
    }

    function lockYfi(uint256 amount) external returns (IVotingYFI.LockedBalance memory lockedBalance) {
        // Interactions
        IERC20(_YFI).safeTransferFrom(msg.sender, address(this), amount);
        return IVotingYFI.LockedBalance({ amount: amount, end: 0 });
    }
}

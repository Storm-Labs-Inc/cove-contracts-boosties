// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockYearnStakingDelegate {
    using SafeERC20 for IERC20;

    address private _mockgaugeStakingRewards;

    mapping(address => mapping(address => uint256)) public balances;

    function deposit(address gauge, uint256 amount) external {
        // Effects
        uint256 newBalance = balances[gauge][msg.sender] + amount;
        balances[gauge][msg.sender] = newBalance;
        // Interactions
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), amount);
    }

    function gaugeStakingRewards(address) external view returns (address) {
        return _mockgaugeStakingRewards;
    }

    function setGaugeStakingRewards(address rewards) external {
        _mockgaugeStakingRewards = rewards;
    }

    function withdraw(address gauge, uint256 amount) external {
        // Effects
        uint256 newBalance = balances[gauge][msg.sender] - amount;
        balances[gauge][msg.sender] = newBalance;
        // Interactions
        IERC20(gauge).safeTransfer(msg.sender, amount);
    }
}

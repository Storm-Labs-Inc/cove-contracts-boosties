// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IDYfiRedeemerEvents {
    event SlippageSet(uint256 slippage);
    event DYfiRedeemed(address indexed dYfiHolder, uint256 dYfiAmount, uint256 yfiAmount);
    event CallerReward(address indexed caller, uint256 amount);
}

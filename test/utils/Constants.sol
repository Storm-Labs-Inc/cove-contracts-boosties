// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

contract Constants {
    uint40 internal constant _JAN_1_2023 = 1_672_531_200;
    uint256 internal constant _MAX_UINT256 = type(uint256).max;

    struct Users {
        // Default admin for all contracts.
        address payable admin;
        // Impartial user.
        address payable alice;
        // Malicious user.
        address payable attacker;
        // Default recipient.
        address payable recipient;
        // Default sender.
        address payable sender;
    }
}

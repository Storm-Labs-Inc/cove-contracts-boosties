// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

contract Constants {
    uint40 internal constant _JAN_1_2023 = 1_672_531_200;
    uint256 internal constant _MAX_UINT256 = type(uint256).max;

    // Ethereum mainnet addresses.
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant ETH_YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address public constant ETH_VE_YFI = 0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5;
    address public constant VAULT_FACTORY = 0x85E2861b3b1a70c90D28DfEc30CE6E07550d83e9;

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

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { CommonBase } from "forge-std/Base.sol";

contract Constants is CommonBase {
    // Constant uint256 values
    uint40 internal constant _JAN_1_2023 = 1_672_531_200;
    uint256 internal constant _MAX_UINT256 = type(uint256).max;

    // Ethereum mainnet addresses
    // Tokens
    address public constant MAINNET_DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant MAINNET_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant MAINNET_VE_YFI = 0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5;
    address public constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant MAINNET_YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;

    // Yearn
    address public constant MAINNET_VAULT_FACTORY = 0x85E2861b3b1a70c90D28DfEc30CE6E07550d83e9;
    address public constant MAINNET_YFI_REWARD_POOL = 0xb287a1964AEE422911c7b8409f5E5A273c1412fA;

    // Curve
    address public constant MAINNET_CURVE_CRYPTO_FACTORY = 0xF18056Bbd320E96A48e3Fbf8bC061322531aac99;
    address public constant MAINNET_CURVE_ROUTER = 0xF0d4c12A5768D806021F80a262B4d39d26C58b8D;

    // Curve Pools
    /// @dev pool type 1, [DAI, USDC, USDT]
    address public constant MAINNET_CRV3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    /// @dev pool type 2, [USDC, WBTC, ETH/WETH]
    address public constant MAINNET_TRI_CRYPTO_USDC = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
    /// @dev pool type 3, [USDT, WBTC, WETH]
    address public constant MAINNET_TRI_CRYPTO_2 = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    /// @dev pool type 2, [ETH/WETH, YFI]
    address public constant MAINNET_YFI_ETH_POOL = 0xC26b89A667578ec7b3f11b2F98d6Fd15C07C54ba;

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

    function _labelEthereumAddresses() internal {
        // Tokens
        vm.label(MAINNET_DAI, "DAI");
        vm.label(MAINNET_ETH, "ETH");
        vm.label(MAINNET_USDC, "USDC");
        vm.label(MAINNET_USDT, "USDT");
        vm.label(MAINNET_VE_YFI, "VE_YFI");
        vm.label(MAINNET_WETH, "WETH");
        vm.label(MAINNET_YFI, "YFI");
        // Yearn
        vm.label(MAINNET_VAULT_FACTORY, "VAULT_FACTORY");
        vm.label(MAINNET_YFI_REWARD_POOL, "YFI_REWARD_POOL");
        // Curve
        vm.label(MAINNET_CURVE_CRYPTO_FACTORY, "CURVE_CRYPTO_FACTORY");
        vm.label(MAINNET_CURVE_ROUTER, "CURVE_ROUTER");
        // Curve Pools
        vm.label(MAINNET_CRV3POOL, "CRV3POOL");
        vm.label(MAINNET_TRI_CRYPTO_USDC, "TRI_CRYPTO_USDC");
        vm.label(MAINNET_TRI_CRYPTO_2, "TRI_CRYPTO_2");
        vm.label(MAINNET_YFI_ETH_POOL, "YFI_ETH_POOL");
    }
}

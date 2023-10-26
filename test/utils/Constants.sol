// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { CommonBase } from "forge-std/Base.sol";

contract Constants is CommonBase {
    // Constant uint256 values
    uint40 internal constant _JAN_1_2023 = 1_672_531_200;
    uint256 internal constant _MAX_UINT256 = type(uint256).max;

    // Ethereum mainnet addresses
    // Tokens
    address public constant MAINNET_DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant MAINNET_DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address public constant MAINNET_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant MAINNET_VE_YFI = 0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5;
    address public constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant MAINNET_YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address public constant MAINNET_FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    // Snapshot
    address public constant MAINNET_SNAPSHOT_DELEGATE_REGISTRY = 0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;

    // Yearn
    address public constant MAINNET_VAULT_FACTORY = 0xE9E8C89c8Fc7E8b8F23425688eb68987231178e5;
    address public constant MAINNET_YFI_REWARD_POOL = 0xb287a1964AEE422911c7b8409f5E5A273c1412fA;
    address public constant MAINNET_DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;
    address public constant MAINNET_DYFI_GAUGE_IMPLEMENTATION = 0x28da6dE3e804bDdF0aD237CFA6048f2930D0b4Dc;
    address public constant MAINNET_VAULT_BLUEPRINT = 0xDE992C652b266AE649FEC8048aFC35954Bee6145;

    // Curve
    address public constant MAINNET_CURVE_CRYPTO_FACTORY = 0xF18056Bbd320E96A48e3Fbf8bC061322531aac99;
    address public constant MAINNET_CURVE_ROUTER = 0xF0d4c12A5768D806021F80a262B4d39d26C58b8D;

    // Curve Pools
    /// @dev pool type 1, [DAI, USDC, USDT]
    address public constant MAINNET_CRV3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    /// @dev pool type 2, [DYFI, ETH/WETH]
    address public constant MAINNET_DYFI_ETH_POOL = 0x8aC64Ba8E440cE5c2d08688f4020698b1826152E;
    /// @dev pool type 2, [USDC, WBTC, ETH/WETH]
    address public constant MAINNET_TRI_CRYPTO_USDC = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
    /// @dev pool type 3, [USDT, WBTC, WETH]
    address public constant MAINNET_TRI_CRYPTO_2 = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    /// @dev pool type 2, [ETH/WETH, YFI]
    address public constant MAINNET_YFI_ETH_POOL = 0xC26b89A667578ec7b3f11b2F98d6Fd15C07C54ba;
    /// @dev pool type 1, [FRAX, USDC]
    address public constant MAINNET_FRAX_USDC_POOL = 0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2;

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
        vm.label(MAINNET_DYFI, "DYFI");
        vm.label(MAINNET_ETH, "ETH");
        vm.label(MAINNET_USDC, "USDC");
        vm.label(MAINNET_USDT, "USDT");
        vm.label(MAINNET_VE_YFI, "VE_YFI");
        vm.label(MAINNET_WETH, "WETH");
        vm.label(MAINNET_YFI, "YFI");
        vm.label(MAINNET_FRAX, "FRAX");
        // Snapshot
        vm.label(MAINNET_SNAPSHOT_DELEGATE_REGISTRY, "SNAPSHOT_DELEGATE_REGISTRY");
        // Yearn
        vm.label(MAINNET_VAULT_FACTORY, "VAULT_FACTORY");
        vm.label(MAINNET_YFI_REWARD_POOL, "YFI_REWARD_POOL");
        vm.label(MAINNET_DYFI_REWARD_POOL, "DYFI_REWARD_POOL");
        // Curve
        vm.label(MAINNET_CURVE_CRYPTO_FACTORY, "CURVE_CRYPTO_FACTORY");
        vm.label(MAINNET_CURVE_ROUTER, "CURVE_ROUTER");
        // Curve Pools
        vm.label(MAINNET_CRV3POOL, "CRV3POOL");
        vm.label(MAINNET_DYFI_ETH_POOL, "DYFI_ETH_POOL");
        vm.label(MAINNET_TRI_CRYPTO_USDC, "TRI_CRYPTO_USDC");
        vm.label(MAINNET_TRI_CRYPTO_2, "TRI_CRYPTO_2");
        vm.label(MAINNET_YFI_ETH_POOL, "YFI_ETH_POOL");
        vm.label(MAINNET_FRAX_USDC_POOL, "FRAX_USDC_POOL");
    }
}

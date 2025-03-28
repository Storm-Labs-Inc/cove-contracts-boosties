// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { CommonBase } from "forge-std/Base.sol";

contract Constants is CommonBase {
    // Constant uint256 values
    uint40 internal constant _JAN_1_2023 = 1_672_531_200;
    uint256 internal constant _MAX_UINT256 = type(uint256).max;
    uint256 internal constant _WEEK = 604_800;
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    /// @dev Included to enable compilation of the script without a $MNEMONIC environment variable.
    string public constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

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
    address public constant MAINNET_CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant MAINNET_YCRV = 0xFCc5c47bE19d06BF83eB04298b026F81069ff65b;
    address public constant MAINNET_PRISMA = 0xdA47862a83dac0c112BA89c6abC2159b95afd71C;
    address public constant MAINNET_YPRISMA = 0x9d5b5925Fb3C8fEE6BC6b5d4f3b6eaA2f3d2dF3b;
    address public constant MAINNET_CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant MAINNET_SCRVUSD = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;
    address public constant MAINNET_USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant MAINNET_SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;

    // Snapshot
    address public constant MAINNET_SNAPSHOT_DELEGATE_REGISTRY = 0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;

    // Yearn
    address public constant MAINNET_VAULT_FACTORY = 0x444045c5C13C246e117eD36437303cac8E250aB0;
    address public constant MAINNET_VAULT_BLUEPRINT = 0x1ab62413e0cf2eBEb73da7D40C70E7202ae14467;
    address public constant MAINNET_TOKENIZED_STRATEGY_IMPLEMENTATION = 0xBB51273D6c746910C7C06fe718f30c936170feD0;
    address public constant MAINNET_YFI_REWARD_POOL = 0xb287a1964AEE422911c7b8409f5E5A273c1412fA;
    address public constant MAINNET_DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;
    address public constant MAINNET_DYFI_REDEMPTION = 0x7dC3A74F0684fc026f9163C6D5c3C99fda2cf60a;
    address public constant MAINNET_YFI_ETH_PRICE_FEED = 0x3EbEACa272Ce4f60E800f6C5EE678f50D2882fd4;

    // Yearn Vaults and Gauges
    address public constant MAINNET_ETH_YFI_VAULT_V2 = 0x790a60024bC3aea28385b60480f15a0771f26D09;
    address public constant MAINNET_ETH_YFI_GAUGE = 0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3;
    address public constant MAINNET_DYFI_ETH_VAULT_V2 = 0xf70B3F1eA3BFc659FFb8b27E84FAE7Ef38b5bD3b;
    address public constant MAINNET_DYFI_ETH_GAUGE = 0x28da6dE3e804bDdF0aD237CFA6048f2930D0b4Dc;
    address public constant MAINNET_WETH_YETH_VAULT_V2 = 0x58900d761Ae3765B75DDFc235c1536B527F25d8F;
    address public constant MAINNET_WETH_YETH_GAUGE = 0x81d93531720d86f0491DeE7D03f30b3b5aC24e59;
    address public constant MAINNET_PRISMA_YPRISMA_VAULT_V2 = 0xbA61BaA1D96c2F4E25205B331306507BcAeA4677;
    address public constant MAINNET_PRISMA_YPRISMA_GAUGE = 0x6130E6cD924a40b24703407F246966D7435D4998;
    address public constant MAINNET_CRV_YCRV_VAULT_V2 = 0x6E9455D109202b426169F0d8f01A3332DAE160f3;
    address public constant MAINNET_CRV_YCRV_GAUGE = 0x107717C98C8125A94D3d2Cc82b86a1b705f3A27C;
    address public constant MAINNET_YVUSDC_VAULT_V3 = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;
    address public constant MAINNET_YVUSDC_GAUGE = 0x622fA41799406B120f9a40dA843D358b7b2CFEE3;
    address public constant MAINNET_YVDAI_VAULT_V3 = 0x028eC7330ff87667b6dfb0D94b954c820195336c;
    address public constant MAINNET_YVDAI_GAUGE = 0x128e72DfD8b00cbF9d12cB75E846AC87B83DdFc9;
    address public constant MAINNET_YVWETH_VAULT_V3 = 0xc56413869c6CDf96496f2b1eF801fEDBdFA7dDB0;
    address public constant MAINNET_YVWETH_GAUGE = 0x5943F7090282Eb66575662EADf7C60a717a7cE4D;
    address public constant MAINNET_COVEYFI_YFI_VAULT_V2 = 0x6A5694C1b37fFA30690b6b60D8Cf89c937d408aD;
    address public constant MAINNET_COVEYFI_YFI_GAUGE = 0x97A597CBcA514AfCc29cD300f04F98d9DbAA3624;
    address public constant MAINNET_YVDAI_VAULT_V3_2 = 0x92545bCE636E6eE91D88D2D017182cD0bd2fC22e;
    address public constant MAINNET_YVDAI_2_GAUGE = 0x38E3d865e34f7367a69f096C80A4fc329DB38BF4;
    address public constant MAINNET_YVWETH_VAULT_V3_2 = 0xAc37729B76db6438CE62042AE1270ee574CA7571;
    address public constant MAINNET_YVWETH_2_GAUGE = 0x8E2485942B399EA41f3C910c1Bb8567128f79859;
    address public constant MAINNET_YVCRVUSD_VAULT_V3_2 = 0xBF319dDC2Edc1Eb6FDf9910E39b37Be221C8805F;
    address public constant MAINNET_YVCRVUSD_2_GAUGE = 0x71c3223D6f836f84cAA7ab5a68AAb6ECe21A9f3b;
    address public constant MAINNET_YVUSDS_VAULT_V3_1 = 0x182863131F9a4630fF9E27830d945B1413e347E8;
    address public constant MAINNET_YVUSDS_1_GAUGE = 0xd57aEa3686d623dA2dCEbc87010a4F2F38Ac7B15;

    // Yearn Vaults that are not an asset of a yearn gauge
    address public constant MAINNET_YVUSDC_VAULT_V2 = 0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE;

    // StakeDAO
    address public constant MAINNET_STAKE_DAO_ETH_YFI_GAUGE = 0x760570c75793b2AB8027aCB60e4A58d337058254;

    // Curve
    address public constant MAINNET_CURVE_CRYPTO_FACTORY = 0xF18056Bbd320E96A48e3Fbf8bC061322531aac99;
    address public constant MAINNET_CURVE_ROUTER = 0xF0d4c12A5768D806021F80a262B4d39d26C58b8D;
    address public constant MAINNET_CURVE_ROUTER_NG = 0x16C6521Dff6baB339122a0FE25a9116693265353;
    address public constant MAINNET_CURVE_ROUTER_NG_V1_2 = 0x45312ea0eFf7E09C83CBE249fa1d7598c4C8cd4e;

    // Balancer
    address public constant MAINNET_BALANCER_FLASH_LOAN_PROVIDER = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    // Curve Pools
    /// @dev pool type 1, [DAI, USDC, USDT]
    address public constant MAINNET_CRV3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address public constant MAINNET_CRV3POOL_LP_TOKEN = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    /// @dev pool type 2, [DYFI, ETH/WETH]
    address public constant MAINNET_DYFI_ETH_POOL = 0x8aC64Ba8E440cE5c2d08688f4020698b1826152E;
    address public constant MAINNET_DYFI_ETH_POOL_LP_TOKEN = 0xE8449F1495012eE18dB7Aa18cD5706b47e69627c;
    /// @dev pool type 2, [USDC, WBTC, ETH/WETH]
    address public constant MAINNET_TRI_CRYPTO_USDC = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
    address public constant MAINNET_TRI_CRYPTO_USDC_LP_TOKEN = MAINNET_TRI_CRYPTO_USDC;
    /// @dev pool type 3, [USDT, WBTC, WETH]
    address public constant MAINNET_TRI_CRYPTO_2 = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    address public constant MAINNET_TRI_CRYPTO_2_LP_TOKEN = 0xc4AD29ba4B3c580e6D59105FFf484999997675Ff;
    /// @dev pool type 2, [ETH/WETH, YFI]
    address public constant MAINNET_ETH_YFI_POOL = 0xC26b89A667578ec7b3f11b2F98d6Fd15C07C54ba;
    address public constant MAINNET_ETH_YFI_POOL_LP_TOKEN = 0x29059568bB40344487d62f7450E78b8E6C74e0e5;
    /// @dev pool type 1, [FRAX, USDC]
    address public constant MAINNET_FRAX_USDC_POOL = 0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2;
    address public constant MAINNET_FRAX_USDC_POOL_LP_TOKEN = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC;
    /// @dev pool type 1, [WETH, YETH]
    address public constant MAINNET_WETH_YETH_POOL = 0x69ACcb968B19a53790f43e57558F5E443A91aF22;
    address public constant MAINNET_WETH_YETH_POOL_LP_TOKEN = MAINNET_WETH_YETH_POOL;
    /// @dev pool type 1, [PRISMA, YPRISMA]
    address public constant MAINNET_PRISMA_YPRISMA_POOL = 0x69833361991ed76f9e8DBBcdf9ea1520fEbFb4a7;
    address public constant MAINNET_PRISMA_YPRISMA_POOL_LP_TOKEN = MAINNET_PRISMA_YPRISMA_POOL;
    /// @dev pool type 1, [CRV, YCRV]
    address public constant MAINNET_CRV_YCRV_POOL = 0x99f5aCc8EC2Da2BC0771c32814EFF52b712de1E5;
    address public constant MAINNET_CRV_YCRV_POOL_LP_TOKEN = MAINNET_CRV_YCRV_POOL;
    /// @dev pool type 2, [ETH/WETH, PRISMA]
    address public constant MAINNET_ETH_PRISMA_POOL = 0x322135Dd9cBAE8Afa84727d9aE1434b5B3EBA44B;
    address public constant MAINNET_ETH_PRISMA_POOL_LP_TOKEN = 0xb34e1a3D07f9D180Bc2FDb9Fd90B8994423e33c1;
    /// @dev pool type 3, [crvUSD, ETH/WETH, CRV]
    address public constant MAINNET_TRICRV_POOL = 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;
    address public constant MAINNET_TRICRV_POOL_LP_TOKEN = MAINNET_TRICRV_POOL;
    /// @dev pool type 10, [COVEYFI, YFI]
    address public constant MAINNET_COVEYFI_YFI_POOL = 0xa3f152837492340dAAf201F4dFeC6cD73A8a9760;
    address public constant MAINNET_COVEYFI_YFI_POOL_LP_TOKEN = MAINNET_COVEYFI_YFI_POOL;
    /// @dev pool type 10, [scrvUSD, sUSDS]
    address public constant MAINNET_SCRVUSD_SUSDS_POOL = 0xfD1627E3f3469C8392C8c3A261D8F0677586e5e1;
    address public constant MAINNET_SCRVUSD_SUSDS_POOL_LP_TOKEN = MAINNET_SCRVUSD_SUSDS_POOL;
    // Uniswap
    address public constant MAINNET_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Sablier V2
    // See https://docs.sablier.com/contracts/v2/deployments for all deployments
    address public constant MAINNET_SABLIER_V2_BATCH = 0xEa07DdBBeA804E7fe66b958329F8Fa5cDA95Bd55;
    address public constant MAINNET_SABLIER_V2_LOCKUP_LINEAR = 0xAFb979d9afAd1aD27C5eFf4E27226E3AB9e5dCC9;

    // Gaslite
    address public constant MAINNET_GASLITE_AIRDROP = 0x09350F89e2D7B6e96bA730783c2d76137B045FEF;

    // Cove Addresses
    address public constant MAINNET_COVE_DEPLOYER = 0x8842fe65A7Db9BB5De6d50e49aF19496da09F9b5;
    address public constant MAINNET_COVE_COMPANY_MULTISIG = 0x519A6Aef94158A90B25846aBa1FA06AFeF8D2323;
    address public constant MAINNET_DEFENDER_RELAYER = 0xc5ccE4661eb87B95Df717b4d25a76eA137F081f7;
    address public constant MAINNET_COVE_COMMUNITY_MULTISIG = 0x7Bd578354b0B2f02E656f1bDC0e41a80f860534b;
    address public constant MAINNET_COVE_OPS_MULTISIG = 0x71BDC5F3AbA49538C76d58Bc2ab4E3A1118dAe4c;
    address public constant COVE_STAGING_COMMUNITY_MULTISIG = 0xC8edE693E4B8cdf4F3C42bf141D9054050E5a728;
    address public constant BOOSTIES_SILVERBACK_AWS_ACCOUNT = 0xd31336617fC8B5Ee3b162d88e75B9236a9be3d6D;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 public constant TOKEN_PERMISSIONS_TYPEHASH =
        0x618358ac3db8dc274f0cd8829da7e234bd48cd73c4a740aede1adec9846d06a1;
    // keccak256("PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256
    // deadline)TokenPermissions(address token,uint256 amount)");
    bytes32 public constant PERMIT2_TRANSFER_FROM_TYPEHASH =
        0x939c21a48a8dbe3a9a2404a1d46691e4d39f6583d6ec6b35714604c986d80106;

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
        vm.label(MAINNET_CRVUSD, "CRVUSD");
        vm.label(MAINNET_SCRVUSD, "SCRVUSD");
        vm.label(MAINNET_USDS, "USDS");
        vm.label(MAINNET_SUSDS, "SUSDS");
        // Snapshot
        vm.label(MAINNET_SNAPSHOT_DELEGATE_REGISTRY, "SNAPSHOT_DELEGATE_REGISTRY");
        // Yearn
        vm.label(MAINNET_VAULT_FACTORY, "VAULT_FACTORY");
        vm.label(MAINNET_YFI_REWARD_POOL, "YFI_REWARD_POOL");
        vm.label(MAINNET_DYFI_REWARD_POOL, "DYFI_REWARD_POOL");
        vm.label(MAINNET_ETH_YFI_VAULT_V2, "ETH_YFI_VAULT_V2");
        vm.label(MAINNET_ETH_YFI_GAUGE, "ETH_YFI_GAUGE");
        vm.label(MAINNET_DYFI_ETH_GAUGE, "DYFI_ETH_GAUGE");
        vm.label(MAINNET_VAULT_BLUEPRINT, "VAULT_BLUEPRINT");
        vm.label(MAINNET_WETH_YETH_VAULT_V2, "WETH_YETH_POOL_VAULT");
        vm.label(MAINNET_WETH_YETH_GAUGE, "WETH_YETH_POOL_GAUGE");
        vm.label(MAINNET_PRISMA_YPRISMA_VAULT_V2, "PRISMA_YPRISMA_VAULT_V2");
        vm.label(MAINNET_PRISMA_YPRISMA_GAUGE, "PRISMA_YPRISMA_GAUGE");
        vm.label(MAINNET_CRV_YCRV_VAULT_V2, "CRV_YCRV_VAULT_V2");
        vm.label(MAINNET_CRV_YCRV_GAUGE, "CRV_YCRV_GAUGE");
        vm.label(MAINNET_YVUSDC_VAULT_V3, "YVUSDC_VAULT_V3");
        vm.label(MAINNET_YVUSDC_GAUGE, "YVUSDC_GAUGE");
        vm.label(MAINNET_YVDAI_VAULT_V3, "YVDAI_VAULT_V3");
        vm.label(MAINNET_YVDAI_GAUGE, "YVDAI_GAUGE");
        vm.label(MAINNET_YVWETH_VAULT_V3, "YVWETH_VAULT_V3");
        vm.label(MAINNET_YVWETH_GAUGE, "YVWETH_GAUGE");
        vm.label(MAINNET_COVEYFI_YFI_VAULT_V2, "COVEYFI_YFI_VAULT_V2");
        vm.label(MAINNET_COVEYFI_YFI_GAUGE, "COVEYFI_YFI_GAUGE");
        vm.label(MAINNET_YVDAI_VAULT_V3_2, "YVDAI_VAULT_V3_2");
        vm.label(MAINNET_YVDAI_2_GAUGE, "YVDAI_2_GAUGE");
        vm.label(MAINNET_YVWETH_VAULT_V3_2, "YVWETH_VAULT_V3_2");
        vm.label(MAINNET_YVWETH_2_GAUGE, "YVWETH_2_GAUGE");
        vm.label(MAINNET_YVCRVUSD_VAULT_V3_2, "YVCRVUSD_VAULT_V3_2");
        vm.label(MAINNET_YVCRVUSD_2_GAUGE, "YVCRVUSD_2_GAUGE");
        vm.label(MAINNET_YVUSDS_VAULT_V3_1, "YVUSDS_VAULT_V3_1");
        vm.label(MAINNET_YVUSDS_1_GAUGE, "YVUSDS_1_GAUGE");
        vm.label(MAINNET_DYFI_REDEMPTION, "DYFI_REDEMPTION");
        // StakeDAO
        vm.label(MAINNET_STAKE_DAO_ETH_YFI_GAUGE, "STAKE_DAO_ETH_YFI_GAUGE");
        // Curve
        vm.label(MAINNET_CURVE_CRYPTO_FACTORY, "CURVE_CRYPTO_FACTORY");
        vm.label(MAINNET_CURVE_ROUTER, "CURVE_ROUTER");
        vm.label(MAINNET_CURVE_ROUTER_NG, "CURVE_ROUTER_NG");
        vm.label(MAINNET_CURVE_ROUTER_NG_V1_2, "CURVE_ROUTER_NG_V1_2");
        vm.label(MAINNET_ETH_YFI_POOL_LP_TOKEN, "CURVE_ETH_YFI_LP_TOKEN");
        // Curve Pools
        vm.label(MAINNET_CRV3POOL, "CRV3POOL");
        vm.label(MAINNET_DYFI_ETH_POOL, "DYFI_ETH_POOL");
        vm.label(MAINNET_TRI_CRYPTO_USDC, "TRI_CRYPTO_USDC");
        vm.label(MAINNET_TRI_CRYPTO_2, "TRI_CRYPTO_2");
        vm.label(MAINNET_ETH_YFI_POOL, "YFI_ETH_POOL");
        vm.label(MAINNET_FRAX_USDC_POOL, "FRAX_USDC_POOL");
        vm.label(MAINNET_WETH_YETH_POOL, "ETH_WETH_YETH_POOL");
        vm.label(MAINNET_PRISMA_YPRISMA_POOL, "PRISMA_YPRISMA_POOL");
        vm.label(MAINNET_CRV_YCRV_POOL, "CRV_YCRV_POOL");
        vm.label(MAINNET_ETH_PRISMA_POOL, "ETH_PRISMA_POOL");
        vm.label(MAINNET_TRICRV_POOL, "TRICRV_POOL");
        vm.label(MAINNET_COVEYFI_YFI_POOL, "COVEYFI_YFI_POOL");
        vm.label(MAINNET_SCRVUSD_SUSDS_POOL, "SCRVUSD_SUSDS_POOL");
        vm.label(MAINNET_TOKENIZED_STRATEGY_IMPLEMENTATION, "TOKENIZED_STRATEGY_IMPLEMENTATION");
        // Uniswap
        vm.label(MAINNET_PERMIT2, "PERMIT2");
        // Sablier V2
        vm.label(MAINNET_SABLIER_V2_BATCH, "SABLIER_V2_BATCH");
        vm.label(MAINNET_SABLIER_V2_LOCKUP_LINEAR, "SABLIER_V2_LOCKUP_LINEAR");
    }
}

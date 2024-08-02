// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { CoveYearnGaugeFactory } from "src/registries/CoveYearnGaugeFactory.sol";

interface IYearnVaultV2 {
    function pricePerShare() external view returns (uint256);
    function token() external view returns (address);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function name() external view returns (string memory);
}

interface IERC4626 is IERC20 {
    function convertToAssets(uint256) external view returns (uint256);
    function asset() external view returns (address);
}

interface ICurveV2 {
    function price_oracle() external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function balances(uint256) external view returns (uint256);
    function token() external view returns (address);
}

interface ICurveNG {
    function price_oracle(uint256) external view returns (uint256);
}

interface ICurveLPToken {
    function minter() external view returns (address);
}

interface IChainlinkFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract DeploylessOracleViem {
    // Struct definition
    struct LogPricesHelper {
        address yearnGauge;
        string yearnGaugeName;
        uint256 yearnGaugePriceInUSD;
        address yearnVault;
        string yearnVaultName;
        uint256 yearnVaultPriceInUSD;
        uint256 yearnVaultPricePerShare;
        address vaultAsset;
        string vaultAssetName;
        uint256 vaultAssetPriceInUSD;
        address coveYearnStrategy;
        string coveYearnStrategyName;
        uint256 coveYearnStrategyPriceInUSD;
        uint256 coveYearnStrategyPricePerShare;
        address coveAutoCompoundingGauge;
        address coveNonCompoundingGauge;
    }

    address private constant _COVE_YEARN_GAUGE_FACTORY = 0x842b22Eb2A1C1c54344eDdbE6959F787c2d15844;
    address private constant _CHAINLINK_ETH_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private constant _CHAINLINK_CRV_PRICE_FEED = 0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f;
    address private constant _CHAINLINK_DAI_PRICE_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private constant _CHAINLINK_USDC_PRICE_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private constant _CHAINLINK_YFI_PRICE_FEED = 0xA027702dbb89fbd58938e4324ac03B58d812b0E1;
    address private constant _CHAINLINK_CRVUSD_PRICE_FEED = 0xEEf0C605546958c1f899b6fB336C20671f9cD49F;

    address private constant _MAINNET_ETH_YFI_GAUGE = 0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3;
    address private constant _MAINNET_DYFI_ETH_GAUGE = 0x28da6dE3e804bDdF0aD237CFA6048f2930D0b4Dc;
    address private constant _MAINNET_WETH_YETH_GAUGE = 0x81d93531720d86f0491DeE7D03f30b3b5aC24e59;
    address private constant _MAINNET_PRISMA_YPRISMA_GAUGE = 0x6130E6cD924a40b24703407F246966D7435D4998;
    address private constant _MAINNET_CRV_YCRV_GAUGE = 0x107717C98C8125A94D3d2Cc82b86a1b705f3A27C;
    address private constant _MAINNET_YVUSDC_GAUGE = 0x622fA41799406B120f9a40dA843D358b7b2CFEE3;
    address private constant _MAINNET_YVDAI_GAUGE = 0x128e72DfD8b00cbF9d12cB75E846AC87B83DdFc9;
    address private constant _MAINNET_YVWETH_GAUGE = 0x5943F7090282Eb66575662EADf7C60a717a7cE4D;
    address private constant _MAINNET_COVEYFI_YFI_GAUGE = 0x97A597CBcA514AfCc29cD300f04F98d9DbAA3624;
    address private constant _MAINNET_YVDAI_2_GAUGE = 0x38E3d865e34f7367a69f096C80A4fc329DB38BF4;
    address private constant _MAINNET_YVWETH_2_GAUGE = 0x8E2485942B399EA41f3C910c1Bb8567128f79859;
    address private constant _MAINNET_CRVUSD_2_GAUGE = 0x71c3223D6f836f84cAA7ab5a68AAb6ECe21A9f3b;

    address private constant _CURVE_ETH_PRISMA_POOL = 0x322135Dd9cBAE8Afa84727d9aE1434b5B3EBA44B;

    constructor() { }

    function getAllPrices() public view returns (LogPricesHelper[] memory h) {
        CoveYearnGaugeFactory.GaugeInfo[] memory gaugeInfo =
            CoveYearnGaugeFactory(_COVE_YEARN_GAUGE_FACTORY).getAllGaugeInfo(100, 0);

        h = new LogPricesHelper[](gaugeInfo.length);
        for (uint256 i = 0; i < gaugeInfo.length; i++) {
            _getPrice(gaugeInfo[i], h, i);
        }
    }

    function _getPrice(
        CoveYearnGaugeFactory.GaugeInfo memory gaugeInfo,
        LogPricesHelper[] memory h,
        uint256 i
    )
        internal
        view
    {
        h[i].yearnGauge = gaugeInfo.yearnGauge;
        h[i].yearnGaugeName = IERC20(gaugeInfo.yearnGauge).name();
        h[i].yearnVault = _getVaultFromGauge(h[i].yearnGauge);
        h[i].yearnVaultName = IERC20(h[i].yearnVault).name();
        h[i].vaultAsset = _getAssetFromVault(h[i].yearnVault);
        h[i].vaultAssetName = IERC20(h[i].vaultAsset).name();
        h[i].coveYearnStrategy = gaugeInfo.coveYearnStrategy;
        h[i].coveYearnStrategyName = IERC20(h[i].coveYearnStrategy).name();
        h[i].coveAutoCompoundingGauge = gaugeInfo.autoCompoundingGauge;
        h[i].coveNonCompoundingGauge = gaugeInfo.nonAutoCompoundingGauge;

        _calculateAssetPrice(h, i);
        _calculateYearnVaultPrice(h, i);
        _calculateYearnGaugePrice(h, i);
        _calculateCoveYearnStrategyPrice(h, i);
    }

    function _calculateAssetPrice(LogPricesHelper[] memory h, uint256 i) internal view {
        // Chainlink price
        uint256 ethPrice = _getChainlinkPrice(_CHAINLINK_ETH_PRICE_FEED);

        if (h[i].yearnGauge == _MAINNET_ETH_YFI_GAUGE) {
            // Curve pooled coin price
            uint256 yfiPrice = _getCoin1Price(h[i].vaultAsset, ethPrice);
            // Calculate Curve LP Price
            h[i].vaultAssetPriceInUSD = _getCurveLPTokenPrice(h[i].vaultAsset, ethPrice, yfiPrice);
        } else if (h[i].yearnGauge == _MAINNET_DYFI_ETH_GAUGE) {
            // Curve pooled coin price
            uint256 dyfiPrice = _getCoin0Price(h[i].vaultAsset, ethPrice);
            // Calculate Curve LP Price
            h[i].vaultAssetPriceInUSD = _getCurveLPTokenPrice(h[i].vaultAsset, dyfiPrice, ethPrice);
        } else if (h[i].yearnGauge == _MAINNET_WETH_YETH_GAUGE) {
            // Curve pooled coin price
            uint256 yethPrice = _getCoin1Price(h[i].vaultAsset, ethPrice);
            // Calculate Curve LP Price
            h[i].vaultAssetPriceInUSD = _getCurveLPTokenPrice(h[i].vaultAsset, ethPrice, yethPrice);
        } else if (h[i].yearnGauge == _MAINNET_PRISMA_YPRISMA_GAUGE) {
            uint256 prismaPrice = _getCoin1Price(_CURVE_ETH_PRISMA_POOL, ethPrice);
            uint256 yPrismaPrice = _getCoin1Price(h[i].vaultAsset, prismaPrice);
            h[i].vaultAssetPriceInUSD = _getCurveLPTokenPrice(h[i].vaultAsset, prismaPrice, yPrismaPrice);
        } else if (h[i].yearnGauge == _MAINNET_CRV_YCRV_GAUGE) {
            uint256 crvPrice = _getChainlinkPrice(_CHAINLINK_CRV_PRICE_FEED);
            uint256 yCrvPrice = _getCoin1Price(h[i].vaultAsset, crvPrice);
            h[i].vaultAssetPriceInUSD = _getCurveLPTokenPrice(h[i].vaultAsset, crvPrice, yCrvPrice);
        } else if (h[i].yearnGauge == _MAINNET_YVUSDC_GAUGE) {
            h[i].vaultAssetPriceInUSD = _getChainlinkPrice(_CHAINLINK_USDC_PRICE_FEED);
        } else if (h[i].yearnGauge == _MAINNET_YVDAI_GAUGE) {
            h[i].vaultAssetPriceInUSD = _getChainlinkPrice(_CHAINLINK_DAI_PRICE_FEED);
        } else if (h[i].yearnGauge == _MAINNET_YVWETH_GAUGE) {
            h[i].vaultAssetPriceInUSD = ethPrice;
        } else if (h[i].yearnGauge == _MAINNET_COVEYFI_YFI_GAUGE) {
            uint256 yfiPrice = _getChainlinkPrice(_CHAINLINK_YFI_PRICE_FEED);
            h[i].vaultAssetPriceInUSD = _getCoin0Price(h[i].vaultAsset, yfiPrice);
        } else if (h[i].yearnGauge == _MAINNET_YVDAI_2_GAUGE) {
            h[i].vaultAssetPriceInUSD = _getChainlinkPrice(_CHAINLINK_DAI_PRICE_FEED);
        } else if (h[i].yearnGauge == _MAINNET_YVWETH_2_GAUGE) {
            h[i].vaultAssetPriceInUSD = ethPrice;
        } else if (h[i].yearnGauge == _MAINNET_CRVUSD_2_GAUGE) {
            h[i].vaultAssetPriceInUSD = _getChainlinkPrice(_CHAINLINK_CRVUSD_PRICE_FEED);
        }
    }

    // Parse chainlink feed answer and scale it to 1e18
    function _getChainlinkPrice(address priceFeed) internal view returns (uint256) {
        IChainlinkFeed feed = IChainlinkFeed(priceFeed);
        (, int256 answer,,,) = feed.latestRoundData();
        return uint256(answer) * 1e10;
    }

    function _getVaultFromGauge(address gauge) internal view returns (address) {
        return IERC4626(gauge).asset();
    }

    function _getAssetFromVault(address vault) internal view returns (address) {
        try IERC4626(vault).asset() returns (address asset) {
            return asset;
        } catch {
            return IYearnVaultV2(vault).token();
        }
    }

    // Get price_oracle() from an address that is either curve pool or lp token.
    function _tryGetPriceOracle(address curvePoolOrLPToken) internal view returns (uint256 priceOracle) {
        // Assume this is curve pool and try getting price oracle
        try ICurveV2(curvePoolOrLPToken).price_oracle() returns (uint256 po) {
            priceOracle = po;
        } catch {
            // Assume this is an NG curve pool and try getting price oracle of coin 0
            try ICurveNG(curvePoolOrLPToken).price_oracle(0) returns (uint256 po) {
                priceOracle = po;
            } catch {
                // Reverted. Assume this is a curve LP token.
                priceOracle = ICurveV2(ICurveLPToken(curvePoolOrLPToken).minter()).price_oracle();
            }
        }
    }

    // Get coin 0 price from coin 1 price using price oracle
    function _getCoin0Price(address curvePoolOrLPToken, uint256 coin1Price) internal view returns (uint256) {
        return coin1Price * 1e18 / _tryGetPriceOracle(curvePoolOrLPToken);
    }

    // Get coin 1 price from coin 0 price using price oracle
    function _getCoin1Price(address curvePoolOrLPToken, uint256 coin0Price) internal view returns (uint256) {
        return _tryGetPriceOracle(curvePoolOrLPToken) * coin0Price / 1e18;
    }

    // Get implied Curve LP token price (volatile) from coin0 and coin1 prices.
    function _getCurveLPTokenPrice(
        address curvePoolOrLPToken,
        uint256 coin0Price,
        uint256 coin1Price
    )
        internal
        view
        returns (uint256)
    {
        address curvePool;
        address curveLPToken;
        uint256 totalSupply;

        try IERC20(curvePoolOrLPToken).totalSupply() returns (uint256 ts) {
            // address could be either lp token OR pool + lp token.
            totalSupply = ts;
            curveLPToken = curvePoolOrLPToken;
            try ICurveLPToken(curvePoolOrLPToken).minter() returns (address pool) {
                // address is lp token
                curvePool = pool;
            } catch {
                curvePool = curvePoolOrLPToken;
                // address is pool + lp token
            }
        } catch {
            // address is pool
            curvePool = curvePoolOrLPToken;
            curveLPToken = ICurveV2(curvePoolOrLPToken).token();
            totalSupply = IERC20(curveLPToken).totalSupply();
        }

        return
            (ICurveV2(curvePool).balances(0) * coin0Price + ICurveV2(curvePool).balances(1) * coin1Price) / totalSupply;
    }

    // Helper function for getting price per share of 4626 contract
    function _get4626PricePerShare(IERC4626 vault) internal view returns (uint256) {
        return vault.convertToAssets(1e18);
    }

    function _calculateYearnVaultPrice(LogPricesHelper[] memory h, uint256 i) internal view {
        try IYearnVaultV2(h[i].yearnVault).pricePerShare() returns (uint256 pps) {
            h[i].yearnVaultPricePerShare = pps * (10 ** (18 - IERC20(h[i].yearnVault).decimals()));
        } catch {
            h[i].yearnVaultPricePerShare = _get4626PricePerShare(IERC4626(h[i].yearnGauge));
        }
        h[i].yearnVaultPriceInUSD = h[i].vaultAssetPriceInUSD * h[i].yearnVaultPricePerShare
            * (10 ** IERC20(h[i].yearnVault).decimals()) / (10 ** (18 + IERC20(h[i].vaultAsset).decimals()));
    }

    function _calculateYearnGaugePrice(LogPricesHelper[] memory h, uint256 i) internal view {
        uint256 gaugePps = _get4626PricePerShare(IERC4626(h[i].yearnGauge));
        h[i].yearnGaugePriceInUSD = h[i].yearnVaultPriceInUSD * gaugePps * (10 ** IERC20(h[i].yearnGauge).decimals())
            / (10 ** (18 + IERC20(h[i].yearnVault).decimals()));
    }

    function _calculateCoveYearnStrategyPrice(LogPricesHelper[] memory h, uint256 i) internal view {
        h[i].coveYearnStrategyPricePerShare = _get4626PricePerShare(IERC4626(h[i].coveYearnStrategy));
        h[i].coveYearnStrategyPriceInUSD = h[i].yearnGaugePriceInUSD * h[i].coveYearnStrategyPricePerShare
            * (10 ** IERC20(h[i].coveYearnStrategy).decimals()) / (10 ** (18 + IERC20(h[i].yearnGauge).decimals()));
    }
}

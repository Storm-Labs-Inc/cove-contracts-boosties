// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

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

interface ICurveLPToken {
    function minter() external view returns (address);
}

interface IChainlinkFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract DeploylessOracle {
    // Struct definition
    struct LogPricesHelper {
        // string yearnGaugeName;
        address yearnGauge;
        uint256 yearnGaugePriceInUSD;
        address yearnVault;
        uint256 yearnVaultPriceInUSD;
        uint256 yearnVaultPricePerShare;
        address vaultAsset;
        uint256 vaultAssetPriceInUSD;
    }

    constructor() {
        LogPricesHelper[] memory returnData = new LogPricesHelper[](8);
        _getPrice(returnData, 0, 0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3);
        _getPrice(returnData, 1, 0x28da6dE3e804bDdF0aD237CFA6048f2930D0b4Dc);
        _getPrice(returnData, 2, 0x81d93531720d86f0491DeE7D03f30b3b5aC24e59);
        _getPrice(returnData, 3, 0x6130E6cD924a40b24703407F246966D7435D4998);
        _getPrice(returnData, 4, 0x107717C98C8125A94D3d2Cc82b86a1b705f3A27C);
        _getPrice(returnData, 5, 0x622fA41799406B120f9a40dA843D358b7b2CFEE3);
        _getPrice(returnData, 6, 0x128e72DfD8b00cbF9d12cB75E846AC87B83DdFc9);
        _getPrice(returnData, 7, 0x5943F7090282Eb66575662EADf7C60a717a7cE4D);
        assembly {
            // Struct size is 0xE0 (7 * 32 bytes)
            let start := add(returnData, 0xE0)
            let size := add(mul(mload(returnData), 0xE0), 0x40)
            mstore(add(start, 0x20), mload(returnData))
            mstore(start, 0x20)
            return(
                start,
                // We assume that 'returnData' is placed at the end of memory
                // Therefore, 'sub(mload(0x40), returnData)' provides the array length
                size
            )
        }
    }

    function _getPrice(LogPricesHelper[] memory h, uint256 i, address yearnGauge) internal view {
        h[i].yearnGauge = yearnGauge;
        // h[i].yearnGaugeName = IERC20(yearnGauge).name();
        h[i].yearnVault = _getVaultFromGauge(h[i].yearnGauge);
        h[i].vaultAsset = _getAssetFromVault(h[i].yearnVault);

        _calculateAssetPrice(h, i);
        _calculateYearnVaultPrice(h, i);
        _calculateYearnGaugePrice(h, i);
    }

    // function getAllPrices() public view returns (LogPricesHelper[] memory h) {
    //     helpers[0] = abi.encode(_getPrice(0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3));
    //     helpers[1] = abi.encode(_getPrice(0x28da6dE3e804bDdF0aD237CFA6048f2930D0b4Dc));
    //     helpers[2] = abi.encode(_getPrice(0x81d93531720d86f0491DeE7D03f30b3b5aC24e59));
    //     helpers[3] = abi.encode(_getPrice(0x6130E6cD924a40b24703407F246966D7435D4998));
    //     helpers[4] = abi.encode(_getPrice(0x107717C98C8125A94D3d2Cc82b86a1b705f3A27C));
    //     helpers[5] = abi.encode(_getPrice(0x622fA41799406B120f9a40dA843D358b7b2CFEE3));
    //     helpers[6] = abi.encode(_getPrice(0x128e72DfD8b00cbF9d12cB75E846AC87B83DdFc9));
    //     helpers[7] = abi.encode(_getPrice(0x5943F7090282Eb66575662EADf7C60a717a7cE4D));
    // }

    // function logPrice(address yearnGauge) public {
    //     _emit(_getPrice(yearnGauge));
    // }

    // function logAllPrices() public {
    //     _emit(_getPrice(0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3));
    //     _emit(_getPrice(0x28da6dE3e804bDdF0aD237CFA6048f2930D0b4Dc));
    //     _emit(_getPrice(0x81d93531720d86f0491DeE7D03f30b3b5aC24e59));
    //     _emit(_getPrice(0x6130E6cD924a40b24703407F246966D7435D4998));
    //     _emit(_getPrice(0x107717C98C8125A94D3d2Cc82b86a1b705f3A27C));
    //     _emit(_getPrice(0x622fA41799406B120f9a40dA843D358b7b2CFEE3));
    //     _emit(_getPrice(0x128e72DfD8b00cbF9d12cB75E846AC87B83DdFc9));
    //     _emit(_getPrice(0x5943F7090282Eb66575662EADf7C60a717a7cE4D));
    // }

    function _calculateAssetPrice(LogPricesHelper[] memory h, uint256 i) internal view {
        // Chainlink price
        uint256 ethPrice = _getChainlinkPrice(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

        if (h[i].yearnGauge == 0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3) {
            // Curve pooled coin price
            uint256 yfiPrice = _getCoin1Price(h[i].vaultAsset, ethPrice);
            // Calculate Curve LP Price
            h[i].vaultAssetPriceInUSD = _getCurveLPTokenPrice(h[i].vaultAsset, ethPrice, yfiPrice);
        } else if (h[i].yearnGauge == 0x28da6dE3e804bDdF0aD237CFA6048f2930D0b4Dc) {
            // Curve pooled coin price
            uint256 dyfiPrice = _getCoin0Price(h[i].vaultAsset, ethPrice);
            // Calculate Curve LP Price
            h[i].vaultAssetPriceInUSD = _getCurveLPTokenPrice(h[i].vaultAsset, dyfiPrice, ethPrice);
        } else if (h[i].yearnGauge == 0x81d93531720d86f0491DeE7D03f30b3b5aC24e59) {
            // Curve pooled coin price
            uint256 yethPrice = _getCoin1Price(h[i].vaultAsset, ethPrice);
            // Calculate Curve LP Price
            h[i].vaultAssetPriceInUSD = _getCurveLPTokenPrice(h[i].vaultAsset, ethPrice, yethPrice);
        } else if (h[i].yearnGauge == 0x6130E6cD924a40b24703407F246966D7435D4998) {
            uint256 prismaPrice = _getCoin1Price(0x322135Dd9cBAE8Afa84727d9aE1434b5B3EBA44B, ethPrice);
            uint256 yPrismaPrice = _getCoin1Price(h[i].vaultAsset, prismaPrice);
            h[i].vaultAssetPriceInUSD = _getCurveLPTokenPrice(h[i].vaultAsset, prismaPrice, yPrismaPrice);
        } else if (h[i].yearnGauge == 0x107717C98C8125A94D3d2Cc82b86a1b705f3A27C) {
            uint256 crvPrice = _getChainlinkPrice(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);
            uint256 yCrvPrice = _getCoin1Price(h[i].vaultAsset, crvPrice);
            h[i].vaultAssetPriceInUSD = _getCurveLPTokenPrice(h[i].vaultAsset, crvPrice, yCrvPrice);
        } else if (h[i].yearnGauge == 0x622fA41799406B120f9a40dA843D358b7b2CFEE3) {
            h[i].vaultAssetPriceInUSD = _getChainlinkPrice(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
        } else if (h[i].yearnGauge == 0x128e72DfD8b00cbF9d12cB75E846AC87B83DdFc9) {
            h[i].vaultAssetPriceInUSD = _getChainlinkPrice(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);
        } else if (h[i].yearnGauge == 0x5943F7090282Eb66575662EADf7C60a717a7cE4D) {
            h[i].vaultAssetPriceInUSD = ethPrice;
        }
    }

    // // Helper function for creating an empty memory struct
    // function _newHelperStruct() internal pure returns (LogPricesHelper memory) {
    //     return LogPricesHelper({
    //         yearnGaugeName: "",
    //         yearnGauge: address(0),
    //         yearnGaugePriceInUSD: 0,
    //         yearnVault: address(0),
    //         yearnVaultPriceInUSD: 0,
    //         yearnVaultPricePerShare: 0,
    //         vaultAsset: address(0),
    //         vaultAssetPriceInUSD: 0
    //     });
    // }

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
            // Reverted. Assume this is a curve LP token.
            priceOracle = ICurveV2(ICurveLPToken(curvePoolOrLPToken).minter()).price_oracle();
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

    // // Fills in vault and gauge price info and emits the event.
    // function _emit(LogPricesHelper memory h) internal {
    //     // Emit event
    //     emit Shadow_YearnGaugePrice(
    //         h.yearnGauge, // Yearn gauge address
    //         (block.timestamp / 1 days) * 1 days, // Timestamp rounded to last day
    //         h.yearnGaugeName,
    //         block.timestamp,
    //         h.vaultAsset, // Asset address (most likely curve LP token)
    //         h.vaultAssetPriceInUSD, // Asset price in USD
    //         h.yearnVault, // Vault address
    //         h.yearnVaultPricePerShare, // Vault Price per share
    //         h.yearnVaultPriceInUSD, // Vault Price in USD (pps * underlying token price)
    //         h.yearnGaugePriceInUSD // Gauge Price in USD
    //     );
    // }
}

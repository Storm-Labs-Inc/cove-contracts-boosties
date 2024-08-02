// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { DeploylessOracleViem } from "src/prices/DeploylessOracleViem.sol";

contract DeploylessOracleViem_ForkedTest is BaseTest {
    DeploylessOracleViem public oracle;

    function setUp() public override {
        // Fork mainnet
        forkNetworkAt("mainnet", 20_320_259);
        _labelEthereumAddresses();
        super.setUp();
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        // Deploy the oracle
        oracle = new DeploylessOracleViem();
    }

    function test_getAllPrices() public {
        // Call getAllPrices
        DeploylessOracleViem.LogPricesHelper[] memory prices = oracle.getAllPrices();

        // Check that we got some results
        assertTrue(prices.length > 0, "No prices returned");

        // Check each price entry
        for (uint256 i = 0; i < prices.length; i++) {
            DeploylessOracleViem.LogPricesHelper memory price = prices[i];

            // Check yearn gauge address
            assertTrue(
                price.yearnGauge == MAINNET_ETH_YFI_GAUGE || price.yearnGauge == MAINNET_DYFI_ETH_GAUGE
                    || price.yearnGauge == MAINNET_WETH_YETH_GAUGE || price.yearnGauge == MAINNET_PRISMA_YPRISMA_GAUGE
                    || price.yearnGauge == MAINNET_CRV_YCRV_GAUGE || price.yearnGauge == MAINNET_YVUSDC_GAUGE
                    || price.yearnGauge == MAINNET_YVDAI_GAUGE || price.yearnGauge == MAINNET_YVWETH_GAUGE
                    || price.yearnGauge == MAINNET_COVEYFI_YFI_GAUGE || price.yearnGauge == MAINNET_YVDAI_2_GAUGE
                    || price.yearnGauge == MAINNET_YVWETH_2_GAUGE || price.yearnGauge == MAINNET_YVCRVUSD_2_GAUGE,
                "Unexpected yearn gauge address"
            );

            // Check yearn vault address
            assertTrue(
                price.yearnVault == MAINNET_ETH_YFI_VAULT_V2 || price.yearnVault == MAINNET_DYFI_ETH_VAULT_V2
                    || price.yearnVault == MAINNET_WETH_YETH_VAULT_V2 || price.yearnVault == MAINNET_PRISMA_YPRISMA_VAULT_V2
                    || price.yearnVault == MAINNET_CRV_YCRV_VAULT_V2 || price.yearnVault == MAINNET_YVUSDC_VAULT_V3
                    || price.yearnVault == MAINNET_YVDAI_VAULT_V3 || price.yearnVault == MAINNET_YVWETH_VAULT_V3
                    || price.yearnVault == MAINNET_COVEYFI_YFI_VAULT_V2 || price.yearnVault == MAINNET_YVDAI_VAULT_V3_2
                    || price.yearnVault == MAINNET_YVWETH_VAULT_V3_2 || price.yearnVault == MAINNET_YVCRVUSD_VAULT_V3_2,
                "Unexpected yearn vault address"
            );

            // Check vault asset address
            assertTrue(
                price.vaultAsset == MAINNET_YFI || price.vaultAsset == MAINNET_DAI || price.vaultAsset == MAINNET_WETH
                    || price.vaultAsset == MAINNET_PRISMA || price.vaultAsset == MAINNET_YCRV
                    || price.vaultAsset == MAINNET_USDC || price.vaultAsset == MAINNET_WETH_YETH_POOL
                    || price.vaultAsset == MAINNET_ETH_YFI_POOL_LP_TOKEN
                    || price.vaultAsset == MAINNET_DYFI_ETH_POOL_LP_TOKEN || price.vaultAsset == MAINNET_CRV_YCRV_POOL
                    || price.vaultAsset == MAINNET_PRISMA_YPRISMA_POOL || price.vaultAsset == MAINNET_COVEYFI_YFI_POOL,
                "Unexpected vault asset address"
            );
            // Check cove yearn strategy address
            assertTrue(price.coveYearnStrategy != address(0), "Cove Yearn strategy address is zero");

            // Check that names are not empty
            assertTrue(bytes(price.yearnGaugeName).length > 0, "Yearn gauge name is empty");
            assertTrue(bytes(price.yearnVaultName).length > 0, "Yearn vault name is empty");
            assertTrue(bytes(price.vaultAssetName).length > 0, "Vault asset name is empty");
            assertTrue(bytes(price.coveYearnStrategyName).length > 0, "Cove Yearn strategy name is empty");

            // Check that prices are not zero
            assertTrue(price.yearnGaugePriceInUSD > 0, "Yearn gauge price is zero");
            assertTrue(price.yearnVaultPriceInUSD > 0, "Yearn vault price is zero");
            assertTrue(price.vaultAssetPriceInUSD > 0, "Vault asset price is zero");
            assertTrue(price.coveYearnStrategyPriceInUSD > 0, "Cove Yearn strategy price is zero");

            // Check that price per share values are not zero
            assertTrue(price.yearnVaultPricePerShare > 0, "Yearn vault price per share is zero");
            assertTrue(price.coveYearnStrategyPricePerShare > 0, "Cove Yearn strategy price per share is zero");
        }
    }
}

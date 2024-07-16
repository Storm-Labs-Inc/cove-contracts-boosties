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

            // Check that addresses are not zero
            assertTrue(price.yearnGauge != address(0), "Yearn gauge address is zero");
            assertTrue(price.yearnVault != address(0), "Yearn vault address is zero");
            assertTrue(price.vaultAsset != address(0), "Vault asset address is zero");
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "tokenized-strategy/interfaces/IStrategy.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WrappedStrategyTest is YearnV3BaseTest {
    IStrategy public mockStrategy;
    IWrappedYearnV3Strategy public wrappedYearnV3Strategy;
    IVault public deployedVault;

    function setUp() public override {
        super.setUp();

        mockStrategy = setUpStrategy("Mock USDC Strategy", USDC);
        wrappedYearnV3Strategy = setUpWrappedStrategy("Wrapped YearnV3 Strategy", USDC);
        vm.label(address(wrappedYearnV3Strategy), "Wrapped YearnV3 Strategy");
        // create array of addresses to be passed to deployVaultV3 instantiated with mockStrategy address
        address[] memory strategies = new address[](1);
        strategies[0] = address(mockStrategy);
        deployVaultV3("USDC Vault", USDC, strategies);
        deployedVault = IVault(deployedVaults["USDC Vault"]);
        wrappedYearnV3Strategy.setYeildSource(deployedVaults["USDC Vault"]);
        wrappedYearnV3Strategy.setStakingDelegate(users["alice"]);
    }

    function testWrappedStrategyDeployment() public view {
        assert(deployedVaults["USDC Vault"] != address(0));
        assert(deployedStrategies["Wrapped YearnV3 Strategy"] != address(0));
        assert(deployedStrategies["Mock USDC Strategy"] != address(0));
    }
}

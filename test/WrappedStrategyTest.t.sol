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
        address[] memory strategies = new address[](1);
        strategies[0] = address(mockStrategy);
        deployVaultV3("USDC Vault", USDC, strategies);
        deployedVault = IVault(deployedVaults["USDC Vault"]);
        wrappedYearnV3Strategy.setYieldSource(deployedVaults["USDC Vault"]);
        // create new user to be the staking delegate
        createUser("stakingDelegate");
        wrappedYearnV3Strategy.setStakingDelegate(users["stakingDelegate"]);
    }

    function testWrappedStrategyDeployment() public view {
        assert(deployedVaults["USDC Vault"] != address(0));
        assert(deployedStrategies["Wrapped YearnV3 Strategy"] != address(0));
        assert(deployedStrategies["Mock USDC Strategy"] != address(0));
    }

    function test_deposit_throughWrappedStrategyDeposit() public {
        deal({ token: USDC, to: users["alice"], give: 1_000_000e18 });
        depositIntoStrategy(wrappedYearnV3Strategy, users["alice"], 1e18);
    }

    function test_withdraw_throughWrappedStrategy() public {
        address stakingDelegate = wrappedYearnV3Strategy.yearnStakingDelegateAddress();
        deal({ token: USDC, to: users["alice"], give: 1_000_000e18 });
        depositIntoStrategy(wrappedYearnV3Strategy, users["alice"], 1e18);

        vm.prank(stakingDelegate);
        deployedVault.approve(address(wrappedYearnV3Strategy), 1e18);

        uint256 userBalanceBefore = ERC20(USDC).balanceOf(users["alice"]);
        vm.prank(users["alice"]);
        wrappedYearnV3Strategy.withdraw(1e18, users["alice"], users["alice"], 0);
        uint256 userBalanceAfter = ERC20(USDC).balanceOf(users["alice"]);
        require(userBalanceAfter > userBalanceBefore, "user balance should increase after withdraw");
    }
}

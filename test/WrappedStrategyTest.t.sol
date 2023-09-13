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

    function testFuzz_deposit_throughWrappedStrategyDeposit(uint256 amount) public {
        vm.assume(amount != 0);
        deal({ token: USDC, to: users["alice"], give: amount });
        // deposit into strategy happens
        depositIntoStrategy(wrappedYearnV3Strategy, users["alice"], amount);
        // check for expected changes
        require(
            deployedVault.balanceOf(wrappedYearnV3Strategy.yearnStakingDelegateAddress()) == amount,
            "vault shares not given to delegate"
        );
        require(deployedVault.totalSupply() == amount, "vault total_supply did not update correctly");
        require(wrappedYearnV3Strategy.balanceOf(users["alice"]) == amount, "Deposit was not successful");
    }

    function test_withdraw_throughWrappedStrategy() public {
        uint256 amount = 1e18;
        address stakingDelegate = wrappedYearnV3Strategy.yearnStakingDelegateAddress();
        deal({ token: USDC, to: users["alice"], give: amount });
        depositIntoStrategy(wrappedYearnV3Strategy, users["alice"], amount);
        vm.prank(stakingDelegate);
        deployedVault.approve(address(wrappedYearnV3Strategy), amount);
        // withdraw from strategy happens
        vm.prank(users["alice"]);
        wrappedYearnV3Strategy.withdraw(amount, users["alice"], users["alice"], 0);
        // check for expected changes
        require(
            deployedVault.balanceOf(wrappedYearnV3Strategy.yearnStakingDelegateAddress()) == 0,
            "vault shares not given to delegate"
        );
        require(deployedVault.totalSupply() == 0, "vault total_supply did not update correctly");
        require(wrappedYearnV3Strategy.balanceOf(users["alice"]) == 0, "Withdraw was not successful");
        require(ERC20(USDC).balanceOf(users["alice"]) == amount, "user balance should be deposit amount after withdraw");
    }
}

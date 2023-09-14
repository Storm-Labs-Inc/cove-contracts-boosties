// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "tokenized-strategy/interfaces/IStrategy.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ICurveBasePool } from "../src/interfaces/ICurveBasePool.sol";

contract WrappedStrategyTest is YearnV3BaseTest {
    IStrategy public mockStrategy;
    IWrappedYearnV3Strategy public wrappedYearnV3Strategy;
    IVault public deployedVault;

    function setUp() public override {
        super.setUp();

        // The underlying vault accepts DAI, while the wrapped strategy accepts USDC
        mockStrategy = setUpStrategy("Mock DAI Strategy", DAI);
        wrappedYearnV3Strategy = setUpWrappedStrategyCurveSwapper("Wrapped YearnV3 Strategy", USDC);
        vm.label(address(wrappedYearnV3Strategy), "Wrapped YearnV3 Strategy");
        address[] memory strategies = new address[](1);
        strategies[0] = address(mockStrategy);
        deployVaultV3("DAI Vault", DAI, strategies);
        deployedVault = IVault(deployedVaults["DAI Vault"]);
        wrappedYearnV3Strategy.setYieldSource(deployedVaults["DAI Vault"]);
        // create new user to be the staking delegate
        createUser("stakingDelegate");
        wrappedYearnV3Strategy.setStakingDelegate(users["stakingDelegate"]);
    }

    function testWrappedStrategyDeployment() public view {
        assert(deployedVaults["DAI Vault"] != address(0));
        assert(deployedStrategies["Wrapped YearnV3 Strategy"] != address(0));
        assert(deployedStrategies["Mock DAI Strategy"] != address(0));
    }

    function test_deposit_wrappedStrategyDepositWithSwap() public {
        uint256 amount = 1e8; // 100 USDC
        deal({ token: USDC, to: users["alice"], give: amount });
        // deposit into strategy happens
        vm.startPrank(users["alice"]);
        ERC20(USDC).approve(address(wrappedYearnV3Strategy), amount);
        wrappedYearnV3Strategy.deposit(amount, users["alice"]);
        // check for expected changes
        uint256 ysdBalance = deployedVault.balanceOf(wrappedYearnV3Strategy.yearnStakingDelegateAddress());
        vm.stopPrank();
        require(ERC20(USDC).balanceOf(users["alice"]) == 0, "alice still has USDC");
        uint256 initialAmountDenomInDai = (amount / 1e6) * 1e18;
        require(
            ysdBalance >= initialAmountDenomInDai - 5e18 && ysdBalance <= initialAmountDenomInDai + 5e18,
            "vault shares not given to delegate within 5% range"
        );
        require(deployedVault.totalSupply() == ysdBalance, "vault total_supply did not update correctly");
        require(wrappedYearnV3Strategy.balanceOf(users["alice"]) == amount, "Deposit was not successful");
    }
}

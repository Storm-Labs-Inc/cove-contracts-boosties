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
        uint256 amount = 1e20;
        deal({ token: USDC, to: users["alice"], give: amount });
        // deposit into strategy happens
        vm.startPrank(users["alice"]);
        ERC20(USDC).approve(address(wrappedYearnV3Strategy), amount);
        console.log("DAI balance: ", ERC20(DAI).balanceOf(address(wrappedYearnV3Strategy)));
        wrappedYearnV3Strategy.deposit(amount, users["alice"]);
        // check for expected changes
        uint256 ysdBalance = deployedVault.balanceOf(wrappedYearnV3Strategy.yearnStakingDelegateAddress());
        // Call get_dy on the curve pool to get the minimum amount of _to token received
        // below dunt work and it make head hurt
        // uint256 expectedMinimumToBalance = ICurveBasePool(CRV3POOL).get_dy(int128(1), int128(0), amount);
        vm.stopPrank();
        require(ERC20(USDC).balanceOf(users["alice"]) == 0, "alice still has USDC");
        require(
            ysdBalance >= amount - 1e18 && ysdBalance <= amount + 1e18,
            "vault shares not given to delegate within range"
        );
        // TODO: figure out why this is so high
        // 70127359339911090471903379 why is the vault balance so high 7e25?
        // 100000000000000000000 when original amount is 1e20
        require(deployedVault.totalSupply() == ysdBalance, "vault total_supply did not update correctly");
        require(wrappedYearnV3Strategy.balanceOf(users["alice"]) == ysdBalance, "Deposit was not successful");
    }
}

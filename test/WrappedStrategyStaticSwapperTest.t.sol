// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "tokenized-strategy/interfaces/IStrategy.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { WrappedYearnV3StrategyStaticSwapper } from "../src/strategies/WrappedYearnV3StrategyStaticSwapper.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ICurveBasePool } from "../src/interfaces/ICurveBasePool.sol";
import { Errors } from "src/libraries/Errors.sol";

contract WrappedStrategyStaticSwapperTest is YearnV3BaseTest {
    IStrategy public mockStrategy;
    WrappedYearnV3StrategyStaticSwapper public wrappedYearnV3StrategyStaticSwapper;
    IWrappedYearnV3Strategy public wrappedYearnV3Strategy;
    IVault public deployedVault;

    // Addresses
    address public alice;

    function setUp() public override {
        super.setUp();

        alice = createUser("alice");

        // The underlying vault accepts DAI, while the wrapped strategy accepts USDC
        mockStrategy = setUpStrategy("Mock DAI Strategy", DAI);
        wrappedYearnV3Strategy = setUpWrappedStrategyStaticSwapper("Wrapped YearnV3 Strategy", USDC, CRV3POOL);
        wrappedYearnV3StrategyStaticSwapper =
            WrappedYearnV3StrategyStaticSwapper(deployedStrategies["Wrapped YearnV3 Strategy"]);
        vm.label(address(wrappedYearnV3Strategy), "Wrapped YearnV3 Strategy");
        address[] memory strategies = new address[](1);
        strategies[0] = address(mockStrategy);
        deployVaultV3("DAI Vault", DAI, strategies);
        deployedVault = IVault(deployedVaults["DAI Vault"]);
        vm.startPrank(users["tpManagement"]);
        wrappedYearnV3Strategy.setYieldSource(deployedVaults["DAI Vault"]);
        // create new user to be the staking delegate
        createUser("stakingDelegate");
        wrappedYearnV3Strategy.setStakingDelegate(users["stakingDelegate"]);
        // set the swap parameters
        wrappedYearnV3StrategyStaticSwapper.setSwapParameters(99_500);
        vm.stopPrank();
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < 1e13);
        uint256 amount = 1e8; // 100 USDC
        deal({ token: USDC, to: users["alice"], give: amount });
        vm.startPrank(users["alice"]);
        ERC20(USDC).approve(address(wrappedYearnV3Strategy), amount);
        // deposit into strategy happens
        wrappedYearnV3Strategy.deposit(amount, users["alice"]);
        // check for expected changes
        uint256 ysdBalance = deployedVault.balanceOf(wrappedYearnV3Strategy.yearnStakingDelegateAddress());
        vm.stopPrank();
        require(ERC20(USDC).balanceOf(users["alice"]) == 0, "alice still has USDC");
        uint256 minAmountFromCurve = ICurveBasePool(CRV3POOL).get_dy(1, 0, amount);
        require(ysdBalance >= minAmountFromCurve, "vault shares not given to delegate");
        require(deployedVault.totalSupply() == ysdBalance, "vault total_supply did not update correctly");
        require(wrappedYearnV3Strategy.balanceOf(users["alice"]) == amount, "Deposit was not successful");
    }

    function test_deposit_revertsSlippageTooHigh() public {
        uint256 amount = 1e8; // 100 USDC
        deal({ token: USDC, to: users["alice"], give: amount });
        vm.prank(users["tpManagement"]);
        wrappedYearnV3StrategyStaticSwapper.setSwapParameters(99_999);
        vm.startPrank(users["alice"]);
        ERC20(USDC).approve(address(wrappedYearnV3Strategy), amount);
        // deposit into strategy happens
        vm.expectRevert(abi.encodeWithSelector(Errors.SlippageTooHigh.selector));
        wrappedYearnV3Strategy.deposit(amount, users["alice"]);
    }
}

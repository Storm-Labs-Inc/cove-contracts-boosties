// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { console2 as console } from "test/utils/BaseTest.t.sol";
import { IStrategy } from "src/interfaces/deps/yearn/tokenized-strategy/IStrategy.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { IERC20, SafeERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { IGaugeFactory } from "src/interfaces/deps/yearn/veYFI/IGaugeFactory.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { Errors } from "../src/libraries/Errors.sol";

contract WrappedStrategyTest is YearnV3BaseTest {
    IStrategy public mockStrategy;
    IWrappedYearnV3Strategy public wrappedYearnV3Strategy;
    YearnStakingDelegate public yearnStakingDelegate;
    IVault public deployedVault;

    // Airdrop amounts
    uint256 public constant ALICE_YFI = 50_000e18;
    uint256 public constant DYFI_REWARD_AMOUNT = 1_000_000e18;

    // Addresses
    address public alice;
    address public testGauge;
    address public manager;
    address public treasury;

    function setUp() public override {
        super.setUp();
        //// generic ////
        alice = createUser("alice");
        manager = createUser("manager");
        treasury = createUser("treasury");
        mockStrategy = setUpStrategy("Mock USDC Strategy", MAINNET_USDC);
        address[] memory strategies = new address[](1);
        strategies[0] = address(mockStrategy);
        deployVaultV3("USDC Vault", MAINNET_USDC, strategies);
        deployedVault = IVault(deployedVaults["USDC Vault"]);

        //// yearn staking delegate ////
        // Deploy gauge
        testGauge = deployGaugeViaFactory(deployedVaults["USDC Vault"], admin, "USDC Test Vault Gauge");
        // Give alice some YFI
        airdrop(ERC20(MAINNET_YFI), alice, ALICE_YFI);
        // Give admin some dYFI
        airdrop(ERC20(dYFI), admin, DYFI_REWARD_AMOUNT);
        // Start new rewards
        vm.startPrank(admin);
        IERC20(dYFI).approve(testGauge, DYFI_REWARD_AMOUNT);
        IGauge(testGauge).queueNewRewards(DYFI_REWARD_AMOUNT);
        vm.stopPrank();
        require(IERC20(dYFI).balanceOf(testGauge) == DYFI_REWARD_AMOUNT, "queueNewRewards failed");
        yearnStakingDelegate = new YearnStakingDelegate(MAINNET_YFI, dYFI, MAINNET_VE_YFI, treasury, admin, manager);
        vm.prank(manager);
        yearnStakingDelegate.setAssociatedGauge(deployedVaults["USDC Vault"], testGauge);

        //// wrapped strategy ////
        wrappedYearnV3Strategy = setUpWrappedStrategy("Wrapped YearnV3 Strategy", MAINNET_USDC);
        vm.label(address(wrappedYearnV3Strategy), "Wrapped YearnV3 Strategy");
        vm.startPrank(tpManagement);
        wrappedYearnV3Strategy.setYieldSource(deployedVaults["USDC Vault"]);
        // set the created staking delegate
        wrappedYearnV3Strategy.setStakingDelegate(address(yearnStakingDelegate));
        vm.stopPrank();
    }

    function testFuzz_deposit(uint256 amount) public {
        vm.assume(amount != 0);
        // limit fuzzing to ysd.userInfo.balance type max
        vm.assume(amount < type(uint128).max);
        deal({ token: MAINNET_USDC, to: users["alice"], give: amount });
        // deposit into strategy happens
        depositIntoStrategy(wrappedYearnV3Strategy, users["alice"], amount);
        // check for expected changes
        assertEq(deployedVault.balanceOf(testGauge), amount, "depositToGauge failed");
        (uint256 userBalance,) = IYearnStakingDelegate(address(yearnStakingDelegate)).userInfo(
            address(wrappedYearnV3Strategy), deployedVaults["USDC Vault"]
        );
        assertEq(userBalance, amount, "userInfo in ysd not updated correctly");
        assertEq(deployedVault.totalSupply(), amount, "vault total_supply did not update correctly");
        assertEq(wrappedYearnV3Strategy.balanceOf(users["alice"]), amount, "Deposit was not successful");
    }

    function testFuzz_withdraw(uint256 amount) public {
        vm.assume(amount != 0);
        // limit fuzzing to ysd.userInfo.balance type max
        vm.assume(amount < type(uint128).max);
        deal({ token: MAINNET_USDC, to: users["alice"], give: amount });
        depositIntoStrategy(wrappedYearnV3Strategy, users["alice"], amount);
        // withdraw from strategy happens
        vm.prank(users["alice"]);
        wrappedYearnV3Strategy.withdraw(amount, users["alice"], users["alice"], 0);
        // check for expected changes
        assertEq(deployedVault.balanceOf(testGauge), 0, "withdrawFromGauge failed");
        (uint256 userBalance,) = IYearnStakingDelegate(address(yearnStakingDelegate)).userInfo(
            address(wrappedYearnV3Strategy), deployedVaults["USDC Vault"]
        );
        assertEq(userBalance, 0, "userInfo in ysd not updated correctly");
        assertEq(
            deployedVault.balanceOf(wrappedYearnV3Strategy.yearnStakingDelegateAddress()),
            0,
            "vault shares not taken from delegate"
        );
        assertEq(deployedVault.totalSupply(), 0, "vault total_supply did not update correctly");
        assertEq(wrappedYearnV3Strategy.balanceOf(users["alice"]), 0, "Withdraw was not successful");
        assertEq(
            ERC20(MAINNET_USDC).balanceOf(users["alice"]),
            amount,
            "user balance should be deposit amount after withdraw"
        );
    }

    function test_setYeildSource_revertsVaultAssetDiffers() public {
        mockStrategy = setUpStrategy("Mock USDC Strategy", MAINNET_DAI);
        address[] memory strategies = new address[](1);
        strategies[0] = address(mockStrategy);
        deployVaultV3("DAI Vault", MAINNET_DAI, strategies);
        vm.startPrank(tpManagement);
        vm.expectRevert(abi.encodeWithSelector(Errors.VaultAssetDiffers.selector));
        wrappedYearnV3Strategy.setYieldSource(deployedVaults["DAI Vault"]);
        vm.stopPrank();
    }

    function test_setStakingDelegate_revertsOnZeroAddress() public {
        vm.startPrank(tpManagement);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        wrappedYearnV3Strategy.setStakingDelegate(address(0));
        vm.stopPrank();
    }
}

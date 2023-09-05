// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { BaseTest, console2 as console } from "test/utils/BaseTest.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockStrategy } from "tokenized-strategy-periphery/test/mocks/MockStrategy.sol";

// Interfaces
import { IVotingYFI } from "src/interfaces/IVotingYFI.sol";
import { IVault } from "src/interfaces/IVault.sol";
import { IStrategy } from "tokenized-strategy/interfaces/IStrategy.sol";

contract YearnV3BaseTest is BaseTest {
    using SafeERC20 for IERC20;

    mapping(string => address) public deployedVaults;
    mapping(string => address) public deployedStrategies;

    address public management;
    address public vaultManagement;
    address public performanceFeeRecipient;
    address public keeper;

    function setUp() public override {
        super.setUp();

        // Fork ethereum mainnet
        forkNetwork("mainnet");

        _createYearnRelatedAddresses();

        // Give alice some YFI
        address alice = users["alice"];
        airdrop(ERC20(ETH_YFI), alice, 1e18);

        // Lock some YFI to get veYFI
        vm.startPrank(alice);
        IERC20(ETH_YFI).approve(ETH_VE_YFI, 1e18);
        IVotingYFI(ETH_VE_YFI).modify_lock(1e18, block.timestamp + 365 * 4 days, alice);
        vm.stopPrank();
    }

    function _createYearnRelatedAddresses() internal {
        // Create yearn related user addresses
        createUser("management");
        createUser("vaultManagement");
        createUser("performanceFeeRecipient");
        createUser("keeper");
        management = users["management"];
        vaultManagement = users["vaultManagement"];
        performanceFeeRecipient = users["performanceFeeRecipient"];
        keeper = users["keeper"];
    }

    // Deploy a vault with given strategies. Uses vyper deployer to deploy v3 vault
    // strategies can be dummy ones or real ones
    // This is intended to spwan a vault that we have control over.
    function deployVaultV3(
        string memory vaultName,
        address asset,
        address[] memory strategies
    )
        public
        returns (address)
    {
        bytes memory args = abi.encode(address(asset), vaultName, "tsVault", users["management"], 10 days);

        IVault _vault = IVault(vyperDeployer.deployContract("lib/yearn-vaults-v3/contracts/", "VaultV3", args));

        vm.prank(management);
        // Give the vault manager all the roles
        _vault.set_role(vaultManagement, 8191);

        // Set deposit limit to max
        vm.prank(vaultManagement);
        _vault.set_deposit_limit(type(uint256).max);

        // Add strategies to vault
        for (uint256 i = 0; i < strategies.length; i++) {
            addStrategyToVault(_vault, IStrategy(strategies[i]));
        }

        // Label the vault
        deployedVaults[vaultName] = address(_vault);
        vm.label(address(_vault), vaultName);

        return address(_vault);
    }

    function addStrategyToVault(IVault _vault, IStrategy _strategy) public {
        vm.prank(vaultManagement);
        _vault.add_strategy(address(_strategy));

        vm.prank(vaultManagement);
        _vault.update_max_debt_for_strategy(address(_strategy), type(uint256).max);
    }

    function setUpStrategy(string memory name, address asset) public returns (IStrategy) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategy _strategy = IStrategy(address(new MockStrategy(address(asset))));

        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);
        // Accept mangagement.
        vm.prank(management);
        _strategy.acceptManagement();

        // Label and store the strategy
        deployedStrategies[name] = address(_strategy);
        vm.label(address(_strategy), name);

        return _strategy;
    }

    // Deploy a strategy that wraps a vault.
    function deployVaultV3WrappedStrategy(address vault) public returns (address) { }
}

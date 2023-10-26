// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { BaseTest, console2 as console } from "test/utils/BaseTest.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockStrategy } from "../mocks/MockStrategy.sol";
import { WrappedYearnV3Strategy } from "src/strategies/WrappedYearnV3Strategy.sol";
import { WrappedYearnV3StrategyAssetSwap } from "src/strategies/WrappedYearnV3StrategyAssetSwap.sol";
import { TokenizedStrategyAssetSwap } from "src/strategies/TokenizedStrategyAssetSwap.sol";

import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

import { ReleaseRegistry } from "vault-periphery/registry/ReleaseRegistry.sol";
import { RegistryFactory } from "vault-periphery/registry/RegistryFactory.sol";
import { Registry } from "vault-periphery/registry/Registry.sol";

import { Gauge } from "src/deps/yearn/veYFI/Gauge.sol";
import { GaugeFactory } from "src/deps/yearn/veYFI/GaugeFactory.sol";
import { dYFI } from "src/deps/yearn/veYFI/dYFI.sol";
import { VeRegistry } from "src/deps/yearn/veYFI/VeRegistry.sol";

// Interfaces
import { IVault } from "yearn-vaults-v3/interfaces/IVault.sol";
import { IStrategy } from "@tokenized-strategy/interfaces/IStrategy.sol";
import { IWrappedYearnV3Strategy } from "src/interfaces/IWrappedYearnV3Strategy.sol";
import { ICurveTwoAssetPool } from "src/interfaces/deps/curve/ICurveTwoAssetPool.sol";

contract YearnV3BaseTest is BaseTest {
    using SafeERC20 for IERC20;

    ERC20 public baseAsset = ERC20(MAINNET_USDC);
    mapping(string => address) public deployedVaults;
    mapping(string => address) public deployedStrategies;

    address public admin;
    address public management;
    address public vaultManagement;
    address public performanceFeeRecipient;
    address public keeper;
    // Wrapped Vault addresses
    address public tpManagement;
    address public tpVaultManagement;
    address public tpPerformanceFeeRecipient;
    address public tpKeeper;

    address public gaugeImpl;
    address public gaugeFactory;
    address public gaugeRegistry;

    // Yearn registry addresses
    address public yearnReleaseRegistry;
    address public yearnRegistryFactory;
    address public yearnRegistry;

    function setUp() public virtual override {
        // Fork ethereum mainnet at block 18386375 for consistent testing and to cache RPC calls
        // https://etherscan.io/block/18429780
        forkNetworkAt("mainnet", 18_429_780);
        super.setUp();

        _createYearnRelatedAddresses();
        _createThirdPartyRelatedAddresses();
        _labelEthereumAddresses();

        // create admin user that would be the default owner of deployed contracts unless specified
        admin = createUser("admin");

        setUpVotingYfiStack();
        setUpYfiRegistry();
    }

    function _createYearnRelatedAddresses() internal {
        // Create yearn related user addresses
        management = createUser("management");
        vaultManagement = createUser("vaultManagement");
        performanceFeeRecipient = createUser("performanceFeeRecipient");
        keeper = createUser("keeper");
    }

    function _createThirdPartyRelatedAddresses() internal {
        // Create third party related user addresses
        tpManagement = createUser("tpManagement");
        tpVaultManagement = createUser("tpVaultManagement");
        tpPerformanceFeeRecipient = createUser("tpPerformanceFeeRecipient");
        tpKeeper = createUser("tpKeeper");
    }

    /// VE-YFI related functions ///
    function setUpVotingYfiStack() public {
        gaugeImpl = _deployGaugeImpl(MAINNET_DYFI, MAINNET_DYFI_REWARD_POOL);
        gaugeFactory = _deployGaugeFactory(gaugeImpl);
        gaugeRegistry = _deployVeYFIRegistry(admin, gaugeFactory, MAINNET_DYFI_REWARD_POOL);
        _increaseDYfiEthPoolLiquidity(MAINNET_DYFI_ETH_POOL, 10e18);
    }

    function _increaseDYfiEthPoolLiquidity(address pool, uint256 ethAmount) internal {
        uint256 dYfiPerEth = ICurveTwoAssetPool(pool).price_oracle();
        uint256 dYfiAmount = ethAmount * 1e18 / dYfiPerEth;
        airdrop(ERC20(MAINNET_WETH), admin, ethAmount);
        airdrop(ERC20(MAINNET_DYFI), admin, dYfiAmount);
        vm.startPrank(admin);
        IERC20(MAINNET_WETH).approve(pool, ethAmount);
        IERC20(MAINNET_DYFI).approve(pool, dYfiAmount);
        ICurveTwoAssetPool(pool).add_liquidity([dYfiAmount, ethAmount], 0);
        vm.stopPrank();
    }

    function _deployDYFI(address owner) internal returns (address) {
        vm.prank(owner);
        address dYfiAddr = address(new dYFI());
        vm.label(dYfiAddr, "DYFI");
        return dYfiAddr;
    }

    function _deployDYFIRewardPool(address dYfi, uint256 startTime) internal returns (address) {
        address addr = vyperDeployer.deployContract(
            "lib/veYFI/contracts/", "dYFIRewardPool", abi.encode(MAINNET_VE_YFI, dYfi, startTime)
        );
        vm.label(addr, "DYfiRewardPool");
        return addr;
    }

    function deployOptions(
        address dYfi,
        address owner,
        address priceFeed,
        address curvePool
    )
        public
        returns (address)
    {
        return vyperDeployer.deployContract(
            "lib/veYFI/contracts/",
            "Options",
            abi.encode(MAINNET_YFI, dYfi, MAINNET_VE_YFI, owner, priceFeed, curvePool)
        );
    }

    function _deployGaugeImpl(address _dYFI, address _dYFIRewardPool) internal returns (address) {
        return address(new Gauge(MAINNET_VE_YFI, _dYFI, _dYFIRewardPool));
    }

    function deployGaugeViaFactory(address vault, address owner, string memory label) public returns (address) {
        address newGauge = GaugeFactory(gaugeFactory).createGauge(vault, owner);
        vm.label(newGauge, label);
        return newGauge;
    }

    function _deployGaugeFactory(address gaugeImplementation) internal returns (address) {
        address gaugeFactoryAddr = address(new GaugeFactory(gaugeImplementation));
        vm.label(gaugeFactoryAddr, "GaugeFactory");
        return gaugeFactoryAddr;
    }

    function _deployVeYFIRegistry(
        address owner,
        address _gaugeFactory,
        address veYFIRewardPool
    )
        internal
        returns (address)
    {
        vm.prank(owner);
        return address(new VeRegistry(MAINNET_VE_YFI, MAINNET_YFI, _gaugeFactory, veYFIRewardPool));
    }

    /// YFI registry related functions ///
    function setUpYfiRegistry() public {
        yearnReleaseRegistry = _deployYearnReleaseRegistry(admin);
        yearnRegistryFactory = _deployYearnRegistryFactory(admin, yearnReleaseRegistry);
        yearnRegistry = RegistryFactory(yearnRegistryFactory).createNewRegistry("TEST_REGISTRY", admin);

        address blueprint = vyperDeployer.deployBlueprint("lib/yearn-vaults-v3/", "VaultV3");
        bytes memory args = abi.encode("Vault V3 Factory 3.0.0", blueprint, admin);
        address factory = vyperDeployer.deployContract("lib/yearn-vaults-v3/", "VaultFactory", args);

        vm.prank(admin);
        ReleaseRegistry(yearnReleaseRegistry).newRelease(factory);
    }

    function _deployYearnReleaseRegistry(address owner) internal returns (address) {
        vm.prank(owner);
        address registryAddr = address(new ReleaseRegistry(owner));
        vm.label(registryAddr, "ReleaseRegistry");
        return registryAddr;
    }

    function _deployYearnRegistryFactory(address owner, address releaseRegistry) internal returns (address) {
        vm.prank(owner);
        address factoryAddr = address(new RegistryFactory(releaseRegistry));
        vm.label(factoryAddr, "RegistryFactory");
        return factoryAddr;
    }

    /// @notice Deploy YearnStakingDelegate with known mainnet addresses
    /// @dev uses ethereum mainnet addresses from Constants.sol
    /// @param _treasury address of treasury
    /// @param _admin address of admin
    /// @param _manager address of manager
    function setUpYearnStakingDelegate(address _treasury, address _admin, address _manager) public returns (address) {
        vm.startPrank(admin);
        YearnStakingDelegate yearnStakingDelegate =
        new YearnStakingDelegate(MAINNET_YFI, MAINNET_DYFI, MAINNET_VE_YFI, MAINNET_SNAPSHOT_DELEGATE_REGISTRY, MAINNET_CURVE_ROUTER, _treasury, _admin, _manager);

        CurveRouterSwapper.CurveSwapParams memory ysdSwapParams;
        // [token_from, pool, token_to, pool, ...]
        ysdSwapParams.route[0] = MAINNET_DYFI;
        ysdSwapParams.route[1] = MAINNET_DYFI_ETH_POOL;
        ysdSwapParams.route[2] = MAINNET_ETH;
        ysdSwapParams.route[3] = MAINNET_YFI_ETH_POOL;
        ysdSwapParams.route[4] = MAINNET_YFI;

        ysdSwapParams.swapParams[0] = [uint256(0), 1, 1, 2, 2];
        ysdSwapParams.swapParams[1] = [uint256(0), 1, 1, 2, 2];
        yearnStakingDelegate.setRouterParams(ysdSwapParams);
        vm.stopPrank();
        return address(yearnStakingDelegate);
    }

    function _deployVaultV3ViaRegistry(string memory vaultName, address asset) internal returns (address) {
        vm.prank(admin);
        address vault = Registry(yearnRegistry).newEndorsedVault(asset, vaultName, "tsVault", management, 10 days, 0);

        vm.prank(management);
        // Give the vault manager all the roles
        IVault(vault).set_role(vaultManagement, 8191);

        // Set deposit limit to max
        vm.prank(vaultManagement);
        IVault(vault).set_deposit_limit(type(uint256).max);

        // Label the vault
        deployedVaults[vaultName] = vault;
        vm.label(vault, vaultName);

        return vault;
    }

    /// @notice Deploy a vault with given strategies. Uses vyper deployer to deploy v3 vault
    /// strategies can be dummy ones or real ones
    /// This is intended to spawn a vault that we have control over.
    function deployVaultV3(
        string memory vaultName,
        address asset,
        address[] memory strategies
    )
        public
        returns (address)
    {
        address vault = _deployVaultV3ViaRegistry(vaultName, asset);

        // Add strategies to vault
        for (uint256 i = 0; i < strategies.length; i++) {
            addStrategyToVault(IVault(vault), IStrategy(strategies[i]));
        }

        return vault;
    }

    /// @notice Deploy a vault with a mock strategy, owned by yearn addresses
    /// @param vaultName name of vault
    /// @param asset address of asset
    /// @return vault address of vault
    /// @return strategy address of mock strategy
    function deployVaultV3WithMockStrategy(
        string memory vaultName,
        address asset
    )
        public
        returns (address vault, address strategy)
    {
        // Deploy mock strategy
        IStrategy _strategy = IStrategy(address(new MockStrategy(asset)));
        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);
        // Accept management.
        vm.prank(management);
        _strategy.acceptManagement();

        vault = _deployVaultV3ViaRegistry(vaultName, asset);
        addStrategyToVault(IVault(vault), _strategy);

        return (vault, address(_strategy));
    }

    /// @notice Increase strategy value by airdropping asset into strategy and harvesting
    /// @param vault address of the vault which has the strategy
    /// @param strategy address of the mock strategy
    /// @param amount amount of asset to airdrop
    /// @return strategyParams struct of strategy params
    function increaseMockStrategyValue(
        address vault,
        address strategy,
        uint256 amount
    )
        public
        returns (IVault.StrategyParams memory)
    {
        // Require strategy is added to vault
        require(IVault(vault).strategies(strategy).activation > 0, "YearnV3BaseTest: Strategy not added to vault");
        // Airdrop asset amount into strategy
        address asset = IStrategy(strategy).asset();
        airdrop(ERC20(asset), strategy, amount);
        reportAndProcessProfits(vault, strategy);
        // Return the strategy params
        // struct StrategyParams {
        //     uint256 activation;
        //     uint256 lastReport;
        //     uint256 currentDebt;
        //     uint256 maxDebt;
        // }
        return IVault(vault).strategies(strategy);
    }

    function reportAndProcessProfits(address vault, address strategy) public {
        // Harvest and report any changes
        vm.prank(management);
        IStrategy(strategy).report();
        // Process report, updating the recorded value of the strategy in the vault
        vm.prank(vaultManagement);
        IVault(vault).process_report(strategy);
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
        // Accept management.
        vm.prank(management);
        _strategy.acceptManagement();

        // Label and store the strategy
        deployedStrategies[name] = address(_strategy);
        vm.label(address(_strategy), name);

        endorseStrategy(address(_strategy));

        return _strategy;
    }

    /// @notice Deploy a strategy that earns yield from a yearn v3 vault.
    function setUpWrappedStrategy(
        string memory name,
        address _asset,
        address _v3VaultAddress,
        address _yearnStakingDelegateAddress,
        address _dYFIAddress,
        address _curveRouterAddress
    )
        public
        returns (IWrappedYearnV3Strategy)
    {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IWrappedYearnV3Strategy _wrappedStrategy = IWrappedYearnV3Strategy(
            address(
                new WrappedYearnV3Strategy(address(_asset), _v3VaultAddress, _yearnStakingDelegateAddress, _dYFIAddress, _curveRouterAddress)
            )
        );
        // set keeper
        _wrappedStrategy.setKeeper(tpKeeper);
        // set treasury
        _wrappedStrategy.setPerformanceFeeRecipient(tpPerformanceFeeRecipient);
        // set management of the strategy
        _wrappedStrategy.setPendingManagement(tpManagement);
        // Accept management.
        vm.prank(tpManagement);
        _wrappedStrategy.acceptManagement();

        // Label and store the strategy
        // *name is "Wrapped Yearn V3 Strategy"
        deployedStrategies[name] = address(_wrappedStrategy);
        vm.label(address(_wrappedStrategy), name);

        endorseStrategy(address(_wrappedStrategy));

        return _wrappedStrategy;
    }

    /// @notice Deploy a strategy that earns yield from a yearn v3 vault with different asset
    /// @dev this strategy relies on oracles to prevent slippage
    function setUpWrappedStrategyAssetSwap(
        string memory name,
        address asset,
        address v3VaultAddress,
        address yearnStakingDelegateAddress,
        address dYFIAddress,
        address curveRouterAddress,
        bool usesOracle
    )
        public
        returns (IWrappedYearnV3Strategy)
    {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IWrappedYearnV3Strategy _wrappedStrategy = IWrappedYearnV3Strategy(
            address(
                new WrappedYearnV3StrategyAssetSwap(asset, v3VaultAddress, yearnStakingDelegateAddress, dYFIAddress, curveRouterAddress, usesOracle)
            )
        );
        // set keeper
        _wrappedStrategy.setKeeper(tpKeeper);
        // set treasury
        _wrappedStrategy.setPerformanceFeeRecipient(tpPerformanceFeeRecipient);
        // set management of the strategy
        _wrappedStrategy.setPendingManagement(tpManagement);
        // Accept management.
        vm.prank(tpManagement);
        _wrappedStrategy.acceptManagement();

        // Label and store the strategy
        // *name is "Wrapped Yearn V3 Strategy"
        deployedStrategies[name] = address(_wrappedStrategy);
        vm.label(address(_wrappedStrategy), name);

        endorseStrategy(address(_wrappedStrategy));

        return _wrappedStrategy;
    }

    /// @notice Deploy a strategy that earns yield from ERC4626 vault with different asset
    /// @dev this strategy allows you to choose to use oracle or not for fetching prices
    function setUpTokenizedStrategyAssetSwap(
        string memory name,
        address asset,
        address v3VaultAddress,
        address curveRouterAddress,
        bool usesOracle
    )
        public
        returns (IStrategy)
    {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategy _tokenizedStrategy =
            IStrategy(address(new TokenizedStrategyAssetSwap(asset, v3VaultAddress, curveRouterAddress, usesOracle)));
        // set keeper
        _tokenizedStrategy.setKeeper(tpKeeper);
        // set treasury
        _tokenizedStrategy.setPerformanceFeeRecipient(tpPerformanceFeeRecipient);
        // set management of the strategy
        _tokenizedStrategy.setPendingManagement(tpManagement);
        // Accept management.
        vm.prank(tpManagement);
        _tokenizedStrategy.acceptManagement();

        // Label and store the strategy
        deployedStrategies[name] = address(_tokenizedStrategy);
        vm.label(address(_tokenizedStrategy), name);
        endorseStrategy(address(_tokenizedStrategy));
        return _tokenizedStrategy;
    }

    function endorseStrategy(address strategy) public {
        vm.prank(admin);
        Registry(yearnRegistry).endorseSingleStrategyVault(strategy);
    }

    function logStratInfo(address strategy) public view {
        IWrappedYearnV3Strategy wrappedYearnV3Strategy = IWrappedYearnV3Strategy(strategy);
        console.log("****************************************");
        console.log("price per share: ", wrappedYearnV3Strategy.pricePerShare());
        console.log("total assets: ", wrappedYearnV3Strategy.totalAssets());
        console.log("total supply: ", wrappedYearnV3Strategy.totalSupply());
        console.log("total debt: ", wrappedYearnV3Strategy.totalDebt());
        console.log("balance of test executor: ", wrappedYearnV3Strategy.balanceOf(address(this)));
        console.log("strategy USDC balance: ", ERC20(MAINNET_USDC).balanceOf(address(wrappedYearnV3Strategy)));
    }

    function logVaultInfo(string memory name) public view {
        IVault deployedVault = IVault(deployedVaults[name]);
        console.log("****************************************");
        console.log(
            "current debt in strategy: ",
            deployedVault.strategies(deployedStrategies["Wrapped YearnV3 Strategy"]).current_debt
        );
        console.log("vault USDC balance: ", ERC20(MAINNET_USDC).balanceOf(address(deployedVault)));
        console.log("vault total debt: ", deployedVault.totalDebt());
        console.log("vault total idle assets: ", deployedVault.totalIdle());
    }

    function depositIntoStrategy(
        IWrappedYearnV3Strategy _strategy,
        address _user,
        uint256 _amount
    )
        public
        returns (uint256 shares)
    {
        vm.prank(_user);
        baseAsset.approve(address(_strategy), _amount);

        vm.prank(_user);
        return _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IWrappedYearnV3Strategy _strategy,
        address _user,
        uint256 _amount
    )
        public
        returns (uint256 shares)
    {
        airdrop(baseAsset, _user, _amount);
        return depositIntoStrategy(_strategy, _user, _amount);
    }

    function addDebtToStrategy(IVault _vault, IStrategy _strategy, uint256 _amount) public {
        vm.prank(vaultManagement);
        _vault.update_debt(address(_strategy), _amount);
    }
}

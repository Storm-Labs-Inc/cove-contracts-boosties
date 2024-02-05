// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { DeployScript } from "forge-deploy/DeployScript.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import {
    DeployerFunctions,
    DefaultDeployerFunction,
    Deployer,
    DeployOptions
} from "generated/deployer/DeployerFunctions.g.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { YearnGaugeStrategy } from "src/strategies/YearnGaugeStrategy.sol";
import { CoveYearnGaugeFactory } from "src/registries/CoveYearnGaugeFactory.sol";
import { SwapAndLock } from "src/SwapAndLock.sol";
import { ITokenizedStrategy } from "lib/tokenized-strategy/src/interfaces/ITokenizedStrategy.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Constants } from "test/utils/Constants.sol";
// Could also import the default deployer functions
// import "forge-deploy/DefaultDeployerFunction.sol";

contract Deployments is DeployScript, Constants {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    DeployOptions public options;

    // Anvil addresses
    // (0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000.000000000000000000 ETH)
    // (1) 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000.000000000000000000 ETH)
    // (2) 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC (10000.000000000000000000 ETH)
    // (3) 0x90F79bf6EB2c4f870365E785982E1f101E93b906 (10000.000000000000000000 ETH)
    string public constant MNEMONIC = "test test test test test test test test test test test junk";
    uint256 public senderPK = vm.deriveKey(MNEMONIC, 0);
    address public sender = vm.addr(senderPK);
    uint256 public adminPK = vm.deriveKey(MNEMONIC, 1);
    address public admin = vm.addr(adminPK);
    uint256 public treasuryPK = vm.deriveKey(MNEMONIC, 2);
    address public treasury = vm.addr(treasuryPK);
    uint256 public managerPK = vm.deriveKey(MNEMONIC, 3);
    address public manager = vm.addr(managerPK);

    address[] public coveYearnStrategies;

    function deploy() public {
        _labelEthereumAddresses();
        vm.label(sender, "sender");
        vm.label(admin, "admin");
        vm.label(treasury, "treasury");
        vm.label(manager, "manager");
        // Deploy Master Registry
        deployMasterRegistry();
        // Deploy Yearn Staking Delegate Stack
        deployYearnStakingDelegateStack();
        // Deploy Cove Strategies for Yearn Gauges
        deployCoveStrategies(deployer.getAddress("YearnStakingDelegate"));
        // Deploy Yearn4626RouterExt
        deployYearn4626RouterExt();
        // Deploy Cove Token
        // TODO: replace MockERC20 with the actual token contract
        address cove = deployCoveToken();
        // Deploy CoveYearnGaugeFactory
        deployCoveYearnGaugeFactory(deployer.getAddress("YearnStakingDelegate"), cove);
        // Deploy RewardsGauge instances
        deployRewardsGauges();
        // Register contracts in the Master Registry
        registerContractsInMasterRegistry();
    }

    function deployYearnStakingDelegateStack() public {
        vm.startBroadcast(senderPK);
        address gaugeRewardReceiverImpl =
            address(deployer.deploy_GaugeRewardReceiver("GaugeRewardReceiverImplementation"));
        YearnStakingDelegate ysd = deployer.deploy_YearnStakingDelegate(
            "YearnStakingDelegate", gaugeRewardReceiverImpl, treasury, admin, manager
        );
        address stakingDelegateRewards =
            address(deployer.deploy_StakingDelegateRewards("StakingDelegateRewards", MAINNET_DYFI, address(ysd)));
        address swapAndLock = address(deployer.deploy_SwapAndLock("SwapAndLock", address(ysd), admin));
        deployer.deploy_DYfiRedeemer("DYfiRedeemer", admin);
        deployer.deploy_CoveYFI("CoveYFI", address(ysd), admin);
        vm.stopBroadcast();

        // Admin transactions
        vm.startBroadcast(adminPK);
        SwapAndLock(swapAndLock).setDYfiRedeemer(deployer.getAddress("DYfiRedeemer"));
        ysd.setSwapAndLock(swapAndLock);
        ysd.setSnapshotDelegate("veyfi.eth", treasury);
        ysd.addGaugeRewards(MAINNET_WETH_YETH_POOL_GAUGE, stakingDelegateRewards);
        ysd.addGaugeRewards(MAINNET_DYFI_ETH_GAUGE, stakingDelegateRewards);
        ysd.addGaugeRewards(MAINNET_ETH_YFI_GAUGE, stakingDelegateRewards);
        vm.stopBroadcast();
    }

    function deployYearn4626RouterExt() public returns (address) {
        vm.startBroadcast(senderPK);
        address yearn4626RouterExt = address(
            deployer.deploy_Yearn4626RouterExt(
                "Yearn4626RouterExt", "Yearn4626RouterExt", MAINNET_WETH, MAINNET_PERMIT2
            )
        );
        vm.stopBroadcast();
        return yearn4626RouterExt;
    }

    function deployCoveStrategies(address ysd) public {
        vm.startBroadcast(senderPK);
        YearnGaugeStrategy strategy = deployer.deploy_YearnGaugeStrategy(
            string.concat("YearnGaugeStrategy-", IERC4626(MAINNET_WETH_YETH_POOL_GAUGE).name()),
            MAINNET_WETH_YETH_POOL_GAUGE,
            ysd,
            MAINNET_CURVE_ROUTER
        );

        CurveRouterSwapper.CurveSwapParams memory curveSwapParams;
        // [token_from, pool, token_to, pool, ...]
        curveSwapParams.route[0] = MAINNET_YFI;
        curveSwapParams.route[1] = MAINNET_ETH_YFI_POOL;
        curveSwapParams.route[2] = MAINNET_WETH;
        curveSwapParams.route[3] = MAINNET_WETH_YETH_POOL;
        curveSwapParams.route[4] = MAINNET_WETH_YETH_POOL; // expect the lp token back

        // i, j, swap_type, pool_type, n_coins
        // YFI -> WETH
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2];
        // ETH -> weth/yeth pool lp token, swap type is 4 to notify the swap router to call add_liquidity()
        curveSwapParams.swapParams[1] = [uint256(0), 0, 4, 1, 2];
        // set params for harvest rewards swapping
        strategy.setHarvestSwapParams(curveSwapParams);
        strategy.setMaxTotalAssets(type(uint256).max);
        ITokenizedStrategy(address(strategy)).setPendingManagement(manager);
        ITokenizedStrategy(address(strategy)).setPerformanceFeeRecipient(treasury);
        ITokenizedStrategy(address(strategy)).setKeeper(manager);
        ITokenizedStrategy(address(strategy)).setEmergencyAdmin(admin);
        vm.stopBroadcast();
        vm.startBroadcast(managerPK);
        ITokenizedStrategy(address(strategy)).acceptManagement();
        vm.stopBroadcast();
        coveYearnStrategies.push(address(strategy));
    }

    function deployMasterRegistry() public returns (address) {
        vm.startBroadcast(senderPK);
        address masterRegistry = address(deployer.deploy_MasterRegistry("MasterRegistry", admin, manager));
        vm.stopBroadcast();
        return masterRegistry;
    }

    function deployCoveToken() public returns (address) {
        vm.startBroadcast(senderPK);
        address cove = address(new ERC20Mock());
        vm.stopBroadcast();
        return cove;
    }

    function deployCoveYearnGaugeFactory(address ysd, address cove) public returns (address) {
        vm.startBroadcast(senderPK);
        address rewardForwarderImpl = address(deployer.deploy_RewardForwarder("RewardForwarderImpl"));
        address baseRewardsGaugeImpl = address(deployer.deploy_BaseRewardsGauge("BaseRewardsGaugeImpl"));
        address ysdRewardsGaugeImpl = address(deployer.deploy_YSDRewardsGauge("YSDRewardsGaugeImpl"));
        // Deploy Gauge Factory
        address factory = address(
            deployer.deploy_CoveYearnGaugeFactory(
                "CoveYearnGaugeFactory",
                admin,
                ysd,
                cove,
                rewardForwarderImpl,
                baseRewardsGaugeImpl,
                ysdRewardsGaugeImpl,
                treasury,
                admin
            )
        );
        vm.stopBroadcast();
        return factory;
    }

    function deployRewardsGauges() public {
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));
        vm.startBroadcast(adminPK);
        for (uint256 i = 0; i < coveYearnStrategies.length; i++) {
            factory.deployCoveGauges(coveYearnStrategies[i]);
        }
        vm.stopBroadcast();
        factory.getAllGaugeInfo();
    }

    function registerContractsInMasterRegistry() public {
        vm.startBroadcast(managerPK);
        bytes[] memory data = new bytes[](6);
        data[0] = abi.encodeWithSelector(
            MasterRegistry.addRegistry.selector,
            bytes32("YearnStakingDelegate"),
            deployer.getAddress("YearnStakingDelegate")
        );
        data[1] = abi.encodeWithSelector(
            MasterRegistry.addRegistry.selector,
            bytes32("StakingDelegateRewards"),
            deployer.getAddress("StakingDelegateRewards")
        );
        data[2] = abi.encodeWithSelector(
            MasterRegistry.addRegistry.selector, bytes32("SwapAndLock"), deployer.getAddress("SwapAndLock")
        );
        data[3] = abi.encodeWithSelector(
            MasterRegistry.addRegistry.selector, bytes32("DYfiRedeemer"), deployer.getAddress("DYfiRedeemer")
        );
        data[4] = abi.encodeWithSelector(
            MasterRegistry.addRegistry.selector, bytes32("CoveYFI"), deployer.getAddress("CoveYFI")
        );
        data[5] = abi.encodeWithSelector(
            MasterRegistry.addRegistry.selector,
            bytes32("CoveYearnGaugeFactory"),
            deployer.getAddress("CoveYearnGaugeFactory")
        );
        MasterRegistry masterRegistry = MasterRegistry(deployer.getAddress("MasterRegistry"));
        masterRegistry.multicall(data);
        vm.stopBroadcast();
    }

    function getCurrentDeployer() external view returns (Deployer) {
        return deployer;
    }
}
// example run in current setup: DEPLOYMENT_CONTEXT=localhost forge script script/Deployments.s.sol --rpc-url
// http://localhost:8545 --broadcast --private-key ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -v
// && ./forge-deploy sync;

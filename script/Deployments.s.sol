// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
import { console2 as console } from "forge-std/console2.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import { DeployerFunctions, DefaultDeployerFunction, Deployer } from "generated/deployer/DeployerFunctions.g.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { YearnGaugeStrategy } from "src/strategies/YearnGaugeStrategy.sol";
import { CoveYearnGaugeFactory } from "src/registries/CoveYearnGaugeFactory.sol";
import { SwapAndLock } from "src/SwapAndLock.sol";
import { ITokenizedStrategy } from "lib/tokenized-strategy/src/interfaces/ITokenizedStrategy.sol";
import { IERC4626, IERC20 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SablierBatchCreator } from "script/vesting/SablierBatchCreator.s.sol";
import { CoveToken } from "src/governance/CoveToken.sol";
// Could also import the default deployer functions
// import "forge-deploy/DefaultDeployerFunction.sol";

contract Deployments is BaseDeployScript, SablierBatchCreator {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    address public admin;
    address public treasury;
    address public manager;

    address[] public coveYearnStrategies;

    function deploy() public override {
        // Assume admin and treasury are the same Gnosis Safe
        admin = vm.envOr("ADMIN_MULTISIG", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 1)));
        treasury = admin;
        manager = broadcaster;

        vm.label(admin, "admin");
        vm.label(manager, "manager");

        _labelEthereumAddresses();
        // Deploy Master Registry
        deployMasterRegistry();
        // Deploy Yearn Staking Delegate Stack
        deployYearnStakingDelegateStack();
        // Deploy Yearn4626RouterExt
        deployYearn4626RouterExt();
        // Deploy Cove Token with minting allowed after 3 years
        uint256 mintingAllowedAfter = block.timestamp + 3 * 365 days;
        deployCoveToken(mintingAllowedAfter);
        // Allow admin, and manager, and sablier batch contract, and the vesting contract to transfer cove tokens
        address[] memory allowedSenders = new address[](4);
        allowedSenders[0] = admin;
        allowedSenders[1] = manager;
        allowedSenders[2] = MAINNET_SABLIER_V2_BATCH;
        allowedSenders[3] = MAINNET_SABLIER_V2_LOCKUP_LINEAR;
        allowlistCoveTokenTransfers(allowedSenders);
        // Deploy Vesting via Sablier
        deploySablierStreams();
        // Deploy CoveYearnGaugeFactory
        deployCoveYearnGaugeFactory(deployer.getAddress("YearnStakingDelegate"), deployer.getAddress("CoveToken"));
        // Deploy Cove Strategies for Yearn Gauges
        deployWethYethCoveStrategy(deployer.getAddress("YearnStakingDelegate"));
        // TODO: Deploy strategies for other gauges
        // Register contracts in the Master Registry
        registerContractsInMasterRegistry();
    }

    function deployYearnStakingDelegateStack() public broadcast deployIfMissing("YearnStakingDelegate") {
        address gaugeRewardReceiverImpl =
            address(deployer.deploy_GaugeRewardReceiver("GaugeRewardReceiverImplementation", options));
        YearnStakingDelegate ysd = deployer.deploy_YearnStakingDelegate(
            "YearnStakingDelegate", gaugeRewardReceiverImpl, treasury, broadcaster, manager, options
        );
        address stakingDelegateRewards = address(
            deployer.deploy_StakingDelegateRewards("StakingDelegateRewards", MAINNET_DYFI, address(ysd), options)
        );
        address swapAndLock = address(deployer.deploy_SwapAndLock("SwapAndLock", address(ysd), broadcaster, options));
        deployer.deploy_DYfiRedeemer("DYfiRedeemer", admin, options);
        deployer.deploy_CoveYFI("CoveYFI", address(ysd), admin, options);
        // Admin transactions
        SwapAndLock(swapAndLock).setDYfiRedeemer(deployer.getAddress("DYfiRedeemer"));
        ysd.setSwapAndLock(swapAndLock);
        ysd.setSnapshotDelegate("veyfi.eth", treasury);
        ysd.addGaugeRewards(MAINNET_WETH_YETH_POOL_GAUGE, stakingDelegateRewards);
        ysd.addGaugeRewards(MAINNET_DYFI_ETH_GAUGE, stakingDelegateRewards);
        ysd.addGaugeRewards(MAINNET_ETH_YFI_GAUGE, stakingDelegateRewards);
        ysd.addGaugeRewards(MAINNET_CRV_YCRV_POOL_GAUGE, stakingDelegateRewards);
        ysd.addGaugeRewards(MAINNET_PRISMA_YPRISMA_POOL_GAUGE, stakingDelegateRewards);

        // Move admin roles to the admin multisig
        ysd.grantRole(ysd.DEFAULT_ADMIN_ROLE(), admin);
        ysd.renounceRole(ysd.DEFAULT_ADMIN_ROLE(), broadcaster);
        SwapAndLock(swapAndLock).grantRole(ysd.DEFAULT_ADMIN_ROLE(), admin);
        SwapAndLock(swapAndLock).renounceRole(ysd.DEFAULT_ADMIN_ROLE(), broadcaster);
    }

    function deployYearn4626RouterExt() public broadcast deployIfMissing("Yearn4626RouterExt") returns (address) {
        address yearn4626RouterExt = address(
            deployer.deploy_Yearn4626RouterExt(
                "Yearn4626RouterExt", "Yearn4626RouterExt", MAINNET_WETH, MAINNET_PERMIT2, options
            )
        );
        return yearn4626RouterExt;
    }

    function deployWethYethCoveStrategy(address ysd)
        public
        broadcast
        deployIfMissing(string.concat("YearnGaugeStrategy-", IERC4626(MAINNET_WETH_YETH_POOL_GAUGE).name()))
    {
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
        curveSwapParams.route[4] = MAINNET_WETH_YETH_POOL_LP_TOKEN; // expect the lp token back

        // i, j, swap_type, pool_type, n_coins
        // YFI -> WETH
        curveSwapParams.swapParams[0] = [uint256(1), 0, 1, 2, 2];
        // ETH -> weth/yeth pool lp token, swap type is 4 to notify the swap router to call add_liquidity()
        curveSwapParams.swapParams[1] = [uint256(0), 0, 4, 1, 2];
        // set params for harvest rewards swapping
        strategy.setHarvestSwapParams(curveSwapParams);
        // TODO: set the max total assets
        strategy.setMaxTotalAssets(type(uint256).max);
        ITokenizedStrategy(address(strategy)).setPerformanceFeeRecipient(treasury);
        ITokenizedStrategy(address(strategy)).setKeeper(manager);
        ITokenizedStrategy(address(strategy)).setEmergencyAdmin(admin);

        // Deploy the reward gauges for the strategy via the factory
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));
        factory.deployCoveGauges(address(strategy));
    }

    function deployMasterRegistry() public broadcast deployIfMissing("MasterRegistry") returns (address) {
        address masterRegistry = address(deployer.deploy_MasterRegistry("MasterRegistry", admin, manager, options));
        return masterRegistry;
    }

    function deployCoveToken(uint256 mintingAllowedAfter)
        public
        broadcast
        deployIfMissing("CoveToken")
        returns (address)
    {
        address cove = address(deployer.deploy_CoveToken("CoveToken", broadcaster, mintingAllowedAfter, options));
        return cove;
    }

    function allowlistCoveTokenTransfers(address[] memory transferrers) public broadcast {
        CoveToken coveToken = CoveToken(deployer.getAddress("CoveToken"));
        bytes[] memory data = new bytes[](transferrers.length);
        for (uint256 i = 0; i < transferrers.length; i++) {
            data[i] = abi.encodeWithSelector(CoveToken.addAllowedTransferrer.selector, transferrers[i]);
        }
        coveToken.multicall(data);
    }

    function deploySablierStreams() public broadcast returns (uint256[] memory streamIds) {
        streamIds = batchCreateStreams(IERC20(deployer.getAddress("CoveToken")), "/script/vesting/vesting.json");
    }

    function deployCoveYearnGaugeFactory(
        address ysd,
        address cove
    )
        public
        broadcast
        deployIfMissing("CoveYearnGaugeFactory")
        returns (address)
    {
        address rewardForwarderImpl = address(deployer.deploy_RewardForwarder("RewardForwarderImpl", options));
        address erc20RewardsGaugeImpl = address(deployer.deploy_ERC20RewardsGauge("ERC20RewardsGaugeImpl", options));
        address ysdRewardsGaugeImpl = address(deployer.deploy_YSDRewardsGauge("YSDRewardsGaugeImpl", options));
        // Deploy Gauge Factory
        address factory = address(
            deployer.deploy_CoveYearnGaugeFactory(
                "CoveYearnGaugeFactory",
                broadcaster,
                ysd,
                cove,
                rewardForwarderImpl,
                erc20RewardsGaugeImpl,
                ysdRewardsGaugeImpl,
                treasury,
                admin,
                options
            )
        );
        return factory;
    }

    function registerContractsInMasterRegistry() public broadcast {
        // Skip if YearnStakingDelegate is already registered
        MasterRegistry masterRegistry = MasterRegistry(deployer.getAddress("MasterRegistry"));
        try masterRegistry.resolveNameToLatestAddress(bytes32("YearnStakingDelegate")) returns (address) {
            console.log("Contracts already registered in MasterRegistry");
            return;
        } catch {
            // continue
            console.log("Registering contracts in MasterRegistry");
        }

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
        masterRegistry.multicall(data);
    }

    function getCurrentDeployer() external view returns (Deployer) {
        return deployer;
    }
}
// example run in current setup: DEPLOYMENT_CONTEXT=localhost forge script script/Deployments.s.sol --rpc-url
// http://localhost:8545 --broadcast --private-key ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -v
// && ./forge-deploy sync;

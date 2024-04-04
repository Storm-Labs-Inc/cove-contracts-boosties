// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
import { console2 as console } from "forge-std/console2.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import { DeployerFunctions, DefaultDeployerFunction, Deployer } from "generated/deployer/DeployerFunctions.g.sol";
import { MasterRegistry } from "src/MasterRegistry.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { YearnGaugeStrategy } from "src/strategies/YearnGaugeStrategy.sol";
import { CoveYearnGaugeFactory } from "src/registries/CoveYearnGaugeFactory.sol";
import { SwapAndLock } from "src/SwapAndLock.sol";
import { ERC20RewardsGauge } from "src/rewards/ERC20RewardsGauge.sol";
import { RewardForwarder } from "src/rewards/RewardForwarder.sol";
import { ITokenizedStrategy } from "lib/tokenized-strategy/src/interfaces/ITokenizedStrategy.sol";
import { IERC4626, IERC20 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SablierBatchCreator } from "script/vesting/SablierBatchCreator.s.sol";
import { CoveToken } from "src/governance/CoveToken.sol";
import { MiniChefV3, IMiniChefV3Rewarder } from "src/rewards/MiniChefV3.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { CurveSwapParamsConstants } from "test/utils/CurveSwapParamsConstants.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { ISnapshotDelegateRegistry } from "src/interfaces/deps/snapshot/ISnapshotDelegateRegistry.sol";
import { Yearn4626RouterExt } from "src/Yearn4626RouterExt.sol";
import { PeripheryPayments } from "Yearn-ERC4626-Router/external/PeripheryPayments.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

// Could also import the default deployer functions
// import "forge-deploy/DefaultDeployerFunction.sol";

contract Deployments is BaseDeployScript, SablierBatchCreator, CurveSwapParamsConstants {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    address public admin;
    address public treasury;
    address public manager;
    address public pauser;
    address public timeLock;

    address[] public coveYearnStrategies;

    // Expected cove token balances after deployment
    uint256 public constant COVE_BALANCE_MINICHEF = 1_000_000 ether; // TODO: determine cove staking reward amount
    uint256 public constant COVE_BALANCE_LINEAR_VESTING = 483_476_190.47e18;
    uint256 public constant COVE_BALANCE_MULTISIG = 515_523_809.53e18; // TODO: determine multisig cove balance
    uint256 public constant COVE_BALANCE_DEPLOYER = 0;
    // TimelockController configuration
    uint256 public constant COVE_TIMELOCK_CONTROLLER_MIN_DELAY = 2 days;
    // RewardForwarder configuration
    uint256 public constant COVE_REWARDS_GAUGE_REWARD_FORWARDER_TREASURY_BPS = 2000; // 20%
    // YearnStakingDelegate deposit limit configuration
    uint256 public constant MAINNET_WETH_YETH_POOL_GAUGE_MAX_DEPOSIT = type(uint256).max;
    uint256 public constant MAINNET_ETH_YFI_GAUGE_MAX_DEPOSIT = type(uint256).max;
    uint256 public constant MAINNET_DYFI_ETH_GAUGE_MAX_DEPOSIT = type(uint256).max;
    uint256 public constant MAINNET_CRV_YCRV_POOL_GAUGE_MAX_DEPOSIT = type(uint256).max;
    uint256 public constant MAINNET_PRISMA_YPRISMA_POOL_GAUGE_MAX_DEPOSIT = type(uint256).max;

    function deploy() public override {
        // Assume admin and treasury are the same Gnosis Safe
        admin = vm.envOr("ADMIN_MULTISIG", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 1)));
        manager = vm.envOr("DEV_MULTISIG", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 2)));
        pauser = vm.envOr("PAUSER_ACCOUNT", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 3)));
        treasury = admin; // TODO: Determine treasury multisig before prod deployment

        vm.label(admin, "admin");
        vm.label(manager, "manager");
        vm.label(pauser, "pauser");
        vm.label(timeLock, "timeLock");

        deployTimelockController();

        timeLock = deployer.getAddress("TimelockController");

        _labelEthereumAddresses();
        // Deploy Master Registry
        deployMasterRegistry();
        // Deploy Yearn Staking Delegate Stack
        deployYearnStakingDelegateStack();
        // Deploy Yearn4626RouterExt
        deployYearn4626RouterExt();
        // Deploy Cove Token
        deployCoveToken();
        // Allow admin, and manager, and sablier batch contract, and the vesting contract to transfer cove tokens
        address[] memory allowedSenders = new address[](4);
        allowedSenders[0] = admin;
        allowedSenders[1] = manager;
        allowedSenders[2] = MAINNET_SABLIER_V2_BATCH;
        allowedSenders[3] = MAINNET_SABLIER_V2_LOCKUP_LINEAR;
        allowlistCoveTokenTransfers(allowedSenders);
        // Deploy MiniChefV3 farm
        deployMiniChefV3();
        // Deploy Vesting via Sablier
        deploySablierStreams(admin);
        // Send the rest of the Cove tokens to admin
        sendCoveTokensToAdmin();
        address yearnStakingDelegateAddress = deployer.getAddress("YearnStakingDelegate");
        // Deploy CoveYearnGaugeFactory
        deployCoveYearnGaugeFactory(yearnStakingDelegateAddress, deployer.getAddress("CoveToken"));
        // Deploy Cove Strategies for Yearn Gauges
        deployCoveStrategiesAndGauges(yearnStakingDelegateAddress);
        // Deploy Rewards Gauge for CoveYFI
        deployCoveYFIRewards();
        // Approve deposits in the router
        approveDepositsInRouter();
        // Register contracts in the Master Registry
        registerContractsInMasterRegistry();
        // Verify the state of the deployment
        verifyPostDeploymentState();
    }

    function deployTimelockController() public broadcast deployIfMissing("TimelockController") {
        // Only admin can propose new transactions
        address[] memory proposers = new address[](1);
        proposers[0] = admin;
        // Admin, manager, and broadcaster can execute proposed transactions
        address[] memory executors = new address[](3);
        executors[0] = admin;
        executors[1] = manager;
        executors[2] = broadcaster;
        // Deploy and save the TimelockController
        address timelockController = address(
            new TimelockController{ salt: bytes32(options.salt) }(
                COVE_TIMELOCK_CONTROLLER_MIN_DELAY, proposers, executors, address(0)
            )
        );
        deployer.save("TimelockController", timelockController, "TimelockController.sol:TimelockController");
    }

    function deployYearnStakingDelegateStack() public broadcast deployIfMissing("YearnStakingDelegate") {
        address gaugeRewardReceiverImpl =
            address(deployer.deploy_GaugeRewardReceiver("GaugeRewardReceiverImplementation", options));
        YearnStakingDelegate ysd = deployer.deploy_YearnStakingDelegate(
            "YearnStakingDelegate", gaugeRewardReceiverImpl, treasury, broadcaster, pauser, broadcaster, options
        );
        address stakingDelegateRewards = address(
            deployer.deploy_StakingDelegateRewards(
                "StakingDelegateRewards", MAINNET_DYFI, address(ysd), admin, timeLock, options
            )
        );
        deployer.deploy_DYFIRedeemer("DYFIRedeemer", admin, options);
        address coveYfi = address(deployer.deploy_CoveYFI("CoveYFI", address(ysd), admin, options));
        address swapAndLock =
            address(deployer.deploy_SwapAndLock("SwapAndLock", address(ysd), coveYfi, broadcaster, options));

        // Admin transactions
        SwapAndLock(swapAndLock).setDYfiRedeemer(deployer.getAddress("DYFIRedeemer"));
        ysd.setSwapAndLock(swapAndLock);
        ysd.setSnapshotDelegate("veyfi.eth", manager);
        ysd.addGaugeRewards(MAINNET_WETH_YETH_GAUGE, stakingDelegateRewards);
        ysd.addGaugeRewards(MAINNET_DYFI_ETH_GAUGE, stakingDelegateRewards);
        ysd.addGaugeRewards(MAINNET_ETH_YFI_GAUGE, stakingDelegateRewards);
        ysd.addGaugeRewards(MAINNET_CRV_YCRV_GAUGE, stakingDelegateRewards);
        ysd.addGaugeRewards(MAINNET_PRISMA_YPRISMA_GAUGE, stakingDelegateRewards);

        // Move admin roles to the admin multisig
        ysd.grantRole(DEFAULT_ADMIN_ROLE, admin);
        ysd.grantRole(MANAGER_ROLE, admin);
        ysd.grantRole(TIMELOCK_ROLE, timeLock);
        SwapAndLock(swapAndLock).grantRole(DEFAULT_ADMIN_ROLE, admin);
        SwapAndLock(swapAndLock).renounceRole(DEFAULT_ADMIN_ROLE, broadcaster);
    }

    function deployYearn4626RouterExt() public broadcast deployIfMissing("Yearn4626RouterExt") returns (address) {
        address yearn4626RouterExt = address(
            deployer.deploy_Yearn4626RouterExt(
                "Yearn4626RouterExt", "Yearn4626RouterExt", MAINNET_WETH, MAINNET_PERMIT2, options
            )
        );
        return yearn4626RouterExt;
    }

    function _populateApproveMulticall(
        bytes[] memory data,
        uint256 i,
        CoveYearnGaugeFactory.GaugeInfo memory gi
    )
        internal
        pure
        returns (uint256)
    {
        bytes4 selector = PeripheryPayments.approve.selector;
        data[i++] = abi.encodeWithSelector(selector, gi.yearnVaultAsset, gi.yearnVault, _MAX_UINT256);
        data[i++] = abi.encodeWithSelector(selector, gi.yearnVault, gi.yearnGauge, _MAX_UINT256);
        data[i++] = abi.encodeWithSelector(selector, gi.yearnGauge, gi.coveYearnStrategy, _MAX_UINT256);
        data[i++] = abi.encodeWithSelector(selector, gi.coveYearnStrategy, gi.autoCompoundingGauge, _MAX_UINT256);
        data[i++] = abi.encodeWithSelector(selector, gi.yearnGauge, gi.nonAutoCompoundingGauge, _MAX_UINT256);
        return i;
    }

    function approveDepositsInRouter() public broadcast {
        Yearn4626RouterExt yearn4626RouterExt = Yearn4626RouterExt(deployer.getAddress("Yearn4626RouterExt"));
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));

        // For each curve LP token -> yearn vault -> yearn gauge -> yearn strategy -> compounding cove gauge
        // and yearn gauge -> non-compounding cove gauge
        // we should include the following approvals:
        // yearn4626RouterExt.approve(address token, address vaultAddress, type(uint256).max)
        bytes[] memory data = new bytes[](25);
        uint256 i = 0;
        // ETH_YFI
        i = _populateApproveMulticall(data, i, factory.getGaugeInfo(MAINNET_ETH_YFI_GAUGE));
        // DYFI_ETH
        i = _populateApproveMulticall(data, i, factory.getGaugeInfo(MAINNET_DYFI_ETH_GAUGE));
        // WETH_YETH
        i = _populateApproveMulticall(data, i, factory.getGaugeInfo(MAINNET_WETH_YETH_GAUGE));
        // PRISMA_YPRISMA
        i = _populateApproveMulticall(data, i, factory.getGaugeInfo(MAINNET_PRISMA_YPRISMA_GAUGE));
        // CRV_YCRV
        i = _populateApproveMulticall(data, i, factory.getGaugeInfo(MAINNET_CRV_YCRV_GAUGE));
        require(i == data.length, "Incorrect number of approves");
        yearn4626RouterExt.multicall(data);
    }

    function _deployCoveStrategyAndGauges(
        address ysd,
        address yearngauge,
        uint256 maxDeposit,
        CurveRouterSwapper.CurveSwapParams memory swapParams
    )
        internal
        broadcast
        deployIfMissing(string.concat("YearnGaugeStrategy-", IERC4626(yearngauge).name()))
    {
        YearnGaugeStrategy strategy = deployer.deploy_YearnGaugeStrategy(
            string.concat("YearnGaugeStrategy-", IERC4626(yearngauge).name()), yearngauge, ysd, MAINNET_CURVE_ROUTER
        );
        // Set the curve swap params for harvest rewards swapping to the asset, gauge token
        strategy.setHarvestSwapParams(swapParams);
        // Set the tokenized strategy roles
        ITokenizedStrategy(address(strategy)).setPerformanceFeeRecipient(treasury);
        ITokenizedStrategy(address(strategy)).setKeeper(manager);
        ITokenizedStrategy(address(strategy)).setEmergencyAdmin(admin);

        // Deploy the reward gauges for the strategy via the factory
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));
        factory.deployCoveGauges(address(strategy));

        // Grant depositor role to the strategy and the ysd rewards gauge
        CoveYearnGaugeFactory.GaugeInfo memory info = factory.getGaugeInfo(yearngauge);
        YearnStakingDelegate(ysd).grantRole(DEPOSITOR_ROLE, info.coveYearnStrategy);
        YearnStakingDelegate(ysd).grantRole(DEPOSITOR_ROLE, info.nonAutoCompoundingGauge);
        // Set deposit limit for the gauge token
        YearnStakingDelegate(ysd).setDepositLimit(yearngauge, maxDeposit);
    }

    function deployCoveStrategiesAndGauges(address ysd) public {
        _deployCoveStrategyAndGauges(
            ysd,
            MAINNET_WETH_YETH_GAUGE,
            MAINNET_WETH_YETH_POOL_GAUGE_MAX_DEPOSIT,
            getMainnetWethYethGaugeCurveSwapParams()
        );
        _deployCoveStrategyAndGauges(
            ysd, MAINNET_ETH_YFI_GAUGE, MAINNET_ETH_YFI_GAUGE_MAX_DEPOSIT, getMainnetEthYfiGaugeCurveSwapParams()
        );
        _deployCoveStrategyAndGauges(
            ysd, MAINNET_DYFI_ETH_GAUGE, MAINNET_DYFI_ETH_GAUGE_MAX_DEPOSIT, getMainnetDyfiEthGaugeCurveSwapParams()
        );
        _deployCoveStrategyAndGauges(
            ysd,
            MAINNET_CRV_YCRV_GAUGE,
            MAINNET_CRV_YCRV_POOL_GAUGE_MAX_DEPOSIT,
            getMainnetCrvYcrvPoolGaugeCurveSwapParams()
        );
        _deployCoveStrategyAndGauges(
            ysd,
            MAINNET_PRISMA_YPRISMA_GAUGE,
            MAINNET_PRISMA_YPRISMA_POOL_GAUGE_MAX_DEPOSIT,
            getMainnetPrismaYprismaPoolGaugeCurveSwapParams()
        );
    }

    function deployMasterRegistry() public broadcast deployIfMissing("MasterRegistry") returns (address) {
        address masterRegistry = address(deployer.deploy_MasterRegistry("MasterRegistry", admin, broadcaster, options));
        return masterRegistry;
    }

    function deployCoveToken() public broadcast deployIfMissing("CoveToken") returns (address) {
        address cove = address(deployer.deploy_CoveToken("CoveToken", broadcaster, options));
        return cove;
    }

    function deployCoveYFIRewards() public broadcast {
        address erc20RewardsGaugeImpl = deployer.getAddress("ERC20RewardsGaugeImpl");
        ERC20RewardsGauge coveRewardsGauge = ERC20RewardsGauge(Clones.clone(erc20RewardsGaugeImpl));
        deployer.save("CoveRewardsGauge", address(coveRewardsGauge), "ERC20RewardsGauge.sol:ERC20RewardsGauge");
        address rewardForwarderImpl = deployer.getAddress("RewardForwarderImpl");
        RewardForwarder coveRewardsGaugeRewardForwarder = RewardForwarder(Clones.clone(rewardForwarderImpl));
        deployer.save(
            "CoveRewardsGaugeRewardForwarder",
            address(coveRewardsGaugeRewardForwarder),
            "RewardForwarder.sol:RewardForwarder"
        );
        address coveYFI = deployer.getAddress("CoveYFI");
        coveRewardsGauge.initialize(coveYFI);
        coveRewardsGaugeRewardForwarder.initialize(address(coveRewardsGauge), admin, manager);
        coveRewardsGauge.addReward(MAINNET_DYFI, address(coveRewardsGaugeRewardForwarder));
        coveRewardsGaugeRewardForwarder.approveRewardToken(MAINNET_DYFI);
        // The YearnStakingDelegate will forward the rewards allotted to the treasury to the
        YearnStakingDelegate ysd = YearnStakingDelegate(deployer.getAddress("YearnStakingDelegate"));
        ysd.setTreasury(address(coveRewardsGaugeRewardForwarder));
        coveRewardsGauge.grantRole(DEFAULT_ADMIN_ROLE, admin);
        coveRewardsGauge.grantRole(MANAGER_ROLE, manager);
        coveRewardsGauge.renounceRole(DEFAULT_ADMIN_ROLE, broadcaster);
        coveRewardsGauge.renounceRole(MANAGER_ROLE, broadcaster);
        ysd.renounceRole(DEFAULT_ADMIN_ROLE, broadcaster);
        ysd.renounceRole(TIMELOCK_ROLE, broadcaster);
    }

    function allowlistCoveTokenTransfers(address[] memory transferrers) public broadcast {
        CoveToken coveToken = CoveToken(deployer.getAddress("CoveToken"));
        bytes[] memory data = new bytes[](transferrers.length);
        for (uint256 i = 0; i < transferrers.length; i++) {
            data[i] = abi.encodeWithSelector(CoveToken.addAllowedSender.selector, transferrers[i]);
        }
        coveToken.multicall(data);
        coveToken.grantRole(DEFAULT_ADMIN_ROLE, admin);
        coveToken.renounceRole(DEFAULT_ADMIN_ROLE, broadcaster);
        coveToken.grantRole(TIMELOCK_ROLE, timeLock);
        coveToken.renounceRole(TIMELOCK_ROLE, broadcaster);
    }

    function deployMiniChefV3() public broadcast deployIfMissing("MiniChefV3") returns (address) {
        address miniChefV3 = address(
            deployer.deploy_MiniChefV3({
                name: "MiniChefV3",
                rewardToken_: IERC20(deployer.getAddress("CoveToken")),
                admin: broadcaster,
                pauser: pauser,
                options: options
            })
        );
        // Add Cove token as pid 0 in MiniChefV3 with allocPoint 1000
        MiniChefV3(miniChefV3).add({
            allocPoint: 1000,
            lpToken_: IERC20(deployer.getAddress("CoveToken")),
            rewarder_: IMiniChefV3Rewarder(address(0))
        });
        // Commit some rewards to the MiniChefV3
        CoveToken(deployer.getAddress("CoveToken")).approve(miniChefV3, COVE_BALANCE_MINICHEF);
        MiniChefV3(miniChefV3).commitReward(COVE_BALANCE_MINICHEF);
        MiniChefV3(miniChefV3).grantRole(DEFAULT_ADMIN_ROLE, admin);
        MiniChefV3(miniChefV3).renounceRole(DEFAULT_ADMIN_ROLE, broadcaster);
        MiniChefV3(miniChefV3).grantRole(TIMELOCK_ROLE, timeLock);
        MiniChefV3(miniChefV3).renounceRole(TIMELOCK_ROLE, broadcaster);

        return miniChefV3;
    }

    function sendCoveTokensToAdmin() public broadcast {
        CoveToken coveToken = CoveToken(deployer.getAddress("CoveToken"));
        coveToken.transfer(admin, coveToken.balanceOf(address(broadcaster)));
    }

    function deploySablierStreams(address streamOwner) public broadcast returns (uint256[] memory streamIds) {
        streamIds =
            batchCreateStreams(streamOwner, IERC20(deployer.getAddress("CoveToken")), "/script/vesting/vesting.json");
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
            deployer.deploy_CoveYearnGaugeFactory({
                name: "CoveYearnGaugeFactory",
                factoryAdmin: broadcaster,
                ysd: ysd,
                cove: cove,
                rewardForwarderImpl_: rewardForwarderImpl,
                erc20RewardsGaugeImpl_: erc20RewardsGaugeImpl,
                ysdRewardsGaugeImpl_: ysdRewardsGaugeImpl,
                gaugeAdmin_: admin,
                gaugeManager_: manager,
                gaugePauser_: pauser,
                options: options
            })
        );
        return factory;
    }

    function _populateMasterRegistryMulticall(
        bytes[] memory data,
        uint256 i,
        string memory name
    )
        internal
        view
        returns (uint256)
    {
        data[i++] =
            abi.encodeWithSelector(MasterRegistry.addRegistry.selector, bytes32(bytes(name)), deployer.getAddress(name));
        return i;
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

        bytes[] memory data = new bytes[](9);
        uint256 i = 0;
        i = _populateMasterRegistryMulticall(data, i, "YearnStakingDelegate");
        i = _populateMasterRegistryMulticall(data, i, "StakingDelegateRewards");
        i = _populateMasterRegistryMulticall(data, i, "SwapAndLock");
        i = _populateMasterRegistryMulticall(data, i, "DYFIRedeemer");
        i = _populateMasterRegistryMulticall(data, i, "CoveYFI");
        i = _populateMasterRegistryMulticall(data, i, "CoveYearnGaugeFactory");
        i = _populateMasterRegistryMulticall(data, i, "MiniChefV3");
        i = _populateMasterRegistryMulticall(data, i, "CoveToken");
        i = _populateMasterRegistryMulticall(data, i, "Yearn4626RouterExt");
        require(i == data.length, "Incorrect number of contracts");

        masterRegistry.multicall(data);
    }

    function verifyPostDeploymentState() public view {
        /// CoveToken initial state and balances verification
        IERC20 coveToken = IERC20(deployer.getAddress("CoveToken"));
        // Verify minichef v3 balance
        require(
            coveToken.balanceOf(deployer.getAddress("MiniChefV3")) == COVE_BALANCE_MINICHEF,
            "CoveToken balance in MiniChefV3 is incorrect"
        );
        // Verify total vesting balance
        require(
            coveToken.balanceOf(MAINNET_SABLIER_V2_LOCKUP_LINEAR) == COVE_BALANCE_LINEAR_VESTING,
            "CoveToken balance in SablierV2LockupLinear is incorrect"
        );
        // Verify multisig balance
        require(coveToken.balanceOf(admin) == COVE_BALANCE_MULTISIG, "CoveToken balance in admin multisig is incorrect");
        // Verify deployer holds no cove tokens
        require(coveToken.balanceOf(broadcaster) == COVE_BALANCE_DEPLOYER, "CoveToken balance in deployer is incorrect");
        // Verify Snapshot delegation for "veyfi.eth" space is set to manager
        require(
            ISnapshotDelegateRegistry(MAINNET_SNAPSHOT_DELEGATE_REGISTRY).delegation(
                deployer.getAddress("YearnStakingDelegate"), "veyfi.eth"
            ) == manager,
            "ysd.setSnapshotDelegate failed"
        );
        // Verify roles have been properly set
        /// YearnStakingDelegate
        _verifyRole("YearnStakingDelegate", DEFAULT_ADMIN_ROLE, admin);
        _verifyRole("YearnStakingDelegate", TIMELOCK_ROLE, timeLock);
        _verifyRole("YearnStakingDelegate", PAUSER_ROLE, pauser);
        _verifyRoleCount("YearnStakingDelegate", DEFAULT_ADMIN_ROLE, 1);
        _verifyRoleCount("YearnStakingDelegate", TIMELOCK_ROLE, 1);
        _verifyRoleCount("YearnStakingDelegate", PAUSER_ROLE, 1);
        _verifyRoleCount("YearnStakingDelegate", DEPOSITOR_ROLE, 10);
        /// StakingDelegateRewards
        _verifyRole("StakingDelegateRewards", DEFAULT_ADMIN_ROLE, admin);
        _verifyRoleCount("StakingDelegateRewards", DEFAULT_ADMIN_ROLE, 1);
        _verifyRole("StakingDelegateRewards", TIMELOCK_ROLE, timeLock);
        _verifyRoleCount("StakingDelegateRewards", TIMELOCK_ROLE, 1);
        /// DYFIRedeemer
        _verifyRole("DYFIRedeemer", DEFAULT_ADMIN_ROLE, admin);
        _verifyRoleCount("DYFIRedeemer", DEFAULT_ADMIN_ROLE, 1);
        /// CoveYFI
        _verifyRole("CoveYFI", DEFAULT_ADMIN_ROLE, admin);
        _verifyRoleCount("CoveYFI", DEFAULT_ADMIN_ROLE, 1);
        /// MasterRegistry
        _verifyRole("MasterRegistry", DEFAULT_ADMIN_ROLE, admin);
        _verifyRole("MasterRegistry", MANAGER_ROLE, broadcaster);
        _verifyRoleCount("MasterRegistry", DEFAULT_ADMIN_ROLE, 1);
        _verifyRoleCount("MasterRegistry", MANAGER_ROLE, 2);
        /// DYFIRedeemer
        _verifyRole("DYFIRedeemer", DEFAULT_ADMIN_ROLE, admin);
        _verifyRoleCount("DYFIRedeemer", DEFAULT_ADMIN_ROLE, 1);
        /// CoveToken
        _verifyRole("CoveToken", DEFAULT_ADMIN_ROLE, admin);
        _verifyRole("CoveToken", TIMELOCK_ROLE, timeLock);
        _verifyRoleCount("CoveToken", DEFAULT_ADMIN_ROLE, 1);
        _verifyRoleCount("CoveToken", TIMELOCK_ROLE, 1);
        /// MiniChefV3
        _verifyRole("MiniChefV3", DEFAULT_ADMIN_ROLE, admin);
        _verifyRole("MiniChefV3", PAUSER_ROLE, pauser);
        _verifyRole("MiniChefV3", TIMELOCK_ROLE, timeLock);
        _verifyRoleCount("MiniChefV3", DEFAULT_ADMIN_ROLE, 1);
        _verifyRoleCount("MiniChefV3", PAUSER_ROLE, 1);
        _verifyRoleCount("MiniChefV3", TIMELOCK_ROLE, 1);
        /// CoveYearnGaugeFactory
        _verifyRole("CoveYearnGaugeFactory", DEFAULT_ADMIN_ROLE, broadcaster);
        _verifyRole("CoveYearnGaugeFactory", MANAGER_ROLE, broadcaster);
        _verifyRoleCount("CoveYearnGaugeFactory", DEFAULT_ADMIN_ROLE, 1);
        _verifyRoleCount("CoveYearnGaugeFactory", MANAGER_ROLE, 1);
        /// SwapAndLock
        _verifyRole("SwapAndLock", DEFAULT_ADMIN_ROLE, admin);
        _verifyRoleCount("SwapAndLock", DEFAULT_ADMIN_ROLE, 1);
    }

    function _verifyRole(string memory contractName, bytes32 role, address user) internal view {
        AccessControlEnumerable contractInstance = AccessControlEnumerable(deployer.getAddress(contractName));
        require(contractInstance.hasRole(role, user), string.concat("Incorrect role for: ", contractName));
    }

    function _verifyRoleCount(string memory contractName, bytes32 role, uint256 count) internal view {
        AccessControlEnumerable contractInstance = AccessControlEnumerable(deployer.getAddress(contractName));
        require(
            contractInstance.getRoleMemberCount(role) == count,
            string.concat("Incorrect role count for: ", contractName)
        );
    }

    function getCurrentDeployer() external view returns (Deployer) {
        return deployer;
    }
}
// example run in current setup: DEPLOYMENT_CONTEXT=localhost forge script script/Deployments.s.sol --rpc-url
// http://localhost:8545 --broadcast --private-key ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -v
// && ./forge-deploy sync;

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { BaseDeployScript } from "script/BaseDeployScript.s.sol";
// generated from looking at contracts with ./forge-deploy gen-deployer
import { DeployerFunctions, DefaultDeployerFunction, Deployer } from "generated/deployer/DeployerFunctions.g.sol";
import { CoveYearnGaugeFactory } from "src/registries/CoveYearnGaugeFactory.sol";
import { Yearn4626RouterExt } from "src/Yearn4626RouterExt.sol";
import { PeripheryPayments } from "Yearn-ERC4626-Router/external/PeripheryPayments.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { YearnGaugeStrategy } from "src/strategies/YearnGaugeStrategy.sol";
import { YearnStakingDelegate } from "src/YearnStakingDelegate.sol";
import { CurveSwapParamsConstants } from "test/utils/CurveSwapParamsConstants.sol";
import { console } from "forge-std/console.sol";
import { ITokenizedStrategy } from "tokenized-strategy/interfaces/ITokenizedStrategy.sol";

contract Deployer20240711 is BaseDeployScript, CurveSwapParamsConstants {
    // Using generated functions
    using DeployerFunctions for Deployer;
    // Using default deployer function
    using DefaultDeployerFunction for Deployer;

    address public broadcaster;
    address public admin;
    address public treasury;
    address public manager;
    address public pauser;
    address public timeLock;

    function deploy() public override {
        broadcaster = vm.envAddress("DEPLOYER_ADDRESS");
        require(broadcaster == msg.sender, "Deployer address mismatch. Is --sender set?");
        admin = vm.envOr("COMMUNITY_MULTISIG_ADDRESS", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 1)));
        manager = vm.envOr("OPS_MULTISIG_ADDRESS", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 2)));
        pauser = vm.envOr("PAUSER_ADDRESS", vm.rememberKey(vm.deriveKey(TEST_MNEMONIC, 3)));
        treasury = admin; // TODO: Determine treasury multisig before prod deployment

        vm.label(broadcaster, "broadcaster");
        vm.label(admin, "admin");
        vm.label(manager, "manager");
        vm.label(pauser, "pauser");

        console.log("==========================================================");
        console.log("Using below addresses for deployment:");
        console.log("  Broadcaster:", broadcaster);
        console.log("  Admin:", admin);
        console.log("  Manager:", manager);
        console.log("  Pauser:", pauser);
        console.log("  Treasury:", treasury);
        console.log("==========================================================");

        deployer.setAutoBroadcast(true);

        // Deploy the strategy and grant the factory manager role to the admin
        _deployCoveStrategy(
            deployer.getAddress("YearnStakingDelegate"),
            MAINNET_COVEYFI_YFI_GAUGE,
            getMainnetCoveyfiYfiGaugeCurveSwapParams()
        );
        _grantFactoryManagerRoleToAdmin();

        // TODO: execute these as multisig transactions
        // Deploy the cove gauges from admin address
        _deployCoveGauges(MAINNET_COVEYFI_YFI_GAUGE);
        // Set roles and deposit limit from timelock address
        // USD value per coveyfi/yfi gauge token at the time of deployment
        // 4529.94
        // Limit deposit to max 100,000 USD
        _setRolesAndDepositLimit(MAINNET_COVEYFI_YFI_GAUGE, uint256(100_000e18 * 1e18) / 4529.94e18);
        // Approve tokens in the router
        address[] memory newYearnGauges = new address[](1);
        newYearnGauges[0] = MAINNET_COVEYFI_YFI_GAUGE;
        _approveTokensInRouter(newYearnGauges);
    }

    function _deployCoveStrategy(
        address ysd,
        address yearngauge,
        CurveRouterSwapper.CurveSwapParams memory swapParams
    )
        internal
        deployIfMissing(string.concat("YearnGaugeStrategy-", IERC4626(yearngauge).name()))
    {
        YearnGaugeStrategy strategy = deployer.deploy_YearnGaugeStrategy(
            string.concat("YearnGaugeStrategy-", IERC4626(yearngauge).name()), yearngauge, ysd, MAINNET_CURVE_ROUTER_NG
        );
        vm.startBroadcast();
        // Set the curve swap params for harvest rewards swapping to the asset, gauge token
        strategy.setHarvestSwapParams(swapParams);
        // Set the tokenized strategy roles
        ITokenizedStrategy(address(strategy)).setPerformanceFee(0);
        ITokenizedStrategy(address(strategy)).setPerformanceFeeRecipient(treasury);
        ITokenizedStrategy(address(strategy)).setKeeper(MAINNET_DEFENDER_RELAYER);
        ITokenizedStrategy(address(strategy)).setEmergencyAdmin(admin);
        ITokenizedStrategy(address(strategy)).setPendingManagement(manager);

        vm.stopBroadcast();
    }

    function _grantFactoryManagerRoleToAdmin() internal {
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));
        vm.broadcast();
        factory.grantRole(MANAGER_ROLE, admin);
    }

    function _deployCoveGauges(address yearnGauge) internal {
        vm.startPrank(admin);
        address ysd = deployer.getAddress("YearnStakingDelegate");
        // Allow rewards from yearnGauge to be sent to the staking delegate
        YearnStakingDelegate(ysd).addGaugeRewards(yearnGauge, deployer.getAddress("StakingDelegateRewards"));
        // Deploy the reward gauges for the strategy via the factory
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));
        address strategy = deployer.getAddress(string.concat("YearnGaugeStrategy-", IERC4626(yearnGauge).name()));
        factory.deployCoveGauges(address(strategy));
        vm.stopPrank();
    }

    function _setRolesAndDepositLimit(address yearnGauge, uint256 maxDeposit) internal {
        vm.startPrank(deployer.getAddress("TimelockController"));
        address ysd = deployer.getAddress("YearnStakingDelegate");
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));
        // Grant depositor role to the strategy and the ysd rewards gauge
        CoveYearnGaugeFactory.GaugeInfo memory info = factory.getGaugeInfo(yearnGauge);
        YearnStakingDelegate(ysd).grantRole(DEPOSITOR_ROLE, info.coveYearnStrategy);
        YearnStakingDelegate(ysd).grantRole(DEPOSITOR_ROLE, info.nonAutoCompoundingGauge);
        // Set deposit limit for the gauge token
        YearnStakingDelegate(ysd).setDepositLimit(yearnGauge, maxDeposit);
        vm.stopPrank();
    }

    function _approveTokensInRouter(address[] memory yearnGauges) internal {
        CoveYearnGaugeFactory factory = CoveYearnGaugeFactory(deployer.getAddress("CoveYearnGaugeFactory"));
        CoveYearnGaugeFactory.GaugeInfo[] memory info = new CoveYearnGaugeFactory.GaugeInfo[](yearnGauges.length);
        uint256 numOfTokensToApprove = 5;

        // Get the gauge info for each yearn gauge
        for (uint256 i = 0; i < yearnGauges.length; i++) {
            info[i] = factory.getGaugeInfo(yearnGauges[i]);
        }
        Yearn4626RouterExt router = Yearn4626RouterExt(deployer.getAddress("Yearn4626RouterExt2"));
        bytes[] memory data = new bytes[](info.length * numOfTokensToApprove);

        // Approve the tokens for the yearn vault, yearn gauge, cove strategy, auto compounding gauge and non auto
        // compounding gauge
        for (uint256 i = 0; i < data.length;) {
            CoveYearnGaugeFactory.GaugeInfo memory gaugeInfo = info[i / numOfTokensToApprove];
            data[i++] = abi.encodeWithSelector(
                PeripheryPayments.approve.selector, gaugeInfo.yearnVaultAsset, gaugeInfo.yearnVault, _MAX_UINT256
            );
            data[i++] = abi.encodeWithSelector(
                PeripheryPayments.approve.selector, gaugeInfo.yearnVault, gaugeInfo.yearnGauge, _MAX_UINT256
            );
            data[i++] = abi.encodeWithSelector(
                PeripheryPayments.approve.selector, gaugeInfo.yearnGauge, gaugeInfo.coveYearnStrategy, _MAX_UINT256
            );
            data[i++] = abi.encodeWithSelector(
                PeripheryPayments.approve.selector,
                gaugeInfo.coveYearnStrategy,
                gaugeInfo.autoCompoundingGauge,
                _MAX_UINT256
            );
            data[i++] = abi.encodeWithSelector(
                PeripheryPayments.approve.selector,
                gaugeInfo.yearnGauge,
                gaugeInfo.nonAutoCompoundingGauge,
                _MAX_UINT256
            );
        }
        router.multicall(data);
    }
}

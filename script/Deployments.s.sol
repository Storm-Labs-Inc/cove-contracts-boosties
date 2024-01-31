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
    string public constant MNEMONIC = "test test test test test test test test test test test junk";
    uint256 public senderPK = vm.deriveKey(MNEMONIC, 0);
    address public sender = vm.addr(senderPK);
    uint256 public adminPK = vm.deriveKey(MNEMONIC, 1);
    address public admin = vm.addr(adminPK);
    uint256 public treasuryPK = vm.deriveKey(MNEMONIC, 2);
    address public treasury = vm.addr(treasuryPK);
    uint256 public managerPK = vm.deriveKey(MNEMONIC, 3);
    address public manager = vm.addr(managerPK);

    function deploy() public {
        vm.startBroadcast(senderPK);

        // Deploy Master Registry
        MasterRegistry masterRegistry = deployer.deploy_MasterRegistry("MasterRegistry", admin);

        // Deploy Yearn Staking Delegate Stack
        address gaugeRewardReceiverImpl =
            address(deployer.deploy_GaugeRewardReceiver("GaugeRewardReceiverImplementation"));
        YearnStakingDelegate ysd = deployer.deploy_YearnStakingDelegate(
            "YearnStakingDelegate", gaugeRewardReceiverImpl, treasury, admin, manager
        );
        address stakingDelegateRewards =
            address(deployer.deploy_StakingDelegateRewards("StakingDelegateRewards", MAINNET_DYFI, address(ysd)));
        address swapAndLock = address(deployer.deploy_SwapAndLock("SwapAndLock", address(ysd)));
        deployer.deploy_DYfiRedeemer("DYfiRedeemer");
        deployer.deploy_CoveYFI("CoveYFI", address(ysd));

        // Deploy Cove Strategies for Yearn Gauges
        deployCoveStrategies(address(ysd));

        // Deploy Yearn4626RouterExt
        deployer.deploy_Yearn4626RouterExt("Yearn4626RouterExt", "Yearn4626RouterExt", MAINNET_WETH, MAINNET_PERMIT2);

        // Change settings via the admin address
        vm.stopBroadcast();
        vm.startBroadcast(adminPK);
        ysd.setSwapAndLock(swapAndLock);
        ysd.setSnapshotDelegate("veyfi.eth", treasury);
        ysd.addGaugeRewards(MAINNET_DYFI_ETH_GAUGE, stakingDelegateRewards);
        ysd.addGaugeRewards(MAINNET_ETH_YFI_GAUGE, stakingDelegateRewards);

        // Register contracts in the Master Registry
        bytes[] memory data = new bytes[](6);
        data[0] = abi.encodeWithSelector(masterRegistry.grantRole.selector, keccak256("MANAGER_ROLE"), admin);
        data[1] =
            abi.encodeWithSelector(masterRegistry.addRegistry.selector, bytes32("YearnStakingDelegate"), address(ysd));
        data[2] = abi.encodeWithSelector(
            masterRegistry.addRegistry.selector, bytes32("StakingDelegateRewards"), stakingDelegateRewards
        );
        data[3] = abi.encodeWithSelector(masterRegistry.addRegistry.selector, bytes32("SwapAndLock"), swapAndLock);
        data[4] = abi.encodeWithSelector(
            masterRegistry.addRegistry.selector, bytes32("DYfiRedeemer"), deployer.getAddress("DYfiRedeemer")
        );
        data[5] = abi.encodeWithSelector(
            masterRegistry.addRegistry.selector, bytes32("CoveYFI"), deployer.getAddress("CoveYFI")
        );
        masterRegistry.multicall(data);
    }

    function deployCoveStrategies(address ysd) public {
        YearnGaugeStrategy strategy = deployer.deploy_YearnGaugeStrategy(
            "YearnGaugeStrategy-WETHYETH", MAINNET_WETH_YETH_POOL_GAUGE, ysd, MAINNET_CURVE_ROUTER
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
    }

    function getCurrentDeployer() external view returns (Deployer) {
        return deployer;
    }
}
// example run in current setup: DEPLOYMENT_CONTEXT=localhost forge script script/Deployments.s.sol --rpc-url
// http://localhost:8545 --broadcast --private-key ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -v
// && ./forge-deploy sync;

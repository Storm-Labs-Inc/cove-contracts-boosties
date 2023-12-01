// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";
import { ICurveTwoAssetPool } from "src/interfaces/deps/curve/ICurveTwoAssetPool.sol";
import { SwapAndLock } from "src/SwapAndLock.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { Errors } from "src/libraries/Errors.sol";

contract SwapAndLockTest is YearnV3BaseTest {
    address public yearnStakingDelegate;
    address public swapAndLock;

    function setUp() public override {
        super.setUp();
        address receiver = setUpGaugeRewardReceiverImplementation(admin);
        yearnStakingDelegate = setUpYearnStakingDelegate(receiver, admin, admin, admin);
        address stakingDelegateRewards = setUpStakingDelegateRewards(admin, MAINNET_DYFI, address(yearnStakingDelegate));
        swapAndLock = setUpSwapAndLock(admin, yearnStakingDelegate, stakingDelegateRewards);
    }

    function test_swapDYfiToVeYfi() public {
        uint256 dYfiAmount;
        // Calculate expected yfi amount after swapping through curve pools
        // dYFI -> WETH then WETH -> YFI
        uint256 wethAmount = ICurveTwoAssetPool(MAINNET_DYFI_ETH_POOL).get_dy(0, 1, dYfiAmount);
        uint256 yfiAmount = ICurveTwoAssetPool(MAINNET_YFI_ETH_POOL).get_dy(0, 1, wethAmount);

        vm.prank(admin);
        SwapAndLock(swapAndLock).swapDYfiToVeYfi(yfiAmount);

        // Check for the new veYfi balance
        IVotingYFI.LockedBalance memory lockedBalance = IVotingYFI(MAINNET_VE_YFI).locked(address(yearnStakingDelegate));
        assertApproxEqRel(
            lockedBalance.amount, 1e18 + yfiAmount, 0.001e18, "swapDYfiToVeYfi failed: locked amount is incorrect"
        );
        assertApproxEqRel(
            lockedBalance.end,
            block.timestamp + 4 * 365 days + 4 weeks,
            0.001e18,
            "swapDYfiToVeYfi failed: locked end timestamp is incorrect"
        );
    }

    function test_swapDYfiToVeYfi_revertWhen_NoDYfiToSwap() public { }

    function test_setRouterParams_revertWhen_EmptyPaths() public {
        vm.startPrank(admin);
        CurveRouterSwapper.CurveSwapParams memory params;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFromToken.selector, MAINNET_DYFI, address(0)));
        SwapAndLock(swapAndLock).setRouterParams(params);
    }

    function test_setRouterParams_revertWhen_InvalidFromToken() public {
        vm.startPrank(admin);
        CurveRouterSwapper.CurveSwapParams memory params;
        // Set from token to be USDC instead of dYFI
        params.route[0] = MAINNET_USDC;
        params.route[1] = MAINNET_TRI_CRYPTO_USDC;
        params.route[2] = MAINNET_ETH;
        params.route[3] = MAINNET_YFI_ETH_POOL;
        params.route[4] = MAINNET_YFI;

        params.swapParams[0] = [uint256(0), 2, 1, 2, 2];
        params.swapParams[1] = [uint256(0), 1, 1, 2, 2];
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFromToken.selector, MAINNET_DYFI, MAINNET_USDC));
        SwapAndLock(swapAndLock).setRouterParams(params);
    }

    function test_setRouterParams_revertWhen_InvalidToToken() public {
        vm.prank(admin);
        CurveRouterSwapper.CurveSwapParams memory params;
        params.route[0] = MAINNET_DYFI;
        params.route[1] = MAINNET_DYFI_ETH_POOL;
        params.route[2] = MAINNET_ETH;
        params.route[3] = MAINNET_TRI_CRYPTO_USDC;
        params.route[4] = MAINNET_USDC;

        params.swapParams[0] = [uint256(0), 1, 1, 2, 2];
        params.swapParams[1] = [uint256(2), 0, 1, 2, 2];
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidToToken.selector, MAINNET_YFI, MAINNET_USDC));
        SwapAndLock(swapAndLock).setRouterParams(params);
    }

    function test_setRouterParams_revertWhen_InvalidCoinIndex() public {
        vm.startPrank(admin);
        CurveRouterSwapper.CurveSwapParams memory params;
        // Set route to include a token address that does not exist in the given pools
        params.route[0] = MAINNET_DYFI;
        params.route[1] = MAINNET_DYFI_ETH_POOL;
        params.route[2] = MAINNET_USDC;
        params.route[3] = MAINNET_YFI_ETH_POOL;
        params.route[4] = MAINNET_YFI;

        params.swapParams[0] = [uint256(0), 1, 1, 2, 2];
        params.swapParams[1] = [uint256(0), 1, 1, 2, 2];
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidCoinIndex.selector));
        SwapAndLock(swapAndLock).setRouterParams(params);
    }
}

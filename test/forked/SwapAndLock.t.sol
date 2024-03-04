// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { YearnV3BaseTest } from "test/utils/YearnV3BaseTest.t.sol";
import { ISwapAndLock } from "src/interfaces/ISwapAndLock.sol";
import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { IDYFIRedeemer } from "src/interfaces/IDYFIRedeemer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SwapAndLock_ForkedTest is YearnV3BaseTest {
    address public yearnStakingDelegate;
    address public swapAndLock;
    address public dYfiRedeemer;

    address public redeemCaller;

    function setUp() public override {
        super.setUp();
        redeemCaller = createUser("redeemCaller");
        address receiver = setUpGaugeRewardReceiverImplementation(admin);
        yearnStakingDelegate = setUpYearnStakingDelegate(receiver, admin, admin, admin, admin);
        swapAndLock = setUpSwapAndLock(admin, yearnStakingDelegate);
        dYfiRedeemer = setUpDYfiRedeemer(admin);
        vm.startPrank(admin);
        IYearnStakingDelegate(yearnStakingDelegate).setSwapAndLock(swapAndLock);
        vm.stopPrank();
    }

    function _setDYfiRedeemer(address redeemer) internal {
        vm.startPrank(admin);
        ISwapAndLock(swapAndLock).setDYfiRedeemer(redeemer);
        vm.stopPrank();
    }

    function test_lockYfi() public {
        _setDYfiRedeemer(dYfiRedeemer);
        uint256 dYfiAmount = 10e18;
        airdrop(IERC20(MAINNET_DYFI), swapAndLock, dYfiAmount);

        address[] memory accounts = new address[](1);
        accounts[0] = swapAndLock;
        uint256[] memory dYfiAmounts = new uint256[](1);
        dYfiAmounts[0] = dYfiAmount;
        vm.prank(redeemCaller);
        IDYFIRedeemer(dYfiRedeemer).massRedeem(accounts, dYfiAmounts);
        uint256 yfiAmount = IERC20(MAINNET_YFI).balanceOf(swapAndLock);
        assertGt(yfiAmount, 0, "dYfi was not redeemed for YFI");

        // Check for the new veYFI balance
        vm.prank(admin);
        IVotingYFI.LockedBalance memory lockedBalance = ISwapAndLock(swapAndLock).lockYfi();
        assertApproxEqRel(lockedBalance.amount, yfiAmount, 0.001e18, "lockYfi failed: locked amount is incorrect");
        assertApproxEqRel(
            lockedBalance.end,
            block.timestamp + 4 * 365 days + 4 weeks,
            0.001e18,
            "lockYfi failed: locked end timestamp is incorrect"
        );
    }
}

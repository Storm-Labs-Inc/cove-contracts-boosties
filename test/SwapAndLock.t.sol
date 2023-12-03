// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ISwapAndLock, ISwapAndLockEvents } from "src/interfaces/ISwapAndLock.sol";
import { SwapAndLock } from "src/SwapAndLock.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { MockCurveRouter } from "test/mocks/MockCurveRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { Errors } from "src/libraries/Errors.sol";

contract SwapAndLockTest is BaseTest, ISwapAndLockEvents {
    address public yearnStakingDelegate;
    address public curveRouter;
    address public swapAndLock;
    address public admin;
    address public yfi;
    address public dYfi;

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");

        // Deploy mock tokens
        yfi = MAINNET_YFI;
        vm.etch(yfi, address(new ERC20Mock()).code);
        dYfi = MAINNET_DYFI;
        vm.etch(dYfi, address(new ERC20Mock()).code);

        // Deploy mock contracts to be called in SwapAndLock
        yearnStakingDelegate = address(new MockYearnStakingDelegate());
        curveRouter = address(new MockCurveRouter());

        // Deploy SwapAndLock
        vm.startPrank(admin);
        swapAndLock = address(new SwapAndLock(curveRouter, yearnStakingDelegate));
        ISwapAndLock(swapAndLock).grantRole(ISwapAndLock(swapAndLock).MANAGER_ROLE(), admin);
        vm.stopPrank();
    }

    function _setRouterParams() internal {
        vm.prank(admin);
        ISwapAndLock(swapAndLock).setRouterParams(generateMockCurveSwapParams({ fromToken: dYfi, toToken: yfi }));
    }

    function test_swapDYfiToVeYfi() public {
        _setRouterParams();

        uint256 dYfiAmount = 20e18;
        uint256 yfiAmount = 10e18;
        airdrop(IERC20(dYfi), swapAndLock, dYfiAmount);
        airdrop(IERC20(yfi), curveRouter, yfiAmount);

        vm.expectEmit();
        emit ISwapAndLockEvents.SwapAndLocked(dYfiAmount, yfiAmount, yfiAmount);
        vm.prank(admin);
        ISwapAndLock(swapAndLock).swapDYfiToVeYfi(0);
        assertEq(IERC20(dYfi).balanceOf(address(swapAndLock)), 0);
        assertEq(IERC20(yfi).balanceOf(address(swapAndLock)), 0);
    }

    function test_swapDYfiToVeYfi_revertWhen_NotAuthorized() public {
        _setRouterParams();
        address alice = createUser("alice");
        vm.expectRevert(_formatAccessControlError(alice, ISwapAndLock(swapAndLock).MANAGER_ROLE()));
        vm.prank(alice);
        ISwapAndLock(swapAndLock).swapDYfiToVeYfi(0);
    }

    function test_swapDYfiToVeYfi_revertWhen_NoDYfiToSwap() public {
        _setRouterParams();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.NoDYfiToSwap.selector));
        ISwapAndLock(swapAndLock).swapDYfiToVeYfi(0);
    }

    function testFuzz_swapDYfiToVeYfi(uint256 dYfiAmount, uint256 yfiAmount) public {
        vm.assume(dYfiAmount > 0);
        vm.assume(yfiAmount > 0);

        _setRouterParams();
        airdrop(IERC20(dYfi), swapAndLock, dYfiAmount);
        airdrop(IERC20(yfi), curveRouter, yfiAmount);

        vm.expectEmit();
        emit ISwapAndLockEvents.SwapAndLocked(dYfiAmount, yfiAmount, yfiAmount);
        vm.prank(admin);
        ISwapAndLock(swapAndLock).swapDYfiToVeYfi(0);
        assertEq(IERC20(dYfi).balanceOf(address(swapAndLock)), 0);
        assertEq(IERC20(yfi).balanceOf(address(swapAndLock)), 0);
    }

    function testFuzz_swapDYfiToVeYfi_revertWhen_NotAuthorized(address caller) public {
        _setRouterParams();
        vm.assume(caller != admin);
        vm.expectRevert(_formatAccessControlError(caller, ISwapAndLock(swapAndLock).MANAGER_ROLE()));
        vm.prank(caller);
        ISwapAndLock(swapAndLock).swapDYfiToVeYfi(0);
    }
}

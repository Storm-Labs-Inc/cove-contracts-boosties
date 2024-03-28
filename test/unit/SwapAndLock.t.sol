// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ISwapAndLock } from "src/interfaces/ISwapAndLock.sol";
import { SwapAndLock } from "src/SwapAndLock.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { MockCoveYFI } from "test/mocks/MockCoveYFI.sol";

contract SwapAndLock_Test is BaseTest {
    address public yearnStakingDelegate;
    address public swapAndLock;
    address public admin;
    address public treasury;
    address public yfi;
    address public dYfi;
    address public coveYfi;

    event DYfiRedeemerSet(address oldRedeemer, address newRedeemer);

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        treasury = createUser("treasury");

        // Deploy mock tokens
        yfi = MAINNET_YFI;
        vm.etch(yfi, address(new ERC20Mock()).code);
        dYfi = MAINNET_DYFI;
        vm.etch(dYfi, address(new ERC20Mock()).code);

        // Deploy mock contracts to be called in SwapAndLock
        yearnStakingDelegate = address(new MockYearnStakingDelegate());
        coveYfi = address(new MockCoveYFI(yfi));

        // Deploy SwapAndLock
        swapAndLock = address(new SwapAndLock(yearnStakingDelegate, coveYfi, admin));

        // Mock yearnStakingDelegate.treasury()
        vm.mockCall(
            yearnStakingDelegate, abi.encodeWithSelector(IYearnStakingDelegate.treasury.selector), abi.encode(treasury)
        );
    }

    function test_lockYfi() public {
        uint256 yfiAmount = 10e18;
        airdrop(IERC20(yfi), swapAndLock, yfiAmount);
        vm.prank(admin);
        ISwapAndLock(swapAndLock).convertToCoveYfi();
        assertEq(IERC20(yfi).balanceOf(address(swapAndLock)), 0);
        assertEq(IERC20(coveYfi).balanceOf(address(treasury)), yfiAmount);
    }

    function testFuzz_setDYfiRedeemer(address a) public {
        vm.assume(a != address(0));

        vm.expectEmit();
        emit DYfiRedeemerSet(address(0), a);
        vm.prank(admin);
        ISwapAndLock(swapAndLock).setDYfiRedeemer(a);
        assertEq(ISwapAndLock(swapAndLock).dYfiRedeemer(), a);
        assertEq(IERC20(dYfi).allowance(swapAndLock, a), type(uint256).max);
    }

    function testFuzz_setDYfiRedeemer_passWhen_Replacing(address a, address b) public {
        vm.assume(a != address(0));
        vm.assume(b != address(0));
        vm.assume(a != b);

        vm.expectEmit();
        emit DYfiRedeemerSet(address(0), a);
        vm.prank(admin);
        ISwapAndLock(swapAndLock).setDYfiRedeemer(a);
        assertEq(ISwapAndLock(swapAndLock).dYfiRedeemer(), a);
        assertEq(IERC20(dYfi).allowance(swapAndLock, a), type(uint256).max);
        assertEq(IERC20(dYfi).allowance(swapAndLock, b), 0);

        vm.expectEmit();
        emit DYfiRedeemerSet(a, b);
        vm.prank(admin);
        ISwapAndLock(swapAndLock).setDYfiRedeemer(b);
        assertEq(ISwapAndLock(swapAndLock).dYfiRedeemer(), b);
        assertEq(IERC20(dYfi).allowance(swapAndLock, a), 0);
        assertEq(IERC20(dYfi).allowance(swapAndLock, b), type(uint256).max);
    }

    function test_setDYfiRedeemer_revertWhen_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        ISwapAndLock(swapAndLock).setDYfiRedeemer(address(0));
    }

    function testFuzz_setDYfiRedeemer_revertWhen_SameAddress(address a) public {
        vm.assume(a != address(0));
        vm.startPrank(admin);
        ISwapAndLock(swapAndLock).setDYfiRedeemer(a);
        vm.expectRevert(abi.encodeWithSelector(Errors.SameAddress.selector));
        ISwapAndLock(swapAndLock).setDYfiRedeemer(a);
        vm.stopPrank();
    }
}

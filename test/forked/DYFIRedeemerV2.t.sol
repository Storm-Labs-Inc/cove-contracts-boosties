// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { YearnV3BaseTest } from "test/utils/YearnV3BaseTest.t.sol";
import { DYFIRedeemerV2 } from "src/DYFIRedeemerV2.sol";
import { MockChainLinkOracle } from "test/mocks/MockChainLinkOracle.sol";

contract DYFIRedeemerV2_ForkedTest is YearnV3BaseTest {
    DYFIRedeemerV2 public dYfiRedeemer;
    uint256 public constant MAX_SLIPPAGE = 0.05e18;

    // Users
    address public alice;
    address public bob;
    address public charlie;
    address public caller;

    function setUp() public override {
        super.setUp();
        // Move fork to a block where the new redemption contract is deployed
        forkNetworkAt("mainnet", 22_746_908);
        alice = createUser("alice");
        bob = createUser("bob");
        charlie = createUser("charlie");
        caller = createUser("caller");
        dYfiRedeemer = new DYFIRedeemerV2(admin);
    }

    function test_massRedeem() public {
        uint256 aliceDYfiAmount = 0.02e18;
        uint256 bobDYfiAmount = 0.4e18;
        uint256 charlieDYfiAmount = 0.6e18;
        uint256 totalDYfiAmount = aliceDYfiAmount + bobDYfiAmount + charlieDYfiAmount;

        airdrop(ERC20(MAINNET_DYFI), alice, aliceDYfiAmount);
        airdrop(ERC20(MAINNET_DYFI), bob, bobDYfiAmount);
        airdrop(ERC20(MAINNET_DYFI), charlie, charlieDYfiAmount);

        vm.prank(alice);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);
        vm.prank(bob);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);
        vm.prank(charlie);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);

        uint256 aliceMinYfi = dYfiRedeemer.currentYfiRedeem(aliceDYfiAmount);
        uint256 bobMinYfi = dYfiRedeemer.currentYfiRedeem(bobDYfiAmount);
        uint256 charlieMinYfi = dYfiRedeemer.currentYfiRedeem(charlieDYfiAmount);

        address[] memory dYfiHolders = new address[](3);
        dYfiHolders[0] = alice;
        dYfiHolders[1] = bob;
        dYfiHolders[2] = charlie;
        uint256[] memory dYfiAmounts = new uint256[](3);
        dYfiAmounts[0] = aliceDYfiAmount;
        dYfiAmounts[1] = bobDYfiAmount;
        dYfiAmounts[2] = charlieDYfiAmount;

        uint256 expectedReward = dYfiRedeemer.expectedMassRedeemReward(totalDYfiAmount);
        uint256 callerEthBalanceBefore = caller.balance;
        vm.prank(caller);
        dYfiRedeemer.massRedeem(dYfiHolders, dYfiAmounts);
        uint256 callerEthBalanceAfter = caller.balance;

        assertApproxEqRel(IERC20(MAINNET_YFI).balanceOf(address(alice)), aliceMinYfi, 0.00001e18);
        assertApproxEqRel(IERC20(MAINNET_YFI).balanceOf(address(bob)), bobMinYfi, 0.00001e18);
        assertApproxEqRel(IERC20(MAINNET_YFI).balanceOf(address(charlie)), charlieMinYfi, 0.00001e18);

        assertApproxEqRel(callerEthBalanceAfter - callerEthBalanceBefore, expectedReward, 0.00001e18);
    }

    function test_massRedeem_LargeAmounts_v2() public {
        uint256 aliceDYfiAmount = 1e18;
        uint256 bobDYfiAmount = 2e18;
        uint256 charlieDYfiAmount = 3e18;
        uint256 totalDYfiAmount = aliceDYfiAmount + bobDYfiAmount + charlieDYfiAmount;

        airdrop(ERC20(MAINNET_DYFI), alice, aliceDYfiAmount);
        airdrop(ERC20(MAINNET_DYFI), bob, bobDYfiAmount);
        airdrop(ERC20(MAINNET_DYFI), charlie, charlieDYfiAmount);

        vm.prank(alice);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);
        vm.prank(bob);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);
        vm.prank(charlie);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);

        uint256 aliceMinYfi = dYfiRedeemer.currentYfiRedeem(aliceDYfiAmount);
        uint256 bobMinYfi = dYfiRedeemer.currentYfiRedeem(bobDYfiAmount);
        uint256 charlieMinYfi = dYfiRedeemer.currentYfiRedeem(charlieDYfiAmount);

        address[] memory dYfiHolders = new address[](3);
        dYfiHolders[0] = alice;
        dYfiHolders[1] = bob;
        dYfiHolders[2] = charlie;
        uint256[] memory dYfiAmounts = new uint256[](3);
        dYfiAmounts[0] = aliceDYfiAmount;
        dYfiAmounts[1] = bobDYfiAmount;
        dYfiAmounts[2] = charlieDYfiAmount;

        // uint256 expectedReward = dYfiRedeemer.expectedMassRedeemReward(totalDYfiAmount);

        uint256 callerEthBalanceBefore = caller.balance;
        vm.prank(caller);
        dYfiRedeemer.massRedeem(dYfiHolders, dYfiAmounts);
        uint256 callerEthBalanceAfter = caller.balance;

        assertApproxEqRel(IERC20(MAINNET_YFI).balanceOf(address(alice)), aliceMinYfi, 0.00001e18);
        assertApproxEqRel(IERC20(MAINNET_YFI).balanceOf(address(bob)), bobMinYfi, 0.00001e18);
        assertApproxEqRel(IERC20(MAINNET_YFI).balanceOf(address(charlie)), charlieMinYfi, 0.00001e18);

        // assertApproxEqRel(callerEthBalanceAfter - callerEthBalanceBefore, expectedReward, 0.00001e18);
    }

    function test_massRedeem_passWhen_CallerIsGnosisSafe() public {
        uint256 aliceDYfiAmount = 0.02e18;
        uint256 bobDYfiAmount = 0.4e18;
        uint256 charlieDYfiAmount = 0.6e18;
        uint256 totalDYfiAmount = aliceDYfiAmount + bobDYfiAmount + charlieDYfiAmount;

        airdrop(ERC20(MAINNET_DYFI), alice, aliceDYfiAmount);
        airdrop(ERC20(MAINNET_DYFI), bob, bobDYfiAmount);
        airdrop(ERC20(MAINNET_DYFI), charlie, charlieDYfiAmount);

        vm.prank(alice);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);
        vm.prank(bob);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);
        vm.prank(charlie);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);

        address[] memory dYfiHolders = new address[](3);
        dYfiHolders[0] = alice;
        dYfiHolders[1] = bob;
        dYfiHolders[2] = charlie;
        uint256[] memory dYfiAmounts = new uint256[](3);
        dYfiAmounts[0] = aliceDYfiAmount;
        dYfiAmounts[1] = bobDYfiAmount;
        dYfiAmounts[2] = charlieDYfiAmount;

        uint256 aliceMinYfi = dYfiRedeemer.currentYfiRedeem(aliceDYfiAmount);
        uint256 bobMinYfi = dYfiRedeemer.currentYfiRedeem(bobDYfiAmount);
        uint256 charlieMinYfi = dYfiRedeemer.currentYfiRedeem(charlieDYfiAmount);

        // Caller is a gnosis safe
        // https://etherscan.io/address/0xc234e41ae2cb00311956aa7109fc801ae8c80941#code
        caller = 0xC234E41AE2cb00311956Aa7109fC801ae8c80941;
        uint256 expectedReward = dYfiRedeemer.expectedMassRedeemReward(totalDYfiAmount);
        uint256 callerEthBalanceBefore = caller.balance;
        vm.prank(caller);
        dYfiRedeemer.massRedeem(dYfiHolders, dYfiAmounts);
        uint256 callerEthBalanceAfter = caller.balance;

        assertApproxEqRel(IERC20(MAINNET_YFI).balanceOf(address(alice)), aliceMinYfi, 0.00001e18);
        assertApproxEqRel(IERC20(MAINNET_YFI).balanceOf(address(bob)), bobMinYfi, 0.00001e18);
        assertApproxEqRel(IERC20(MAINNET_YFI).balanceOf(address(charlie)), charlieMinYfi, 0.00001e18);
        assertApproxEqRel(callerEthBalanceAfter - callerEthBalanceBefore, expectedReward, 0.00001e18);
    }

    function test_massRedeem_revertWhen_InvalidArrayLength() public {
        address[] memory dYfiHolders = new address[](2);
        dYfiHolders[0] = alice;
        dYfiHolders[1] = bob;
        uint256[] memory dYfiAmounts = new uint256[](3);
        dYfiAmounts[0] = 0.02e18;
        dYfiAmounts[1] = 0.4e18;
        dYfiAmounts[2] = 0.6e18;

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidArrayLength.selector));
        dYfiRedeemer.massRedeem(dYfiHolders, dYfiAmounts);
    }

    function test_massRedeem_revertWhen_NoDYfiToRedeem() public {
        address[] memory dYfiHolders = new address[](3);
        dYfiHolders[0] = alice;
        dYfiHolders[1] = bob;
        dYfiHolders[2] = charlie;
        uint256[] memory dYfiAmounts = new uint256[](3);
        dYfiAmounts[0] = 0;
        dYfiAmounts[1] = 0;
        dYfiAmounts[2] = 0;

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.NoDYfiToRedeem.selector));
        dYfiRedeemer.massRedeem(dYfiHolders, dYfiAmounts);
    }

    function test_massRedeem_revertWhen_CallerRewardEthTransferFailed() public {
        uint256 aliceDYfiAmount = 0.02e18;
        uint256 bobDYfiAmount = 0.4e18;
        uint256 charlieDYfiAmount = 0.3e18;

        airdrop(ERC20(MAINNET_DYFI), alice, aliceDYfiAmount);
        airdrop(ERC20(MAINNET_DYFI), bob, bobDYfiAmount);
        airdrop(ERC20(MAINNET_DYFI), charlie, charlieDYfiAmount);

        vm.prank(alice);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);
        vm.prank(bob);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);
        vm.prank(charlie);
        IERC20(MAINNET_DYFI).approve(address(dYfiRedeemer), type(uint256).max);

        address[] memory dYfiHolders = new address[](3);
        dYfiHolders[0] = alice;
        dYfiHolders[1] = bob;
        dYfiHolders[2] = charlie;
        uint256[] memory dYfiAmounts = new uint256[](3);
        dYfiAmounts[0] = aliceDYfiAmount;
        dYfiAmounts[1] = bobDYfiAmount;
        dYfiAmounts[2] = charlieDYfiAmount;

        vm.prank(address(this)); // This test contract has no receive function
        vm.expectRevert(abi.encodeWithSelector(Errors.CallerRewardEthTransferFailed.selector));
        dYfiRedeemer.massRedeem(dYfiHolders, dYfiAmounts);
    }

    function test_massRedeem_revertWhen_Paused() public {
        address[] memory dYfiHolders = new address[](3);
        uint256[] memory dYfiAmounts = new uint256[](3);

        vm.prank(admin);
        dYfiRedeemer.kill();
        vm.prank(caller);
        vm.expectRevert("Pausable: paused");
        dYfiRedeemer.massRedeem(dYfiHolders, dYfiAmounts);
    }

    function test_setSlippage() public {
        uint256 slippage = 0.02e18;
        vm.prank(admin);
        dYfiRedeemer.setSlippage(slippage);
        assertEq(dYfiRedeemer.slippage(), slippage);
    }

    function testFuzz_setSlippage_revertWhen_SlippageTooHigh(uint256 slippage) public {
        vm.assume(slippage > MAX_SLIPPAGE);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.SlippageTooHigh.selector));
        dYfiRedeemer.setSlippage(slippage);
    }

    function testFuzz_setSlippage_revertWhen_CallerIsNotAdmin(address a) public {
        vm.assume(a != admin);
        vm.expectRevert(_formatAccessControlError(a, DEFAULT_ADMIN_ROLE));
        vm.prank(a);
        dYfiRedeemer.setSlippage(0.02e18);
    }

    function testFuzz_minYfiRedeem(uint256 dYfiAmount) public {
        vm.assume(dYfiAmount > 1e3); // minimum dYfi amount required to simulate
        vm.assume(dYfiAmount < type(uint128).max);
        vm.prank(admin);
        assertGt(dYfiRedeemer.currentYfiRedeem(dYfiAmount), dYfiRedeemer.minYfiRedeem(dYfiAmount));
    }

    function test_getLatestPrice_revertWhen_PriceFeedReturnedZeroPrice() public {
        MockChainLinkOracle mockOracle = new MockChainLinkOracle(0);
        // etch mock oracle code to _YFI_ETH_PRICE_FEED address
        vm.etch(MAINNET_YFI_ETH_PRICE_FEED, address(mockOracle).code);
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceFeedReturnedZeroPrice.selector));
        dYfiRedeemer.getLatestPrice();
    }

    function test_getLatestPrice_revertWhen_PriceFeedIncorrectRound() public {
        MockChainLinkOracle mockOracle = new MockChainLinkOracle(0);
        // etch mock oracle code to _YFI_ETH_PRICE_FEED address
        vm.etch(MAINNET_YFI_ETH_PRICE_FEED, address(mockOracle).code);
        MockChainLinkOracle oracle = MockChainLinkOracle(MAINNET_YFI_ETH_PRICE_FEED);
        oracle.setPrice(1);
        oracle.setRoundID(2);
        oracle.setAnswerInRound(1);
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceFeedIncorrectRound.selector));
        dYfiRedeemer.getLatestPrice();
    }

    function test_expectedMassRedeemReward_ReturnsZeroOnZeroTotalDYfi() public {
        assertEq(dYfiRedeemer.expectedMassRedeemReward(0), 0);
    }

    function testFuzz_receiveFlashLoan_revertWhen_NotAuthorized(address a) public {
        vm.assume(a != MAINNET_BALANCER_FLASH_LOAN_PROVIDER);
        vm.prank(a);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthorized.selector));
        dYfiRedeemer.receiveFlashLoan(new IERC20[](0), new uint256[](0), new uint256[](0), "");
    }

    function testFuzz_receiverFlashLoan_revertWhen_InvalidTokensReceived(address t) public {
        vm.assume(t != MAINNET_WETH);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(t);
        vm.prank(MAINNET_BALANCER_FLASH_LOAN_PROVIDER);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTokensReceived.selector));
        dYfiRedeemer.receiveFlashLoan(tokens, new uint256[](tokens.length), new uint256[](tokens.length), "");
    }

    function testFuzz_receiverFlashLoan_revertWhen_InvalidTokensReceived_InvalidTokensArrayLength(uint256 len) public {
        len = bound(len, 1, 2000);
        IERC20[] memory tokens = new IERC20[](len);
        vm.prank(MAINNET_BALANCER_FLASH_LOAN_PROVIDER);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTokensReceived.selector));
        dYfiRedeemer.receiveFlashLoan(tokens, new uint256[](1), new uint256[](1), "");
    }

    function testFuzz_receiverFlashLoan_revertWhen_InvalidTokensReceived_InvalidAmountsArrayLength(uint256 len)
        public
    {
        len = bound(len, 1, 2000);
        uint256[] memory amounts = new uint256[](len);
        vm.prank(MAINNET_BALANCER_FLASH_LOAN_PROVIDER);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTokensReceived.selector));
        dYfiRedeemer.receiveFlashLoan(new IERC20[](1), amounts, new uint256[](1), "");
    }

    function testFuzz_receiverFlashLoan_revertWhen_InvalidTokensReceived_InvalidFeesArrayLength(uint256 len) public {
        len = bound(len, 1, 2000);
        uint256[] memory fees = new uint256[](len);
        vm.prank(MAINNET_BALANCER_FLASH_LOAN_PROVIDER);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTokensReceived.selector));
        dYfiRedeemer.receiveFlashLoan(new IERC20[](1), new uint256[](1), fees, "");
    }

    function test_getLatestPrice_revertWhen_PriceFeedOutdated() public {
        vm.warp(block.timestamp + 86_400);
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceFeedOutdated.selector));
        dYfiRedeemer.getLatestPrice();
    }

    function testFuzz_kill_revertWhen_CallerIsNotAdmin(address a) public {
        vm.assume(a != admin);
        vm.expectRevert(_formatAccessControlError(a, DEFAULT_ADMIN_ROLE));
        vm.prank(a);
        dYfiRedeemer.kill();
    }

    function test_kill_revertWhen_AlreadyPaused() public {
        vm.startPrank(admin);
        dYfiRedeemer.kill();
        vm.expectRevert("Pausable: paused");
        dYfiRedeemer.kill();
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { CoveYFI } from "src/CoveYFI.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { YearnV3BaseTest } from "test/utils/YearnV3BaseTest.t.sol";

contract CoveYFI_ForkedTest is YearnV3BaseTest {
    CoveYFI public coveYFI;

    // Addresses
    address public bob;
    address public yearnStakingDelegate;

    function setUp() public override {
        super.setUp();

        bob = createUser("bob");

        address receiver = setUpGaugeRewardReceiverImplementation(admin);
        yearnStakingDelegate = setUpYearnStakingDelegate(receiver, admin, admin, admin);

        coveYFI = new CoveYFI(yearnStakingDelegate, admin);
    }

    function testFuzz_constructor(address noAdminAddress) public {
        vm.assume(noAdminAddress != admin);

        // Check for storage variables default values
        assertEq(coveYFI.name(), "Cove YFI");
        assertEq(coveYFI.symbol(), "coveYFI");
        assertEq(coveYFI.yfi(), MAINNET_YFI);
        assertEq(coveYFI.yearnStakingDelegate(), yearnStakingDelegate);
        // Check for ownership
        assertTrue(coveYFI.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertFalse(coveYFI.hasRole(DEFAULT_ADMIN_ROLE, noAdminAddress));
        // Check for approvals
        assertEq(IERC20(MAINNET_YFI).allowance(address(coveYFI), yearnStakingDelegate), type(uint256).max);
    }

    function test_deposit() public {
        airdrop(ERC20(MAINNET_YFI), admin, 1e18);

        vm.startPrank(admin);
        IERC20(MAINNET_YFI).approve(address(coveYFI), type(uint256).max);
        CoveYFI(coveYFI).deposit(1e18);
        assertEq(IERC20(coveYFI).balanceOf(address(admin)), 1e18);
        vm.stopPrank();
    }

    function test_deposit_passWhen_ReceiverIsGiven() public {
        airdrop(ERC20(MAINNET_YFI), admin, 1e18);

        vm.startPrank(admin);
        IERC20(MAINNET_YFI).approve(address(coveYFI), type(uint256).max);
        CoveYFI(coveYFI).deposit(1e18, address(this));
        assertEq(IERC20(coveYFI).balanceOf(address(this)), 1e18);
        vm.stopPrank();
    }

    function test_deposit_passWhen_ReceiverIsZero() public {
        airdrop(ERC20(MAINNET_YFI), admin, 1e18);

        vm.startPrank(admin);
        IERC20(MAINNET_YFI).approve(address(coveYFI), type(uint256).max);
        CoveYFI(coveYFI).deposit(1e18, address(0));
        assertEq(IERC20(coveYFI).balanceOf(address(admin)), 1e18);
        vm.stopPrank();
    }

    function test_deposit_revertsOnZero() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        CoveYFI(coveYFI).deposit(0);
        vm.stopPrank();
    }

    function test_rescue() public {
        deal(address(coveYFI), 1e18);
        vm.prank(admin);
        CoveYFI(coveYFI).rescue(IERC20(address(0)), bob, 1e18);
        // createUser deals new addresses 100 ETH
        assertEq(address(bob).balance, 100 ether + 1e18, "rescue failed");
    }

    function test_rescue_revertsOnNonOwner() public {
        vm.prank(bob);
        vm.expectRevert(_formatAccessControlError(bob, DEFAULT_ADMIN_ROLE));
        CoveYFI(coveYFI).rescue(IERC20(address(0)), admin, 1e18);
    }
}

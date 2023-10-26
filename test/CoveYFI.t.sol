// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { CoveYFI } from "src/CoveYFI.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Errors } from "../src/libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { YearnV3BaseTest } from "./utils/YearnV3BaseTest.t.sol";

contract CoveYFITest is YearnV3BaseTest {
    CoveYFI public coveYFI;

    // Addresses
    address public bob;
    address public yearnStakingDelegate;

    function setUp() public override {
        super.setUp();

        bob = createUser("bob");

        yearnStakingDelegate = setUpYearnStakingDelegate(admin, admin, admin);

        vm.prank(admin);
        coveYFI = new CoveYFI(MAINNET_YFI, yearnStakingDelegate);
    }

    function testFuzz_constructor(address noAdminAddress) public {
        vm.assume(noAdminAddress != admin);

        // Check for storage variables default values
        assertEq(coveYFI.name(), "Cove YFI");
        assertEq(coveYFI.symbol(), "coveYFI");
        assertEq(coveYFI.yfi(), MAINNET_YFI);
        assertEq(coveYFI.yearnStakingDelegate(), yearnStakingDelegate);
        // Check for ownership
        assertEq(coveYFI.owner(), admin);
        assertNotEq(coveYFI.owner(), noAdminAddress);
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

    function test_deposit_whenPaused() public {
        airdrop(ERC20(MAINNET_YFI), admin, 1e18);

        vm.startPrank(admin);
        CoveYFI(coveYFI).pause();

        IERC20(MAINNET_YFI).approve(address(coveYFI), type(uint256).max);
        CoveYFI(coveYFI).deposit(1e18);
        assertEq(IERC20(coveYFI).balanceOf(address(admin)), 1e18);
        vm.stopPrank();
    }

    function test_deposit_revertsOnZero() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAmount.selector));
        CoveYFI(coveYFI).deposit(0);
        vm.stopPrank();
    }

    function test_pause_unpause() public {
        airdrop(ERC20(coveYFI), admin, 1e18);

        vm.startPrank(admin);
        CoveYFI(coveYFI).pause();
        CoveYFI(coveYFI).unpause();

        ERC20(coveYFI).transfer(bob, 1e18);
        assertEq(IERC20(coveYFI).balanceOf(address(bob)), 1e18);
        vm.stopPrank();
    }

    function test_pause_revertsOnTransfer() public {
        airdrop(ERC20(coveYFI), admin, 1e18);

        vm.startPrank(admin);
        CoveYFI(coveYFI).pause();

        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyMintingEnabled.selector));
        ERC20(coveYFI).transfer(bob, 1e18);
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
        vm.expectRevert("Ownable: caller is not the owner");
        CoveYFI(coveYFI).rescue(IERC20(address(0)), admin, 1e18);
    }
}

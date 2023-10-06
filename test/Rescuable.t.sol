// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { BaseTest } from "./utils/BaseTest.t.sol";
import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { MockRescuable } from "./mocks/MockRescuable.sol";
import { MockNonPayable } from "./mocks/MockNonPayable.sol";
import { ERC20Mock } from "@openzeppelin-5.0/contracts/mocks/token/ERC20Mock.sol";

contract RescuableTest is BaseTest {
    MockRescuable public mockRescuable;

    // Addresses
    address public alice;
    address public shitcoin;
    address public nonPayable;

    function setUp() public override {
        super.setUp();

        alice = createUser("alice");
        shitcoin = address(new ERC20Mock());
        mockRescuable = new MockRescuable();
        nonPayable = address(new MockNonPayable());
    }

    function testFuzz_rescue_eth(uint256 amount) public {
        vm.assume(amount != 0);
        // createUser deals new addresses 100 ETH, so set to 0
        deal(alice, 0);
        deal(address(mockRescuable), amount);
        mockRescuable.rescue(IERC20(address(0)), alice, amount);
        assertEq(address(alice).balance, amount, "rescue failed");
    }

    function test_rescue_eth_zeroBalance() public {
        deal(address(mockRescuable), 1e18);
        mockRescuable.rescue(IERC20(address(0)), alice, 0);
        // createUser deals new addresses 100 ETH
        assertEq(address(alice).balance, 100 ether + 1e18, "rescue failed");
    }

    function test_rescue_eth_balanceExceedsTotalBalance() public {
        deal(address(mockRescuable), 1e18);
        mockRescuable.rescue(IERC20(address(0)), alice, 2e18);
        // createUser deals new addresses 100 ETH
        assertEq(address(alice).balance, 100 ether + 1e18, "rescue failed");
    }

    function test_rescue_eth_revertsOnZeroBalance() public {
        vm.expectRevert("trying to send 0 ETH");
        mockRescuable.rescue(IERC20(address(0)), alice, 1e18);
    }

    function test_rescue_eth_revertsOnFailedTransfer() public {
        deal(address(mockRescuable), 1e18);
        vm.expectRevert("ETH transfer failed");
        mockRescuable.rescue(IERC20(address(0)), nonPayable, 1e18);
    }

    function testFuzz_rescue_erc20(uint256 amount) public {
        vm.assume(amount != 0);
        airdrop(ERC20(shitcoin), address(mockRescuable), amount);
        mockRescuable.rescue(IERC20(shitcoin), alice, amount);
        assertEq(IERC20(shitcoin).balanceOf(alice), amount, "rescue failed");
    }

    function test_rescue_erc20_zeroBalance() public {
        airdrop(ERC20(shitcoin), address(mockRescuable), 1e18);
        mockRescuable.rescue(IERC20(shitcoin), alice, 0);
        assertEq(IERC20(shitcoin).balanceOf(alice), 1e18, "rescue failed");
    }

    function test_rescue_erc20_balanceExceedsTotalBalance() public {
        airdrop(ERC20(shitcoin), address(mockRescuable), 1e18);
        mockRescuable.rescue(IERC20(shitcoin), alice, 2e18);
        assertEq(IERC20(shitcoin).balanceOf(alice), 1e18, "rescue failed");
    }

    function test_rescue_erc20_revertsOnZeroBalance() public {
        vm.expectRevert("trying to send 0 balance");
        mockRescuable.rescue(IERC20(shitcoin), alice, 1e18);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Constants} from "./utils/Constants.sol";

abstract contract BaseTest is Test, Constants {
    //// VARIABLES ////
    Users internal _users;

    //// TEST CONTRACTS
    ERC20 internal _usdc;
    ERC20 internal _dai;

    //// SETUP FUNCTION ////
    function setUp() public virtual {
        // Deploy test token contracts.
        _usdc = new ERC20("USDC Stablecoin", "USDC");
        _dai = new ERC20("Dai Stablecoin", "DAI");

        vm.label({account: address(_usdc), newLabel: "USDC"});
        vm.label({account: address(_dai), newLabel: "DAI"});

        // Create users for testing.
        _users = Users({
            admin: _createUser("Admin"),
            alice: _createUser("Alice"),
            attacker: _createUser("Attacker"),
            recipient: _createUser("Recipient"),
            sender: _createUser("Sender")
        });

        // Warp to Jan 1, 2023 at 00:00 GMT to provide a more realistic testing environment.
        vm.warp(_JAN_1_2023);
    }

    //// HELPERS ////

    /**
     * @dev Generates a user, labels its address, and funds it with test assets.
     * @param name The name of the user.
     * @return The address of the user.
     */
    function _createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: 100 ether});
        deal({token: address(_usdc), to: user, give: 1_000_000e18});
        deal({token: address(_dai), to: user, give: 1_000_000e18});
        return user;
    }

    /**
     * @dev Approves a list of contracts to spend the maximum of funds for a user.
     * @param contractAddresses The list of contracts to approve.
     * @param userAddresses The users to approve the contracts for.
     */
    function _approveProtocol(address[] calldata contractAddresses, address[] calldata userAddresses) internal {
        for (uint256 i = 0; i < contractAddresses.length; i++) {
            for (uint256 n = 0; n < userAddresses.length; n++) {
                changePrank(userAddresses[n]);
                IERC20(contractAddresses[i]).approve(userAddresses[n], _MAX_UINT256);
            }
        }
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Test, console2 } from "forge-std/Test.sol";
import { ERC20 } from "openzeppelin-contracts-v4.9.3/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin-contracts-v4.9.3/token/ERC20/IERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Constants } from "./Constants.sol";

abstract contract BaseTest is Test, Constants {
    //// VARIABLES ////
    struct Fork {
        uint256 forkId;
        uint256 blockNumber;
    }

    mapping(string => address) public users;
    mapping(string => Fork) public forks;

    //// TEST CONTRACTS
    ERC20 internal _usdc;
    ERC20 internal _dai;

    //// SETUP FUNCTION ////
    function setUp() public virtual {
        // Deploy test token contracts.
        _usdc = new ERC20("USDC Stablecoin", "USDC");
        _dai = new ERC20("Dai Stablecoin", "DAI");

        vm.label({ account: address(_usdc), newLabel: "USDC" });
        vm.label({ account: address(_dai), newLabel: "DAI" });

        // Create users for testing.
        createUser("admin");
        createUser("alice");
        createUser("attacker");
        createUser("recipient");
        createUser("sender");

        // Warp to Jan 1, 2023 at 00:00 GMT to provide a more realistic testing environment.
        vm.warp(_JAN_1_2023);
    }

    //// HELPERS ////

    /**
     * @dev Generates a user, labels its address, and funds it with test assets.
     * @param name The name of the user.
     * @return The address of the user.
     */
    function createUser(string memory name) public returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({ account: user, newBalance: 100 ether });
        deal({ token: address(_usdc), to: user, give: 1_000_000e18 });
        deal({ token: address(_dai), to: user, give: 1_000_000e18 });
        users[name] = user;
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

    //// FORKING UTILS ////

    /**
     * @dev Creates a fork at a given block.
     * @param network The name of the network, matches an entry in the foundry.toml
     * @param blockNumber The block number to fork from.
     * @return The fork id.
     */
    // TODO: Why does this break when the fork functions are overloaded
    function forkNetworkAt(string memory network, uint256 blockNumber) public returns (uint256) {
        string memory rpcURL = vm.rpcUrl(network);
        uint256 forkId = vm.createSelectFork(rpcURL, blockNumber);
        forks[network] = Fork({ forkId: forkId, blockNumber: blockNumber });
        console2.log("Started fork ", network, " at block ", block.number);
        console2.log("with id", forkId);
        return forkId;
    }

    /**
     * @dev Creates a fork at the latest block number.
     * @param network The name of the network, matches an entry in the foundry.toml
     * @return The fork id.
     */
    function forkNetwork(string memory network) public returns (uint256) {
        string memory rpcURL = vm.rpcUrl(network);
        uint256 forkId = vm.createSelectFork(rpcURL);
        forks[network] = Fork({ forkId: forkId, blockNumber: block.number });
        console2.log("Started fork ", network, "at block ", block.number);
        console2.log("with id", forkId);
        return forkId;
    }

    function selectNamedFork(string memory network) public {
        vm.selectFork(forks[network].forkId);
    }
}

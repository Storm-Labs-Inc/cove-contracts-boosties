// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

abstract contract ForkUtils is Test {
    struct Fork {
        uint256 forkId;
        uint256 blockNumber;
    }

    mapping(string => Fork) public forks;

    /**
     * @dev Creates a fork at a given block.
     * @param network The name of the network, matches an entry in the .env like: "network"_RPC_URL.
     * @param blockNumber The block number to fork from.
     * @return The fork id.
     */
    function forkNetwork(string calldata network, uint256 blockNumber) public returns (uint256) {
        uint256 forkId = vm.createSelectFork(vm.envString(string(abi.encodePacked(network, "_RPC_URL"))), blockNumber);
        forks[network] = Fork({forkId: forkId, blockNumber: blockNumber});
        console2.log("Started fork ", network, " at block ", block.number);
        console2.log("with id", forkId);
        return forkId;
    }

    /**
     * @dev Creates a fork at the latest block number.
     * @param network The name of the network, matches an entry in the .env like: "network"_RPC_URL.
     * @return The fork id.
     */
    function forkNetwork(string calldata network) public returns (uint256) {
        uint256 forkId = vm.createSelectFork(vm.envString(string(abi.encodePacked(network, "_RPC_URL"))));
        forks[network] = Fork({forkId: forkId, blockNumber: block.number});
        console2.log("Started fork ", network, "at block ", block.number);
        console2.log("with id", forkId);
        return forkId;
    }

    function selectNamedFork(string calldata network) public {
        vm.selectFork(forks[network].forkId);
    }
}

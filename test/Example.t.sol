pragma solidity ^0.8.17;

// import {Vm} from "forge-std/Vm.sol";
import "../src/Counter.sol";
import "./utils/BaseTest.t.sol";

contract ExampleTest is Test, BaseTest {
    Counter public counter;

    function setUp() public override {
        BaseTest.setUp();
        // counter = new Counter();
        // counter.setNumber(0);
    }

    function testUserSetup() public view {
        assert(users["admin"] != address(0x0));
        assert(users["alice"] != address(0x0));
        assert(users["attacker"] != address(0x0));
        assert(users["recipient"] != address(0x0));
        assert(users["sender"] != address(0x0));
    }

    function testCreateUser() public {
        createUser("Bob");
        assert(users["Bob"] != address(0x0));
        assert(address(users["Bob"]).balance == 100 ether);
        assert(_usdc.balanceOf(address(users["Bob"])) == 1_000_000e18);
        assert(_dai.balanceOf(address(users["Bob"])) == 1_000_000e18);
    }

    function testForkNetwork() public {
        BaseTest.forkNetwork("mainnet");
        assertEq(BaseTest.forks["mainnet"].blockNumber, block.number);
        assertEq(vm.activeFork(), BaseTest.forks["mainnet"].forkId);
    }

    function testForkNetworkAt() public {
        BaseTest.forkNetworkAt("mainnet", 10);
        assertEq(BaseTest.forks["mainnet"].blockNumber, block.number);
        assertEq(vm.activeFork(), BaseTest.forks["mainnet"].forkId);
    }

    function testMultipleNetwork() public {
        BaseTest.forkNetwork("mainnet");
        BaseTest.forkNetwork("aurora");
        BaseTest.selectNamedFork("mainnet");
        assertEq(vm.activeFork(), BaseTest.forks["mainnet"].forkId);
        BaseTest.selectNamedFork("aurora");
        assertEq(vm.activeFork(), BaseTest.forks["aurora"].forkId);
    }
}

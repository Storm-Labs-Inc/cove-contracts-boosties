// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants } from "./Constants.sol";
import { VyperDeployer } from "./VyperDeployer.sol";
import { Errors } from "src/libraries/Errors.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

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

    //// HELPER CONTRACTS
    VyperDeployer public vyperDeployer;

    //// SETUP FUNCTION ////
    function setUp() public virtual {
        // Instantiate vyper deployer
        vyperDeployer = new VyperDeployer();
        _labelEthereumAddresses();
    }

    //// HELPERS ////

    /**
     * @dev Generates a user, labels its address, and funds it with test assets.
     * @param name The name of the user.
     * @return The address of the user.
     */
    function createUser(string memory name) public returns (address payable) {
        address payable user = payable(makeAddr(name));
        if (users[name] != address(0)) {
            console2.log("User ", name, " already exists");
            return user;
        }
        vm.deal({ account: user, newBalance: 100 ether });
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

    /// @notice Airdrop an asset to an address with a given amount
    /// @dev This function should only be used for ERC20s that have totalSupply storage slot
    /// @param _asset address of the asset to airdrop
    /// @param _to address to airdrop to
    /// @param _amount amount to airdrop
    function airdrop(IERC20 _asset, address _to, uint256 _amount, bool adjust) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount, adjust);
    }

    function airdrop(IERC20 _asset, address _to, uint256 _amount) public {
        airdrop(_asset, _to, _amount, true);
    }

    /// @notice Take an asset away from an address with a given amount
    /// @param _asset address of the asset to take away
    /// @param _from address to take away from
    /// @param _amount amount to take away
    function takeAway(IERC20 _asset, address _from, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_from);
        if (balanceBefore < _amount) {
            revert Errors.TakeAwayNotEnoughBalance();
        }
        deal(address(_asset), _from, balanceBefore - _amount);
    }

    function generateMockCurveSwapParams(
        address fromToken,
        address toToken
    )
        public
        pure
        returns (CurveRouterSwapper.CurveSwapParams memory)
    {
        CurveRouterSwapper.CurveSwapParams memory params;
        params.route[0] = fromToken;
        params.route[1] = address(1); // pool address is not needed
        params.route[2] = toToken;
        return params;
    }

    function _formatAccessControlError(address addr, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(addr),
            " is missing role ",
            Strings.toHexString(uint256(role), 32)
        );
    }

    function _deployVaultFactoryAt(address owner, address at) internal returns (address) {
        vm.startPrank(owner);
        address blueprint = vyperDeployer.deployBlueprint("lib/yearn-vaults-v3/contracts/", "VaultV3");
        bytes memory args = abi.encode("Vault V3 Factory 3.0.0", blueprint, owner);
        address factory = vyperDeployer.deployContract("lib/yearn-vaults-v3/contracts/", "VaultFactory", args);
        vm.etch(at, factory.code);
        vm.label(at, "VaultFactory");
        vm.stopPrank();
        return factory;
    }

    function _cloneContract(address implementation) internal returns (address) {
        return Clones.clone(implementation);
    }
}

// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { IMasterRegistry } from "./interfaces/IMasterRegistry.sol";
import { Errors } from "./libraries/Errors.sol";

/**
 * @title MasterRegistry
 * @notice This contract holds list of other registries or contracts and its historical versions.
 */
contract MasterRegistry is IMasterRegistry, AccessControlEnumerable, Multicall {
    /// @notice Role responsible for adding registries.
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");

    //slither-disable-next-line uninitialized-state
    mapping(bytes32 => address[]) private _registryMap;
    //slither-disable-next-line uninitialized-state
    mapping(address => ReverseRegistryData) private _reverseRegistry;

    /**
     * @notice Add a new registry entry to the master list.
     * @param name address of the added pool
     * @param registryAddress address of the registry
     * @param version version of the registry
     */
    event AddRegistry(bytes32 indexed name, address registryAddress, uint256 version);
    /**
     * @notice Update a current registry entry to the master list.
     * @param name address of the added pool
     * @param registryAddress address of the registry
     * @param version version of the registry
     */
    event UpdateRegistry(bytes32 indexed name, address registryAddress, uint256 version);

    // slither-disable-next-line locked-ether
    constructor(address admin, address manager) payable {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(_MANAGER_ROLE, admin);
        _grantRole(_MANAGER_ROLE, manager);
    }

    /// @inheritdoc IMasterRegistry
    function addRegistry(bytes32 registryName, address registryAddress) external override onlyRole(_MANAGER_ROLE) {
        // Check for empty values.
        if (registryName == 0) revert Errors.NameEmpty();
        if (registryAddress == address(0)) revert Errors.AddressEmpty();

        // Check that the registry name is not already in use.
        address[] storage registry = _registryMap[registryName];
        uint256 version = registry.length;
        if (version > 0) revert Errors.RegistryNameFound(registryName);
        if (_reverseRegistry[registryAddress].registryName != 0) {
            revert Errors.DuplicateRegistryAddress(registryAddress);
        }
        // Create an entry in the registry
        registry.push(registryAddress);
        _reverseRegistry[registryAddress] = ReverseRegistryData(registryName, version);

        emit AddRegistry(registryName, registryAddress, version);
    }

    /// @inheritdoc IMasterRegistry
    function updateRegistry(bytes32 registryName, address registryAddress) external override onlyRole(_MANAGER_ROLE) {
        // Check for empty values.
        if (registryName == 0) revert Errors.NameEmpty();
        if (registryAddress == address(0)) revert Errors.AddressEmpty();

        // Check that the registry name already exists in the registry.
        address[] storage registry = _registryMap[registryName];
        uint256 version = registry.length;
        if (version == 0) revert Errors.RegistryNameNotFound(registryName);
        if (_reverseRegistry[registryAddress].registryName != 0) {
            revert Errors.DuplicateRegistryAddress(registryAddress);
        }

        // Update the entry in the registry
        registry.push(registryAddress);
        _reverseRegistry[registryAddress] = ReverseRegistryData(registryName, version);

        emit UpdateRegistry(registryName, registryAddress, version);
    }

    /// @inheritdoc IMasterRegistry
    function resolveNameToLatestAddress(bytes32 registryName) external view override returns (address) {
        address[] storage registry = _registryMap[registryName];
        uint256 length = registry.length;
        if (length == 0) revert Errors.RegistryNameNotFound(registryName);
        return registry[length - 1];
    }

    /// @inheritdoc IMasterRegistry
    function resolveNameAndVersionToAddress(
        bytes32 registryName,
        uint256 version
    )
        external
        view
        override
        returns (address)
    {
        address[] storage registry = _registryMap[registryName];
        if (version >= registry.length) revert Errors.RegistryNameVersionNotFound(registryName, version);
        return registry[version];
    }

    /// @inheritdoc IMasterRegistry
    function resolveNameToAllAddresses(bytes32 registryName) external view override returns (address[] memory) {
        address[] storage registry = _registryMap[registryName];
        if (registry.length == 0) revert Errors.RegistryNameNotFound(registryName);
        return registry;
    }

    /// @inheritdoc IMasterRegistry
    function resolveAddressToRegistryData(address registryAddress)
        external
        view
        override
        returns (bytes32 registryName, uint256 version, bool isLatest)
    {
        ReverseRegistryData memory data = _reverseRegistry[registryAddress];
        if (data.registryName == 0) revert Errors.RegistryAddressNotFound(registryAddress);
        registryName = data.registryName;
        version = data.version;
        uint256 length = _registryMap[registryName].length;
        isLatest = version == length - 1;
    }
}

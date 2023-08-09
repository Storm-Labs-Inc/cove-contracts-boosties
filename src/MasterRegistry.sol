// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import { AccessControl } from "openzeppelin-contracts-v4.9.3/access/AccessControl.sol";
import { Multicall } from "openzeppelin-contracts-v4.9.3/utils/Multicall.sol";
import { IMasterRegistry } from "./interfaces/IMasterRegistry.sol";

/**
 * @title MasterRegistry
 * @notice This contract holds list of other registries or contracts and its historical versions.
 */
contract MasterRegistry is AccessControl, IMasterRegistry {
    /// @notice Role responsible for adding registries.
    bytes32 public constant PROTOCOL_MANAGER_ROLE = keccak256("PROTOCOL_MANAGER_ROLE");

    mapping(bytes32 => address[]) private _registryMap;
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

    /// @notice Thrown when the registry name given is empty.
    error NameEmpty();
    /// @notice Thrown when the registry address given is empty.
    error AddressEmpty();
    /// @notice Thrown when the caller is not the protocol manager.
    error CallerNotProtocolManager(address caller);
    /// @notice Thrown when the registry name is found when calling addRegistry().
    error RegistryNameFound(bytes32 name);
    /// @notice Thrown when the registry name is not found but is expected to be.
    error RegistryNameNotFound(bytes32 name);
    /// @notice Thrown when the registry address is not found but is expected to be.
    error RegistryAddressNotFound(address registryAddress);
    /// @notice Thrown when the registry name and version is not found but is expected to be.
    error RegistryNameVersionNotFound(bytes32 name, uint256 version);
    /// @notice Thrown when a duplicate registry address is found.
    error DuplicateRegistryAddress(address registryAddress);

    constructor(address admin) {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(PROTOCOL_MANAGER_ROLE, msg.sender);
    }

    /// @inheritdoc IMasterRegistry
    function addRegistry(bytes32 registryName, address registryAddress) external payable override {
        if (!hasRole(PROTOCOL_MANAGER_ROLE, msg.sender)) revert CallerNotProtocolManager(msg.sender);
        if (registryName == 0) revert NameEmpty();
        if (registryAddress == address(0)) revert AddressEmpty();

        address[] storage registry = _registryMap[registryName];
        uint256 version = registry.length;
        // This function should only be used to create a new registry entry.)
        if (version > 0) revert RegistryNameFound(registryName);
        registry.push(registryAddress);
        if (_reverseRegistry[registryAddress].name != 0) revert DuplicateRegistryAddress(registryAddress);
        _reverseRegistry[registryAddress] = ReverseRegistryData(registryName, version);

        emit AddRegistry(registryName, registryAddress, version);
    }

    /// @inheritdoc IMasterRegistry
    function updateRegistry(bytes32 registryName, address registryAddress) external payable override {
        if (!hasRole(PROTOCOL_MANAGER_ROLE, msg.sender)) revert CallerNotProtocolManager(msg.sender);
        if (registryName == 0) revert NameEmpty();
        if (registryAddress == address(0)) revert AddressEmpty();
        address[] storage registry = _registryMap[registryName];
        uint256 version = registry.length;
        // This function should only be used update an existing registry entry.
        if (version == 0) revert RegistryNameNotFound(registryName);
        registry.push(registryAddress);
        if (_reverseRegistry[registryAddress].name != 0) revert DuplicateRegistryAddress(registryAddress);
        _reverseRegistry[registryAddress] = ReverseRegistryData(registryName, version);

        emit UpdateRegistry(registryName, registryAddress, version);
    }

    /// @inheritdoc IMasterRegistry
    function resolveNameToLatestAddress(bytes32 name) external view override returns (address) {
        address[] storage registry = _registryMap[name];
        uint256 length = registry.length;
        if (length == 0) revert RegistryNameNotFound(name);
        return registry[length - 1];
    }

    /// @inheritdoc IMasterRegistry
    function resolveNameAndVersionToAddress(bytes32 name, uint256 version) external view override returns (address) {
        address[] storage registry = _registryMap[name];
        if (version >= registry.length) revert RegistryNameVersionNotFound(name, version);
        return registry[version];
    }

    /// @inheritdoc IMasterRegistry
    function resolveNameToAllAddresses(bytes32 name) external view override returns (address[] memory) {
        address[] storage registry = _registryMap[name];
        if (registry.length == 0) revert RegistryNameNotFound(name);
        return registry;
    }

    /// @inheritdoc IMasterRegistry
    function resolveAddressToRegistryData(address registryAddress)
        external
        view
        override
        returns (bytes32 name, uint256 version, bool isLatest)
    {
        ReverseRegistryData memory data = _reverseRegistry[registryAddress];
        if (data.name == 0) revert RegistryAddressNotFound(registryAddress);
        name = data.name;
        version = data.version;
        uint256 length = _registryMap[name].length;
        isLatest = version == length - 1;
    }
}

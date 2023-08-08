// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import { AccessControl } from "openzeppelin-contracts-v4.9.3/access/AccessControl.sol";
import { BaseBoringBatchable } from "./helper/BaseBoringBatchable.sol";
import { IMasterRegistry } from "./interfaces/IMasterRegistry.sol";

/**
 * @title MasterRegistry
 * @notice This contract holds list of other registries or contracts and its historical versions.
 */
contract MasterRegistry is AccessControl, IMasterRegistry, BaseBoringBatchable {
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
    event UpdateRegistry(bytes32 indexed name, address registryAddress, uint256 version);

    constructor(address admin) {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(PROTOCOL_MANAGER_ROLE, msg.sender);
    }

    /// @inheritdoc IMasterRegistry
    function addRegistry(bytes32 registryName, address registryAddress) external payable override {
        require(hasRole(PROTOCOL_MANAGER_ROLE, msg.sender), "MR: msg.sender is not allowed");
        require(registryName != 0, "MR: name cannot be empty");
        require(registryAddress != address(0), "MR: address cannot be empty");

        address[] storage registry = _registryMap[registryName];
        uint256 version = registry.length;
        // This function should only be used to create a new registry entry.
        require(version == 0, "MR: registry name found, please use updateRegistry");
        registry.push(registryAddress);
        require(_reverseRegistry[registryAddress].name == 0, "MR: duplicate registry address");
        _reverseRegistry[registryAddress] = ReverseRegistryData(registryName, version);

        emit AddRegistry(registryName, registryAddress, version);
    }

    /// @inheritdoc IMasterRegistry
    function updateRegistry(bytes32 registryName, address registryAddress) external payable override {
        require(hasRole(PROTOCOL_MANAGER_ROLE, msg.sender), "MR: msg.sender is not allowed");
        require(registryName != 0, "MR: name cannot be empty");
        require(registryAddress != address(0), "MR: address cannot be empty");
        address[] storage registry = _registryMap[registryName];
        uint256 version = registry.length;
        // This function should only be used update an existing registry entry.
        require(version > 0, "MR: registry entry does not exist, please use addRegistry");
        registry.push(registryAddress);
        require(_reverseRegistry[registryAddress].name == 0, "MR: duplicate registry address");
        _reverseRegistry[registryAddress] = ReverseRegistryData(registryName, version);

        emit UpdateRegistry(registryName, registryAddress, version);
    }

    /// @inheritdoc IMasterRegistry
    function resolveNameToLatestAddress(bytes32 name) external view override returns (address) {
        address[] storage registry = _registryMap[name];
        uint256 length = registry.length;
        require(length > 0, "MR: no match found for name");
        return registry[length - 1];
    }

    /// @inheritdoc IMasterRegistry
    function resolveNameAndVersionToAddress(bytes32 name, uint256 version) external view override returns (address) {
        address[] storage registry = _registryMap[name];
        require(version < registry.length, "MR: no match found for name and version");
        return registry[version];
    }

    /// @inheritdoc IMasterRegistry
    function resolveNameToAllAddresses(bytes32 name) external view override returns (address[] memory) {
        address[] storage registry = _registryMap[name];
        require(registry.length > 0, "MR: no match found for name");
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
        require(data.name != 0, "MR: no match found for address");
        name = data.name;
        version = data.version;
        uint256 length = _registryMap[name].length;
        isLatest = version == length - 1;
    }
}

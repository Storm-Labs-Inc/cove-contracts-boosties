// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { IBasketRegistry } from "./interfaces/IBasketRegistry.sol";
import { Errors } from "./libraries/Errors.sol";

/**
 * @title MasterRegistry
 * @notice This contract holds list of other registries or contracts and its historical versions.
 */
contract BasketRegistry is IBasketRegistry, AccessControl, Multicall {
    /// @notice Role responsible for adding registries.
    bytes32 public constant PROTOCOL_MANAGER_ROLE = keccak256("PROTOCOL_MANAGER_ROLE");

    //slither-disable-next-line uninitialized-state
    mapping(bytes32 => address[]) private _registryMap;
    //slither-disable-next-line uninitialized-state
    mapping(address => address[]) private _baseAssetToBasketsMap;
    //slither-disable-next-line uninitialized-state
    mapping(address => ReverseRegistryData) private _reverseRegistry;

    /**
     * @notice Add a new registry entry to the master list.
     * @param name address of the added pool
     * @param registryAddress address of the registry
     * @param version version of the registry
     */
    event AddBasket(bytes32 indexed name, address registryAddress, address baseAsset, uint256 version);
    /**
     * @notice Update a current registry entry to the master list.
     * @param name address of the added pool
     * @param registryAddress address of the registry
     * @param version version of the registry
     */
    event UpdateRegistry(bytes32 indexed name, address registryAddress, uint256 version);

    constructor(address admin) {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(PROTOCOL_MANAGER_ROLE, msg.sender);
    }

    /// @inheritdoc IBasketRegistry
    function addRegistry(
        bytes32 registryName,
        address registryAddress,
        address baseAsset
    )
        external
        override
        onlyRole(PROTOCOL_MANAGER_ROLE)
    {
        // Check for empty values.
        if (registryName == 0) revert Errors.NameEmpty();
        if (registryAddress == address(0)) revert Errors.AddressEmpty();
        if (baseAsset == address(0)) revert Errors.BaseAssetAddressEmpty();

        // Check that the registry name is not already in use.
        address[] storage registry = _registryMap[registryName];
        uint256 version = registry.length;
        if (version > 0) revert Errors.RegistryNameFound(registryName);
        if (_reverseRegistry[registryAddress].registryName != 0) {
            revert Errors.DuplicateRegistryAddress(registryAddress);
        }
        // TODO: Check that it is a valid basket contract and the base asset is correct.
        // Create an entry in the registry mappings.
        registry.push(registryAddress);
        address[] storage baseAssetToBaskets = _baseAssetToBasketsMap[baseAsset];
        baseAssetToBaskets.push(registryAddress);
        _reverseRegistry[registryAddress] = ReverseRegistryData(registryName, baseAsset, version);

        emit AddBasket(registryName, registryAddress, baseAsset, version);
    }

    /// @inheritdoc IBasketRegistry
    function updateRegistry(
        bytes32 registryName,
        address registryAddress,
        address baseAsset
    )
        external
        override
        onlyRole(PROTOCOL_MANAGER_ROLE)
    {
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

        // TODO: Check that it is a valid basket contract and that base asset is correct.
        // Update the entry in the registry
        registry.push(registryAddress);
        _reverseRegistry[registryAddress] = ReverseRegistryData(registryName, baseAsset, version);

        emit UpdateRegistry(registryName, registryAddress, version);
    }

    /// @inheritdoc IBasketRegistry
    function resolveNameToLatestAddress(bytes32 registryName) external view override returns (address) {
        address[] storage registry = _registryMap[registryName];
        uint256 length = registry.length;
        if (length == 0) revert Errors.RegistryNameNotFound(registryName);
        return registry[length - 1];
    }

    /// @inheritdoc IBasketRegistry
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

    /// @inheritdoc IBasketRegistry
    function resolveNameToAllAddresses(bytes32 registryName) external view override returns (address[] memory) {
        address[] storage registry = _registryMap[registryName];
        if (registry.length == 0) revert Errors.RegistryNameNotFound(registryName);
        return registry;
    }

    /// @inheritdoc IBasketRegistry
    function resolveAddressToRegistryData(address registryAddress)
        external
        view
        override
        returns (bytes32 registryName, address baseAsset, uint256 version, bool isLatest)
    {
        ReverseRegistryData memory data = _reverseRegistry[registryAddress];
        if (data.registryName == 0) revert Errors.RegistryAddressNotFound(registryAddress);
        registryName = data.registryName;
        version = data.version;
        baseAsset = data.baseAsset;
        uint256 length = _registryMap[registryName].length;
        isLatest = version == length - 1;
    }

    function resolveBaseAssetToBaskets(address baseAsset) external view override returns (address[] memory) {
        address[] storage baskets = _baseAssetToBasketsMap[baseAsset];
        if (baskets.length == 0) revert Errors.BaseAssetNotFound(baseAsset);
        return baskets;
    }
}

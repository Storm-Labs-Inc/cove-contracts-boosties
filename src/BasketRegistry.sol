// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import { AccessControl } from "openzeppelin-contracts-v4.9.3/access/AccessControl.sol";
import { BaseBoringBatchable } from "./helper/BaseBoringBatchable.sol";
import { IBasketRegistry } from "./interfaces/IBasketRegistry.sol";

contract BasketRegistry is AccessControl, IBasketRegistry, BaseBoringBatchable {
    /// @notice Role responsible for adding registries.
    bytes32 public constant PROTOCOL_MANAGER_ROLE = keccak256("PROTOCOL_MANAGER_ROLE");

    mapping(bytes32 => address[]) private _basketRegistryMap;
    mapping(address => address[]) private _baseAssetToBaskets;
    mapping(address => ReverseBasketRegistryData) private _reverseBasketRegistry;

    /**
     * @notice Add a new registry entry to the master list.
     * @param name address of the added pool
     * @param registryAddress address of the registry
     * @param version version of the registry
     */
    event AddRegistry(bytes32 indexed name, address registryAddress, uint256 version);

    constructor(address admin) {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(PROTOCOL_MANAGER_ROLE, msg.sender);
    }

    /// @inheritdoc IBasketRegistry
    function addBasket(bytes32 registryName, address registryAddress, address baseAsset) external payable override {
        require(hasRole(PROTOCOL_MANAGER_ROLE, msg.sender), "MR: msg.sender is not allowed");
        require(registryName != 0, "MR: name cannot be empty");
        require(registryAddress != address(0), "MR: address cannot be empty");
        require(baseAsset != address(0), "MR: baseAsset cannot be empty");
        address[] storage registry = _basketRegistryMap[registryName];
        uint256 version = registry.length;
        // TODO find a way to ensure baskets in this mapping are current
        address[] storage baseAssetBaskets = _baseAssetToBaskets[baseAsset];
        version == 0 ? baseAssetBaskets.push(registryAddress) : ();
        registry.push(registryAddress);
        require(_reverseBasketRegistry[registryAddress].name == 0, "MR: duplicate registry address");
        _reverseBasketRegistry[registryAddress] = ReverseBasketRegistryData(registryName, version, baseAsset);

        emit AddRegistry(registryName, registryAddress, version);
    }

    /// @inheritdoc IBasketRegistry
    function resolveNameToLatestAddress(bytes32 name) external view override returns (address) {
        address[] storage registry = _basketRegistryMap[name];
        uint256 length = registry.length;
        require(length > 0, "MR: no match found for name");
        return registry[length - 1];
    }

    /// @inheritdoc IBasketRegistry
    function resolveNameAndVersionToAddress(bytes32 name, uint256 version) external view override returns (address) {
        address[] storage registry = _basketRegistryMap[name];
        require(version < registry.length, "MR: no match found for name and version");
        return registry[version];
    }

    /// @inheritdoc IBasketRegistry
    function resolveNameToAllAddresses(bytes32 name) external view override returns (address[] memory) {
        address[] storage registry = _basketRegistryMap[name];
        require(registry.length > 0, "MR: no match found for name");
        return registry;
    }

    /// @inheritdoc IBasketRegistry
    function resolveAddressToRegistryData(address registryAddress)
        external
        view
        override
        returns (bytes32 name, uint256 version, address baseAsset, bool isLatest)
    {
        ReverseBasketRegistryData memory data = _reverseBasketRegistry[registryAddress];
        require(data.name != 0, "MR: no match found for address");
        name = data.name;
        version = data.version;
        baseAsset = data.baseAsset;
        uint256 length = _basketRegistryMap[name].length;
        require(length > 0, "MR: no version found for address");
        isLatest = version == length - 1;
    }

    /// @inheritdoc IBasketRegistry
    function resloveBaseAssetToBaskets(address baseAsset) external view override returns (address[] memory) {
        // Only include baskets that are current
        address[] storage baskets = _baseAssetToBaskets[baseAsset];
        uint256 length = baskets.length;
        address[] memory currentBaskets = new address[](length);
        uint256 currentBasketCount = 0;
        for (uint256 i = 0; i < length; i++) {
            ReverseBasketRegistryData memory data = _reverseBasketRegistry[baskets[i]];
            if (data.baseAsset == baseAsset) {
                currentBaskets[currentBasketCount] = baskets[i];
                currentBasketCount++;
            }
        }
        return currentBaskets;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.17;
pragma experimental ABIEncoderV2;

interface IBasketRegistry {
    /* Structs */

    struct ReverseBasketRegistryData {
        bytes32 name;
        uint256 version;
        address baseAsset;
    }

    /* Functions */

    /**
     * @notice Add a new basket entry to the master list.
     * @param basketName name for the basket
     * @param basketAddress address of the new basket
     * @param baseAsset address of the base asset of the basket
     */
    function addBasket(bytes32 basketName, address basketAddress, address baseAsset) external payable;

    /**
     * @notice Update a current basket entry to the master list.
     * @param basketName name for the basket
     * @param basketAddress address of the new basket
     * @param baseAsset address of the base asset of the basket
     */
    function updateBasket(bytes32 basketName, address basketAddress, address baseAsset) external payable;

    /**
     * @notice Resolves a name to the latest basket address. Reverts if no match is found.
     * @param name name for the basket
     * @return address address of the latest basket with the matching name
     */
    function resolveNameToLatestAddress(bytes32 name) external view returns (address);

    /**
     * @notice Resolves a name and version to an address. Reverts if there is no basket with given name and version.
     * @param name address of the basket you want to resolve to
     * @param version version of the basket you want to resolve to
     */
    function resolveNameAndVersionToAddress(bytes32 name, uint256 version) external view returns (address);

    /**
     * @notice Resolves a name to an array of all addresses. Reverts if no match is found.
     * @param name name for the basket
     * @return address address of the latest basket with the matching name
     */
    function resolveNameToAllAddresses(bytes32 name) external view returns (address[] memory);

    /**
     * @notice Resolves an address to basket entry data.
     * @param basketAddress address of a basket you want to resolve
     * @return name name of the resolved basket
     * @return version version of the resolved basket
     * @return baseAsset address of the base asset of the resolved basket
     * @return isLatest boolean flag of whether the given address is the latest version of the given registries with
     * matching name
     */
    function resolveAddressToRegistryData(address basketAddress)
        external
        view
        returns (bytes32 name, uint256 version, address baseAsset, bool isLatest);

    /**
     * @notice Resolves an address to basket entry data.
     * @param baseAsset address of a base asset you want to resolve
     * @return baskets array of baskets that contain the given base asset
     */
    function resolveBaseAssetToBaskets(address baseAsset) external view returns (address[] memory);
}

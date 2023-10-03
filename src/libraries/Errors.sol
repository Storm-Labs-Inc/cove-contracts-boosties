// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/// @title Errors
/// @notice Library containing all custom errors the protocol may revert with.
library Errors {
    //// MASTER REGISTRY ////

    /// @notice Thrown when the registry name given is empty.
    error NameEmpty();

    /// @notice Thrown when the registry address given is empty.
    error AddressEmpty();

    /// @notice Thrown when the registry name is found when calling addRegistry().
    error RegistryNameFound(bytes32 name);

    /// @notice Thrown when the registry name is not found but is expected to be.
    error RegistryNameNotFound(bytes32 name);

    /// @notice Thrown when the registry address is not found but is expected to be.
    error RegistryAddressNotFound(address registryAddress);

    /// @notice Thrown when the registry name and version is not found but is expected to be.
    error RegistryNameVersionNotFound(bytes32 name, uint256 version);

    /// @notice Thrown when the caller is not the protocol manager.
    error CallerNotProtocolManager(address caller);

    /// @notice Thrown when a duplicate registry address is found.
    error DuplicateRegistryAddress(address registryAddress);

    //// YEARN STAKING DELEGATE ////
    error ZeroAddress();

    error ZeroAmount();

    error InvalidSwapPath();

    error InvalidRewardSplit();

    error PerpetualLockEnabled();

    error NoAssociatedGauge();

    //// WRAPPED STRATEGY CURVE SWAPPER ////

    error OracleOudated();

    error VaultAssetDiffers();

    error VaultAssetDoesNotDiffer();

    error SlippageTooHigh();

    error OracleNotSet(address asset);

    error SlippageToleranceNotInRange(uint256 slippageTolerance);

    error TimeToleranceNotInRange(uint256 timeTolerance);

    error TokenNotFoundInPool(address token);

    /// CURVE ROUTER SWAPPER ///
    error InvalidFromToken(address intendedFromToken, address actualFromToken);
    error InvalidToToken(address intendedToToken, address actualToToken);
    error InvalidCoinIndex();
}

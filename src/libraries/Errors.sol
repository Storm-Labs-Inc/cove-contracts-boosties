// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

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

    error PerpetualLockDisabled();

    error SwapAndLockNotSet();

    error GetRewardFailed();
    error GaugeRewardsAlreadyAdded();
    error GaugeRewardsNotYetAdded();
    error CannotRescueUserTokens();
    error ExecutionNotAllowed();
    error ExecutionFailed();

    //// STAKING DELEGATE REWARDS ////
    error RescueNotAllowed();
    error PreviousRewardsPeriodNotCompleted();
    error OnlyStakingDelegateCanUpdateUserBalance();
    error OnlyStakingDelegateCanAddStakingToken();
    error OnlyRewardDistributorCanNotifyRewardAmount();
    error StakingTokenAlreadyAdded();
    error StakingTokenNotAdded();
    error RewardRateTooLow();
    error RewardDurationCannotBeZero();

    //// WRAPPED STRATEGY CURVE SWAPPER ////
    error OracleOutdated();

    error VaultAssetDiffers();

    error VaultAssetDoesNotDiffer();

    error AssetDoesNotMatchStrategyAsset();

    error SlippageTooHigh();

    error OracleNotSet(address asset);

    error SlippageToleranceNotInRange(uint128 slippageTolerance);

    error TimeToleranceNotInRange(uint128 timeTolerance);

    error TokenNotFoundInPool(address token);
    error InvalidTokensReceived();
    error InsufficientFlashLoanPayment();
    error FlashLoanProviderNotSet();

    /// CURVE TWO ASSET POOL YEARN GAUGE STRATEGY ///
    error InvalidDepositToken();

    /// CURVE ROUTER SWAPPER ///
    error InvalidFromToken(address intendedFromToken, address actualFromToken);
    error InvalidToToken(address intendedToToken, address actualToToken);
    error ExpectedAmountZero();
    error InvalidSwapParams();

    /// SWAP AND LOCK ///
    error SameAddress();

    //// COVEYFI ////

    error OnlyMintingEnabled();

    /// RESCUABLE ///

    error ZeroEthTransfer();
    error EthTransferFailed();
    error ZeroTokenTransfer();

    /// GAUGEREWARDRECEIVER ///

    error NotAuthorized();
    error CannotRescueRewardToken();

    /// DYFI REDEEMER ///
    error InvalidArrayLength();
    error PriceFeedOutdated();
    error PriceFeedIncorrectRound();
    error PriceFeedReturnedZeroPrice();
    error InsufficientYfiBalance();
    error NoDYfiToRedeem();

    /// TESTING ///

    error TakeAwayNotEnoughBalance();
    error StrategyNotAddedToVault();
    error QueueNewRewardsFailed();
    error SetAssociatedGaugeFailed();
}

// SPDX-License-Identifier: BUSL-1.1
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

    /// @notice Thrown when a duplicate registry address is found.
    error DuplicateRegistryAddress(address registryAddress);

    //// YEARN STAKING DELEGATE ////

    /// @notice Error for when an address is zero which is not allowed.
    error ZeroAddress();

    /// @notice Error for when an amount is zero which is not allowed.
    error ZeroAmount();

    /// @notice Error for when a reward split is invalid.
    error InvalidRewardSplit();

    /// @notice Error for when the treasury percentage is too high.
    error TreasuryPctTooHigh();

    /// @notice Error for when perpetual lock is enabled and an action cannot be taken.
    error PerpetualLockEnabled();

    /// @notice Error for when perpetual lock is disabled and an action cannot be taken.
    error PerpetualLockDisabled();

    /// @notice Error for when swap and lock settings are not set.
    error SwapAndLockNotSet();

    /// @notice Error for when gauge rewards have already been added.
    error GaugeRewardsAlreadyAdded();

    /// @notice Error for when gauge rewards have not yet been added.
    error GaugeRewardsNotYetAdded();

    /// @notice Error for when execution of an action is not allowed.
    error ExecutionNotAllowed();

    /// @notice Error for when execution of an action has failed.
    error ExecutionFailed();

    /// @notice Error for when Cove YFI reward forwarder is not set.
    error CoveYfiRewardForwarderNotSet();

    //// STAKING DELEGATE REWARDS ////

    /// @notice Error for when a rescue operation is not allowed.
    error RescueNotAllowed();

    /// @notice Error for when the previous rewards period has not been completed.
    error PreviousRewardsPeriodNotCompleted();

    /// @notice Error for when only the staking delegate can update a user's balance.
    error OnlyStakingDelegateCanUpdateUserBalance();

    /// @notice Error for when only the staking delegate can add a staking token.
    error OnlyStakingDelegateCanAddStakingToken();

    /// @notice Error for when only the reward distributor can notify the reward amount.
    error OnlyRewardDistributorCanNotifyRewardAmount();

    /// @notice Error for when a staking token has already been added.
    error StakingTokenAlreadyAdded();

    /// @notice Error for when a staking token has not been added.
    error StakingTokenNotAdded();

    /// @notice Error for when the reward rate is too low.
    error RewardRateTooLow();

    /// @notice Error for when the reward duration cannot be zero.
    error RewardDurationCannotBeZero();

    //// WRAPPED STRATEGY CURVE SWAPPER ////

    /// @notice Error for when slippage is too high.
    error SlippageTooHigh();

    /// @notice Error for when invalid tokens are received.
    error InvalidTokensReceived();

    /// CURVE ROUTER SWAPPER ///

    /*
     * @notice Error for when the from token is invalid.
     * @param intendedFromToken The intended from token address.
     * @param actualFromToken The actual from token address received.
     */
    error InvalidFromToken(address intendedFromToken, address actualFromToken);

    /*
     * @notice Error for when the to token is invalid.
     * @param intendedToToken The intended to token address.
     * @param actualToToken The actual to token address received.
     */
    error InvalidToToken(address intendedToToken, address actualToToken);

    /// @notice Error for when the expected amount is zero.
    error ExpectedAmountZero();

    /// @notice Error for when swap parameters are invalid.
    error InvalidSwapParams();

    /// SWAP AND LOCK ///

    /// @notice Error for when the same address is used in a context where it is not allowed.
    error SameAddress();

    //// COVEYFI ////

    /// @notice Error for when only minting is enabled.
    error OnlyMintingEnabled();

    /// RESCUABLE ///

    /// @notice Error for when an ETH transfer of zero is attempted.
    error ZeroEthTransfer();

    /// @notice Error for when an ETH transfer fails.
    error EthTransferFailed();

    /// @notice Error for when a token transfer of zero is attempted.
    error ZeroTokenTransfer();

    /// GAUGE REWARD RECEIVER ///

    /// @notice Error for when an action is not authorized.
    error NotAuthorized();

    /// @notice Error for when rescuing a reward token is not allowed.
    error CannotRescueRewardToken();

    /// DYFI REDEEMER ///

    /// @notice Error for when an array length is invalid.
    error InvalidArrayLength();

    /// @notice Error for when a price feed is outdated.
    error PriceFeedOutdated();

    /// @notice Error for when a price feed round is incorrect.
    error PriceFeedIncorrectRound();

    /// @notice Error for when a price feed returns a zero price.
    error PriceFeedReturnedZeroPrice();

    /// @notice Error for when there is no DYFI to redeem.
    error NoDYfiToRedeem();

    /// @notice Error for when an ETH transfer for caller reward fails.
    error CallerRewardEthTransferFailed();

    /// COVE YEARN GAUGE FACTORY ///

    /// @notice Error for when a gauge has already been deployed.
    error GaugeAlreadyDeployed();

    /// @notice Error for when a gauge has not been deployed.
    error GaugeNotDeployed();

    /// MINICHEF V3 ////

    /// @notice Error for when an LP token is invalid.
    error InvalidLPToken();

    /// @notice Error for when an LP token has not been added.
    error LPTokenNotAdded();

    /// @notice Error for when an LP token does not match the pool ID.
    error LPTokenDoesNotMatchPoolId();

    /// @notice Error for when there is an insufficient balance.
    error InsufficientBalance();

    /// @notice Error for when an LP token has already been added.
    error LPTokenAlreadyAdded();

    /// @notice Error for when the reward rate is too high.
    error RewardRateTooHigh();

    /// Yearn4626RouterExt ///

    /// @notice Error for when there are insufficient shares.
    error InsufficientShares();

    /// @notice Error for when the 'to' address is invalid.
    error InvalidTo();

    /// @notice Error esure the has enough remaining gas.
    error InsufficientGas();

    /// TESTING ///

    /// @notice Error for when there is not enough balance to take away.
    error TakeAwayNotEnoughBalance();

    /// @notice Error for when a strategy has not been added to a vault.
    error StrategyNotAddedToVault();

    /// COVE TOKEN ///

    /// @notice Error for when a transfer is attempted before it is allowed.
    error TransferNotAllowedYet();

    /// @notice Error for when an address is being added as both a sender and a receiver.
    error CannotBeBothSenderAndReceiver();

    /// @notice Error for when an unpause is attempted too early.
    error UnpauseTooEarly();

    /// @notice Error for when the pause period is too long.
    error PausePeriodTooLong();

    /// @notice Error for when minting is attempted too early.
    error MintingAllowedTooEarly();

    /// @notice Error for when the mint amount exceeds the cap.
    error InflationTooLarge();

    /*
     * @notice Error for when an unauthorized account attempts an action requiring a specific role.
     * @param account The account attempting the unauthorized action.
     * @param neededRole The role required for the action.
     */
    error AccessControlEnumerableUnauthorizedAccount(address account, bytes32 neededRole);

    /// @notice Error for when an action is unauthorized.
    error Unauthorized();

    /// @notice Error for when a pause is expected but not enacted.
    error ExpectedPause();

    /// COVE YEARN GAUGE FACTORY ///

    /// @notice Error for when an address is not a contract.
    error AddressNotContract();
}

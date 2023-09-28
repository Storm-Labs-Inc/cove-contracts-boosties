// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IBaseTokenizedStrategy } from "src/interfaces/deps/yearn/tokenized-strategy/IBaseTokenizedStrategy.sol";
import { ITokenizedStrategy, IERC4626 } from "src/interfaces/deps/yearn/tokenized-strategy/ITokenizedStrategy.sol";

interface IWrappedYearnV3Strategy is IBaseTokenizedStrategy, ITokenizedStrategy {
    // Need to override the `asset` function since
    // its defined in both interfaces inherited.
    function asset() external view override(IBaseTokenizedStrategy, IERC4626) returns (address);

    function setYieldSource(address v3VaultAddress) external;

    function setStakingDelegate(address yearnStakingDelegateAddress) external;

    function setOracle(address token, address oracle) external;

    function setSwapParameters(uint256 slippageTolerance, uint256 timeTolerance) external;

    function vaultAddress() external view returns (address);

    function yearnStakingDelegateAddress() external view returns (address);
}

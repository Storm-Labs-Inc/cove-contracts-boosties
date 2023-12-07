// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// @dev YearnVaultV2 does not follow ERC4626 interface for `asset()` instead it uses `token()`
interface IYearnVaultV2 {
    function token() external view returns (address);
}

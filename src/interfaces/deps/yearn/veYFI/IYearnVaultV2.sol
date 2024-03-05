// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// @dev YearnVaultV2 does not follow ERC4626 interface for `asset()` instead it uses `token()`
interface IYearnVaultV2 {
    function token() external view returns (address);
    function deposit(uint256 _amount, address _recipient) external returns (uint256 shares);
    function deposit(uint256 _amount) external returns (uint256 shares);
    function pricePerShare() external view returns (uint256);
}

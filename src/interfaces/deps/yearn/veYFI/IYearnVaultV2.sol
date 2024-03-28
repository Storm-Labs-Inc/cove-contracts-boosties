// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// @dev YearnVaultV2 does not follow ERC4626 interface for `asset()` instead it uses `token()`
interface IYearnVaultV2 {
    function token() external view returns (address);
    function deposit(uint256 amount, address recipient) external returns (uint256 shares);
    function deposit(uint256 amount) external returns (uint256 shares);
    function withdraw(uint256 shares, address recipient) external returns (uint256 amount);
    function pricePerShare() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function lastReport() external view returns (uint256);
    function lockedProfitDegradation() external view returns (uint256);
    function lockedProfit() external view returns (uint256);
}

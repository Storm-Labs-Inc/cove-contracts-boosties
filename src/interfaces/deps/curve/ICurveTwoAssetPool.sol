// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ICurveTwoAssetPool {
    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 minMintAmount,
        bool useEth,
        address receiver
    )
        external
        returns (uint256);

    function add_liquidity(uint256[2] calldata amounts, uint256 minMintAmount) external returns (uint256);
    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256 dy);
    // solhint-disable func-param-name-mixedcase,var-name-mixedcase
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external payable returns (uint256 dy);
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy,
        bool useEth
    )
        external
        payable
        returns (uint256 dy);
    function coins(uint256 arg0) external view returns (address);
    function price_oracle() external view returns (uint256);
}

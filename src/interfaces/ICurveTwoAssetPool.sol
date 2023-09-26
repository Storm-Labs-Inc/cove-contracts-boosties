// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256 dy);
    // solhint-disable-next-line func-param-name-mixedcase,var-name-mixedcase
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function coins(uint256 arg0) external view returns (address);
}

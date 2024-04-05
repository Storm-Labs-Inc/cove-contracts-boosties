// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGasliteDrop {
    function airdropERC20(
        address _token,
        address[] calldata _addresses,
        uint256[] calldata _amounts,
        uint256 _totalAmount
    )
        external
        payable;
}

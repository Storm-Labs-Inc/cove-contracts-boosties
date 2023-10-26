// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ICurveFactory {
    function deploy_pool(
        string calldata name,
        string calldata symbol,
        address[2] calldata coins,
        uint256 a,
        uint256 gamma,
        uint256 midFee,
        uint256 outFee,
        uint256 allowedExtraProfit,
        uint256 feeGamma,
        uint256 adjustmentStep,
        uint256 adminFee,
        uint256 maHalfTime,
        uint256 initialPrice
    )
        external
        returns (address);
}

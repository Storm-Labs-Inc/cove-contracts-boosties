// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { IFlashLoanRecipient } from "src/interfaces/deps/balancer/IFlashLoanRecipient.sol";
import { IAccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

interface IDYFIRedeemer is IFlashLoanRecipient, IAccessControlEnumerable {
    function slippage() external view returns (uint256);
    function getLatestPrice() external view returns (uint256);
    function minYfiRedeem(uint256 dYfiAmount) external view returns (uint256);
    function currentYfiRedeem(uint256 dYfiAmount) external view returns (uint256);
    function expectedMassRedeemReward(uint256 dYfiAmount) external view returns (uint256);
    function massRedeem(address[] calldata accounts, uint256[] calldata dYfiAmounts) external;
    function setSlippage(uint256 slippage_) external;
}

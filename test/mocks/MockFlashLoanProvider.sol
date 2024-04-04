// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFlashLoanRecipient } from "src/interfaces/deps/balancer/IFlashLoanRecipient.sol";
import { IFlashLoanProvider } from "src/interfaces/deps/balancer/IFlashLoanProvider.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Constants } from "test/utils/Constants.sol";

contract MockFlashLoanProvider is IFlashLoanProvider, StdCheats, Constants {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    )
        external
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            deal(address(tokens[i]), address(this), amounts[i], false);
            if (tokens[i] == IERC20(MAINNET_WETH)) {
                vm.deal({ account: MAINNET_WETH, newBalance: amounts[i] });
            }
            tokens[i].transfer(address(recipient), amounts[i]);
        }
        uint256[] memory fees = new uint256[](tokens.length);
        recipient.receiveFlashLoan(tokens, amounts, fees, userData);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = tokens[i].balanceOf(address(this));
            require(balance == amounts[i] + fees[i], "FlashLoanProvider: insufficient fee");
        }
    }
}

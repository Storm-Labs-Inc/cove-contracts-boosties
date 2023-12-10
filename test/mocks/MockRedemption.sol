// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRedemption } from "src/interfaces/deps/yearn/veYFI/IRedemption.sol";
import { Constants } from "test/utils/Constants.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract MockRedemption is IRedemption, StdCheats, Constants {
    function redeem(uint256 dYfiAmount) external payable returns (uint256) {
        uint256 ethRequired = IRedemption(this).eth_required(dYfiAmount);
        IERC20(MAINNET_DYFI).transferFrom(msg.sender, address(this), dYfiAmount);
        require(msg.value == ethRequired, "MockRedemption: incorrect ETH amount");
        deal(MAINNET_YFI, address(this), dYfiAmount, true);
        IERC20(MAINNET_YFI).transfer(msg.sender, dYfiAmount);
        return dYfiAmount;
    }

    function eth_required(uint256) external view returns (uint256) {
        // use vm.mockCall to mock the return value in tests
        return 1e18;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { CommonBase } from "forge-std/Base.sol";

contract MockCurveTwoAssetPool is CommonBase, StdCheats {
    address[2] public coins;
    address private constant _WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setCoins(address[2] memory coins_) external {
        coins = coins_;
    }

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minOut,
        bool useEth
    )
        external
        payable
        returns (uint256 dy)
    {
        if (coins[i] == _WETH && useEth) {
            require(msg.value == dx, "MockCurveTwoAssetPool: incorrect ETH amount");
        } else {
            IERC20(coins[i]).transferFrom(msg.sender, address(this), dx);
        }
        if (coins[j] == _WETH && useEth) {
            vm.deal({ account: address(this), newBalance: minOut });
            payable(msg.sender).transfer(minOut);
        } else {
            deal(coins[j], address(this), minOut, true);
            IERC20(coins[j]).transfer(msg.sender, minOut);
        }
        return minOut;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { ERC20Pausable } from "@openzeppelin-5.0/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import { Math } from "@openzeppelin-5.0/contracts/utils/math/Math.sol";
import { Ownable } from "@openzeppelin-5.0/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract CoveYFI is ERC20Pausable, Ownable {
    using SafeERC20 for IERC20;

    constructor() ERC20("Cove YFI", "coveYFI") Ownable(msg.sender) { }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /// @notice Rescue any ERC20 tokens that are stuck in this contract
    /// @dev Only callable by owner
    /// @param token address of the ERC20 token to rescue. Use zero address for ETH
    /// @param to address to send the tokens to
    /// @param balance amount of tokens to rescue. Use zero to rescue all
    function rescue(IERC20 token, address to, uint256 balance) external onlyOwner {
        if (address(token) == address(0)) {
            // for Ether
            uint256 totalBalance = address(this).balance;
            balance = balance == 0 ? totalBalance : Math.min(totalBalance, balance);
            require(balance > 0, "trying to send 0 ETH");
            // slither-disable-next-line arbitrary-send
            (bool success,) = to.call{ value: balance }("");
            require(success, "ETH transfer failed");
        } else {
            // any other erc20
            uint256 totalBalance = token.balanceOf(address(this));
            balance = balance == 0 ? totalBalance : Math.min(totalBalance, balance);
            require(balance > 0, "trying to send 0 balance");
            token.safeTransfer(to, balance);
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/ERC20.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Math } from "@openzeppelin-5.0/contracts/utils/math/Math.sol";
import { Ownable } from "@openzeppelin-5.0/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin-5.0/contracts/utils/Pausable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin-5.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract CoveYFI is ERC20, Pausable, Ownable {
    // Libraries
    using SafeERC20 for IERC20;

    // Immutable storage variables
    address public immutable yfi;
    address public immutable yearnStakingDelegate;

    constructor(address _yfi, address _yearnStakingDelegate) ERC20("Cove YFI", "coveYFI") Ownable(msg.sender) {
        // Checks
        // check for zero addresses
        if (_yfi == address(0) || _yearnStakingDelegate == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // set storage variables
        yfi = _yfi;
        yearnStakingDelegate = _yearnStakingDelegate;

        // Interactions
        // max approve YFI for the yearn staking delegate
        IERC20(_yfi).approve(_yearnStakingDelegate, type(uint256).max);
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        // only allow minting by allowing transfers from the 0x0 address
        if (paused() && from != address(0x0)) {
            revert Errors.OnlyMintingEnabled();
        }
        super._update(from, to, value);
    }

    function deposit(uint256 balance) public {
        address sender = _msgSender();

        // Checks
        if (balance == 0) {
            revert Errors.ZeroAmount();
        }

        // Effects
        _mint(sender, balance);

        // Interactions
        IERC20(yfi).safeTransferFrom(sender, address(this), balance);
        IYearnStakingDelegate(yearnStakingDelegate).lockYfi(balance);
    }

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

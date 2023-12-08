// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { Rescuable } from "src/Rescuable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CoveYFI
 * @notice CoveYFI is a tokenized version of veYFI, commonly referred to as a liquid locker.
 * @dev Extends the ERC-20 standard with permit, pausable, ownable, and rescuable functionality.
 */
contract CoveYFI is ERC20Permit, Pausable, Ownable, Rescuable {
    // Libraries
    using SafeERC20 for IERC20;

    // Immutable storage variables
    // slither-disable-start naming-convention
    address internal immutable _YFI;
    address internal immutable _YEARN_STAKING_DELEGATE;
    // slither-disable-end naming-convention

    /**
     * @param _yfi The address of the YFI token contract.
     * @param _yearnStakingDelegate The address of the YearnStakingDelegate contract.
     */
    constructor(
        address _yfi,
        address _yearnStakingDelegate
    )
        ERC20("Cove YFI", "coveYFI")
        ERC20Permit("Cove YFI")
        Ownable()
    {
        // Checks
        // Check for zero addresses
        if (_yfi == address(0) || _yearnStakingDelegate == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // Set storage variables
        _YFI = _yfi;
        _YEARN_STAKING_DELEGATE = _yearnStakingDelegate;

        // Interactions
        // Max approve YFI for the yearn staking delegate
        IERC20(_yfi).forceApprove(_yearnStakingDelegate, type(uint256).max);
    }

    /**
     * @notice Hook that is called before any transfer of tokens including minting and burning.
     * @dev Overridden to restrict transfers while the contract is paused, except for minting.
     * @param from The address the tokens are being transferred from.
     * @param to The address the tokens are being transferred to.
     * @param value The amount of tokens being transferred.
     */
    function _beforeTokenTransfer(address from, address to, uint256 value) internal virtual override {
        // Only allow minting by allowing transfers from the 0x0 address
        if (paused() && from != address(0x0)) {
            revert Errors.OnlyMintingEnabled();
        }
        super._beforeTokenTransfer(from, to, value);
    }

    /**
     * @notice Deposits YFI tokens into the YearnStakingDelegate contract and mints coveYFI tokens to the sender.
     * @dev Mints coveYFI tokens equivalent to the amount of YFI deposited. The deposited YFI is then staked.
     *      Reverts with `Errors.ZeroAmount` if the deposit amount is zero.
     *      Emits a `Transfer` event from the zero address to the sender, indicating minting of coveYFI tokens.
     * @param balance The amount of YFI tokens to deposit and stake. Must be greater than zero to succeed.
     */
    function deposit(uint256 balance) public {
        address sender = _msgSender();

        // Checks
        if (balance == 0) {
            revert Errors.ZeroAmount();
        }

        // Effects
        _mint(sender, balance);

        // Interactions
        IERC20(_YFI).safeTransferFrom(sender, address(this), balance);
        // lockYfi ultimately calls modify_lock which returns a struct with unnecessary balance information
        // Ref: https://github.com/yearn/veYFI/blob/master/contracts/VotingYFI.vy#L300
        // slither-disable-next-line unused-return
        IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).lockYfi(balance);
    }

    /**
     * @notice Pauses all token transfers, mints, and burns within the contract.
     * @dev Can only be called by the contract owner. Emits a Paused event.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers, mints, and burns within the contract.
     * @dev Can only be called by the contract owner. Emits an Unpaused event.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice Allows the owner to rescue tokens mistakenly sent to the contract.
     * @dev Can only be called by the contract owner. This function is intended for use in case of accidental token
     * transfers into the contract.
     * @param token The ERC20 token to rescue, or 0x0 for ETH.
     * @param to The recipient address of the rescued tokens.
     * @param balance The amount of tokens to rescue.
     */
    function rescue(IERC20 token, address to, uint256 balance) external onlyOwner {
        _rescue(token, to, balance);
    }

    /**
     * @notice Returns the address of the YFI token contract.
     * @dev Provides a way to access the YFI token address used by the contract.
     * @return The address of the YFI token contract.
     */
    function yfi() external view returns (address) {
        return _YFI;
    }

    /**
     * @notice Returns the address of the YearnStakingDelegate contract.
     * @dev Provides a way to access the YearnStakingDelegate address used by the contract.
     * @return The address of the YearnStakingDelegate contract.
     */
    function yearnStakingDelegate() external view returns (address) {
        return _YEARN_STAKING_DELEGATE;
    }
}

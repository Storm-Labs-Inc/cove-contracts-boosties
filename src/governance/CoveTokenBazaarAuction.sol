// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { Errors } from "src/libraries/Errors.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CoveTokenBazaarAuction
 * @notice ERC20 token with capped supply and owner controlled allowlisting mechanism for transfers.
 * @dev Intended usage of the allowlisting mechanism is:
 * - Senders: Bazaar Uncapped Auction Factory for creating the auction, Bazaar Uncapped Auction for users to claim
 * tokens
 * - Receivers: None
 * It inherits from OpenZeppelin's ERC20 and Ownable contracts.
 */
contract CoveTokenBazaarAuction is ERC20, Ownable {
    /// @notice Mapping to track addresses allowed to receive transfers.
    mapping(address => bool) public allowedReceiver;
    /// @notice Mapping to track addresses allowed to initiate transfers.
    mapping(address => bool) public allowedSender;
    /// @notice State variable to make the events orderable for external observers if they are called in the same block.
    uint256 private _eventId;
    /// @notice Total supply of the token.
    uint256 private constant _TOTAL_SUPPLY = 95_000_000 ether;
    /// @notice Address of the Bazaar Uncapped Auction Factory contract.
    /// https://etherscan.io/address/0x47612eabFbE65329AeD1ab1BF3FCbAE493aEf460
    address private constant _BAZAAR_UNCAPPED_AUCTION_FACTORY = 0x47612eabFbE65329AeD1ab1BF3FCbAE493aEf460;

    /**
     * @notice Emitted when an address is granted permission to initiate transfers.
     * @param target The address that is being allowed to send tokens.
     * @param eventId An identifier for the event to order events within the same block.
     */
    event SenderAllowed(address indexed target, uint256 eventId);
    /**
     * @notice Emitted when an address has its permission to initiate transfers revoked.
     * @param target The address that is being disallowed from sending tokens.
     * @param eventId An identifier for the event to order events within the same block.
     */
    event SenderDisallowed(address indexed target, uint256 eventId);
    /**
     * @notice Emitted when an address is granted permission to receive transfers.
     * @param target The address that is being allowed to receive tokens.
     * @param eventId An identifier for the event to order events within the same block.
     */
    event ReceiverAllowed(address indexed target, uint256 eventId);
    /**
     * @notice Emitted when an address has its permission to receive transfers revoked.
     * @param target The address that is being disallowed from receiving tokens.
     * @param eventId An identifier for the event to order events within the same block.
     */
    event ReceiverDisallowed(address indexed target, uint256 eventId);

    /**
     * @notice Deploys this contract with the initial owner and minting the total supply to the owner.
     * @param owner_ The address of the initial owner.
     */
    constructor(address owner_) payable Ownable() ERC20("Cove DAO Bazaar Auction Token", "COVE-BAZAAR") {
        // Checks
        if (owner_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        _transferOwnership(owner_);
        _addToAllowedSender(address(0)); // Allow minting
        _addToAllowedSender(owner_); // Allow transfers from owner for distribution
        _addToAllowedSender(_BAZAAR_UNCAPPED_AUCTION_FACTORY); // Allow transfers from Bazaar Uncapped Auction Factory
        _mint(owner_, _TOTAL_SUPPLY); // Mint total supply to owner
    }

    /**
     * @notice Adds an address to the list of allowed transferees.
     * @param target The address to allow.
     */
    function addAllowedReceiver(address target) external onlyOwner {
        _addToAllowedReceiver(target);
    }

    /**
     * @notice Removes an address from the list of allowed transferees.
     * @param target The address to disallow.
     */
    function removeAllowedReceiver(address target) external onlyOwner {
        _removeFromAllowedReceiver(target);
    }

    /**
     * @notice Adds an address to the list of allowed transferrers.
     * @param target The address to allow.
     */
    function addAllowedSender(address target) external onlyOwner {
        _addToAllowedSender(target);
    }

    /**
     * @notice Removes an address from the list of allowed transferrers.
     * @param target The address to disallow.
     */
    function removeAllowedSender(address target) external onlyOwner {
        _removeFromAllowedSender(target);
    }

    function _addToAllowedReceiver(address target) internal {
        if (allowedSender[target]) {
            revert Errors.CannotBeBothSenderAndReceiver();
        }
        allowedReceiver[target] = true;
        emit ReceiverAllowed(target, _eventId);
        ++_eventId;
    }

    function _removeFromAllowedReceiver(address target) internal {
        allowedReceiver[target] = false;
        emit ReceiverDisallowed(target, _eventId);
        ++_eventId;
    }

    function _addToAllowedSender(address target) internal {
        if (allowedReceiver[target]) {
            revert Errors.CannotBeBothSenderAndReceiver();
        }
        allowedSender[target] = true;
        emit SenderAllowed(target, _eventId);
        ++_eventId;
    }

    function _removeFromAllowedSender(address target) internal {
        allowedSender[target] = false;
        emit SenderDisallowed(target, _eventId);
        ++_eventId;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes minting and burning.
     *      It checks if the contract is paused and if so, only allows transfers from allowed transferrers
     *      or to allowed transferees (only one inclusion is required).  This is meant to support:
     *      - Allowed senders: Bazaar Uncapped Auction Factory, Bazaar Uncapped Auction
     *      - Allowed receivers: None
     * @param from The address which is transferring tokens.
     * @param to The address which is receiving tokens.
     * @param amount The amount of tokens being transferred.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Check if the transfer is allowed
        // Only allowed transferrers can transfer or only allowed transferees can receive
        if (!allowedSender[from]) {
            if (!allowedReceiver[to]) {
                revert Errors.TransferNotAllowedYet();
            }
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC20Permit, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { Errors } from "src/libraries/Errors.sol";

/**
 * @title CoveToken
 * @notice ERC20 token with governance features including roles, pausability, and permit functionality.
 * @dev This token includes roles for minting and pausing, as well as the ability to set transfer allowances via
 * signatures.
 * It inherits from OpenZeppelin's ERC20, ERC20Permit, AccessControl, Pausable, and Multicall contracts.
 */
contract CoveToken is ERC20Permit, AccessControl, Pausable, Multicall {
    /// @dev Initial supply of tokens.
    uint256 private constant _INITIAL_SUPPLY = 1_000_000_000 ether;
    /// @dev Minimum time interval between mints.
    uint256 private constant _MIN_MINT_INTERVAL = 365 days;
    /// @dev Numerator for calculating mint cap.
    uint256 private constant _MINT_CAP_NUMERATOR = 600;
    /// @dev Denominator for calculating mint cap.
    uint256 private constant _MINT_CAP_DENOMINATOR = 10_000;
    /// @dev Maximum period the contract can be paused.
    uint256 private constant _MAX_PAUSE_PERIOD = 18 * 4 weeks;
    /// @dev Period after which the owner can unpause the contract.
    uint256 private constant _OWNER_PAUSE_PERIOD = 6 * 4 weeks;
    /// @dev Role identifier for minters.
    bytes32 private constant _MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Timestamp after which minting is allowed.
    uint256 public mintingAllowedAfter;

    // slither-disable-start naming-convention
    /// @notice Timestamp after which the owner can unpause the contract.
    uint256 public immutable OWNER_CAN_UNPAUSE_AFTER;
    /// @notice Timestamp after which anyone can unpause the contract.
    uint256 public immutable ANYONE_CAN_UNPAUSE_AFTER;
    // slither-disable-end naming-convention

    /// @notice Mapping to track addresses allowed to receive transfers.
    mapping(address => bool) public allowedTransferee;
    /// @notice Mapping to track addresses allowed to initiate transfers.
    mapping(address => bool) public allowedTransferrer;
    /// @notice State variable to make the events orderable for external observers if they are called in the same block.
    uint256 private _eventId;

    /// @dev Emitted when a transferrer is allowed.
    event TransferrerAllowed(address indexed target, uint256 eventId);
    /// @dev Emitted when a transferrer is disallowed.
    event TransferrerDisallowed(address indexed target, uint256 eventId);
    /// @dev Emitted when a transferee is allowed.
    event TransfereeAllowed(address indexed target, uint256 eventId);
    /// @dev Emitted when a transferee is disallowed.
    event TransfereeDisallowed(address indexed target, uint256 eventId);

    /**
     * @notice Deploys this contract with the initial owner and minting allowed after a specified time.
     * @dev The contract is paused upon deployment and the initial supply is minted to the owner.
     * @param owner_ The address of the initial owner.
     * @param mintingAllowedAfter_ The timestamp after which minting is allowed.
     */
    constructor(
        address owner_,
        uint256 mintingAllowedAfter_
    )
        payable
        ERC20Permit("CoveToken")
        ERC20("CoveToken", "COVE")
    {
        // Checks
        // slither-disable-next-line timestamp
        if (mintingAllowedAfter_ < block.timestamp) {
            revert Errors.MintingAllowedTooEarly();
        }
        // Effects
        OWNER_CAN_UNPAUSE_AFTER = block.timestamp + _OWNER_PAUSE_PERIOD;
        ANYONE_CAN_UNPAUSE_AFTER = block.timestamp + _MAX_PAUSE_PERIOD;
        _addToAllowedTransferrer(address(0)); // Allow minting
        _addToAllowedTransferrer(owner_); // Allow transfers from owner for distribution
        _mint(owner_, _INITIAL_SUPPLY); // Mint initial supply to the owner
        _pause(); // Pause the contract
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
        mintingAllowedAfter = mintingAllowedAfter_; // Set the time delay for the first mint
    }

    /**
     * @notice Mints tokens to a specified address.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyRole(_MINTER_ROLE) {
        if (amount > availableSupplyToMint()) {
            revert Errors.InflationTooLarge();
        }
        mintingAllowedAfter = block.timestamp + _MIN_MINT_INTERVAL;
        _mint(to, amount);
    }

    /**
     * @notice Unpauses the contract.
     */
    function unpause() external whenPaused {
        uint256 unpauseAfter =
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ? OWNER_CAN_UNPAUSE_AFTER : ANYONE_CAN_UNPAUSE_AFTER;
        // slither-disable-next-line timestamp
        if (block.timestamp < unpauseAfter) {
            revert Errors.UnpauseTooEarly();
        }
        _unpause();
    }

    /**
     * @notice Adds an address to the list of allowed transferees.
     * @param target The address to allow.
     */
    function addAllowedTransferee(address target) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addToAllowedTransferee(target);
    }

    /**
     * @notice Removes an address from the list of allowed transferees.
     * @param target The address to disallow.
     */
    function removeAllowedTransferee(address target) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeFromAllowedTransferee(target);
    }

    /**
     * @notice Adds an address to the list of allowed transferrers.
     * @param target The address to allow.
     */
    function addAllowedTransferrer(address target) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addToAllowedTransferrer(target);
    }

    /**
     * @notice Removes an address from the list of allowed transferrers.
     * @param target The address to disallow.
     */
    function removeAllowedTransferrer(address target) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeFromAllowedTransferrer(target);
    }

    /**
     * @notice Calculates the available supply that can be minted.
     * @return uint256 The amount of supply available for minting.
     */
    function availableSupplyToMint() public view returns (uint256) {
        // slither-disable-next-line timestamp
        if (block.timestamp < mintingAllowedAfter) {
            return 0;
        }
        return (totalSupply() * _MINT_CAP_NUMERATOR) / _MINT_CAP_DENOMINATOR;
    }

    function _addToAllowedTransferee(address target) internal {
        allowedTransferee[target] = true;
        emit TransfereeAllowed(target, _eventId);
        ++_eventId;
    }

    function _removeFromAllowedTransferee(address target) internal {
        allowedTransferee[target] = false;
        emit TransfereeDisallowed(target, _eventId);
        ++_eventId;
    }

    function _addToAllowedTransferrer(address target) internal {
        allowedTransferrer[target] = true;
        emit TransferrerAllowed(target, _eventId);
        ++_eventId;
    }

    function _removeFromAllowedTransferrer(address target) internal {
        allowedTransferrer[target] = false;
        emit TransferrerDisallowed(target, _eventId);
        ++_eventId;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes minting and burning.
     *      It checks if the contract is paused and if so, only allows transfers from allowed transferrers
     *      to allowed transferees.
     * @param from The address which is transferring tokens.
     * @param to The address which is receiving tokens.
     * @param amount The amount of tokens being transferred.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Check if the transfer is allowed
        // When paused, only allowed transferrers can transfer and only allowed transferees can receive
        if (paused()) {
            if (!allowedTransferrer[from]) {
                if (!allowedTransferee[to]) {
                    revert Errors.TransferNotAllowedYet();
                }
            }
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}

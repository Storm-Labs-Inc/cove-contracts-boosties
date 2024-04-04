// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { ERC20Permit, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { Errors } from "src/libraries/Errors.sol";

/**
 * @title CoveToken
 * @notice ERC20 token with governance features including roles, pausability, and permit functionality.
 * @dev This token includes roles for minting and pausing, as well as the ability to set transfer allowances via
 * signatures.  It also includes an allowlisting mechanism for:
 * - Senders: Vesting contracts, treasury multisig, or rewards contracts so CoveToken can be claimed.
 * - Receivers: For non-tokenized staking contracts like MiniChefV3 to enable staking while it is non-transferrable.
 * It inherits from OpenZeppelin's ERC20, ERC20Permit, AccessControlEnumerable, Pausable, and Multicall contracts.
 */
contract CoveToken is ERC20Permit, AccessControlEnumerable, Pausable, Multicall {
    /// @dev Initial delay before inflation starts.
    uint256 private constant _INITIAL_INFLATION_DELAY = 3 * 52 weeks;
    /// @dev Initial supply of tokens.
    uint256 private constant _INITIAL_SUPPLY = 1_000_000_000 ether;
    /// @dev Minimum time interval between mints.
    uint256 private constant _MIN_MINT_INTERVAL = 52 weeks;
    /// @dev Numerator for calculating mint cap.
    uint256 private constant _MINT_CAP_NUMERATOR = 600;
    /// @dev Denominator for calculating mint cap.
    uint256 private constant _MINT_CAP_DENOMINATOR = 10_000;
    /// @dev Maximum period the contract can be paused.
    uint256 private constant _MAX_PAUSE_PERIOD = 18 * 4 weeks;
    /// @dev Period after which the owner can unpause the contract.
    uint256 private constant _OWNER_PAUSE_PERIOD = 6 * 4 weeks;
    /// @dev Role identifier for minters.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @dev Role identifier for the timelock.
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

    /// @notice Timestamp after which minting is allowed.
    uint256 public mintingAllowedAfter;

    // slither-disable-start naming-convention
    /// @notice Timestamp after which the owner can unpause the contract.
    uint256 public immutable OWNER_CAN_UNPAUSE_AFTER;
    /// @notice Timestamp after which anyone can unpause the contract.
    uint256 public immutable ANYONE_CAN_UNPAUSE_AFTER;
    // slither-disable-end naming-convention

    /// @notice Mapping to track addresses allowed to receive transfers.
    mapping(address => bool) public allowedReceiver;
    /// @notice Mapping to track addresses allowed to initiate transfers.
    mapping(address => bool) public allowedSender;
    /// @notice State variable to make the events orderable for external observers if they are called in the same block.
    uint256 private _eventId;

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
     * @notice Deploys this contract with the initial owner and minting allowed after a specified time.
     * @dev The contract is paused upon deployment and the initial supply is minted to the owner.
     * @param owner_ The address of the initial owner.
     */
    constructor(address owner_) payable ERC20Permit("Cove DAO") ERC20("Cove DAO", "COVE") {
        // Checks
        if (owner_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        mintingAllowedAfter = block.timestamp + _INITIAL_INFLATION_DELAY;
        OWNER_CAN_UNPAUSE_AFTER = block.timestamp + _OWNER_PAUSE_PERIOD;
        ANYONE_CAN_UNPAUSE_AFTER = block.timestamp + _MAX_PAUSE_PERIOD;
        _addToAllowedSender(address(0)); // Allow minting
        _addToAllowedSender(owner_); // Allow transfers from owner for distribution
        _mint(owner_, _INITIAL_SUPPLY); // Mint initial supply to the owner
        _pause(); // Pause the contract
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
        _grantRole(TIMELOCK_ROLE, owner_); // This role must be revoked after granting it to the timelock
        _setRoleAdmin(TIMELOCK_ROLE, TIMELOCK_ROLE); // Only those with the timelock role can grant the timelock role
    }

    /**
     * @notice Mints tokens to a specified address.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
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
    function addAllowedReceiver(address target) external onlyRole(TIMELOCK_ROLE) {
        _addToAllowedReceiver(target);
    }

    /**
     * @notice Removes an address from the list of allowed transferees.
     * @param target The address to disallow.
     */
    function removeAllowedReceiver(address target) external onlyRole(TIMELOCK_ROLE) {
        _removeFromAllowedReceiver(target);
    }

    /**
     * @notice Adds an address to the list of allowed transferrers.
     * @param target The address to allow.
     */
    function addAllowedSender(address target) external onlyRole(TIMELOCK_ROLE) {
        _addToAllowedSender(target);
    }

    /**
     * @notice Removes an address from the list of allowed transferrers.
     * @param target The address to disallow.
     */
    function removeAllowedSender(address target) external onlyRole(TIMELOCK_ROLE) {
        _removeFromAllowedSender(target);
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
     *      - Allowed senders: Vesting, treasury multisig, and rewards contracts so CoveToken can be distributed.
     *      - Allowed receivers: For non-tokenized staking contracts like MiniChefV3 so any address can stake CoveToken
     *        while it's non-transferrable.
     * @param from The address which is transferring tokens.
     * @param to The address which is receiving tokens.
     * @param amount The amount of tokens being transferred.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Check if the transfer is allowed
        // When paused, only allowed transferrers can transfer or only allowed transferees can receive
        if (paused()) {
            if (!allowedSender[from]) {
                if (!allowedReceiver[to]) {
                    revert Errors.TransferNotAllowedYet();
                }
            }
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}

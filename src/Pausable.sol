pragma solidity ^0.8.18;

/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable {
    event Pause();
    event Unpause();

    bool public paused; // false by default
    bytes32 internal constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     */
    modifier whenPaused() {
        require(paused);
        _;
    }

    /**
     * @dev called by the pauser to pause, external function to be written in the derived contract to check for the
     * correct role
     */
    function _pause() internal whenNotPaused {
        paused = true;
        emit Pause();
    }

    /**
     * @dev called by the pauser to unpause, external function to be written in the derived contract to check for the
     * correct role
     */
    function _unpause() internal whenPaused {
        paused = false;
        emit Unpause();
    }
}

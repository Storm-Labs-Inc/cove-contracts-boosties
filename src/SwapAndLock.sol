// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Errors } from "src/libraries/Errors.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IYearnStakingDelegate, IVotingYFI } from "src/interfaces/IYearnStakingDelegate.sol";
import { ISwapAndLock } from "src/interfaces/ISwapAndLock.sol";

/**
 * @title SwapAndLock
 * @dev This contract is designed to swap dYFI tokens to YFI and lock them in the YearnStakingDelegate.
 * It inherits from ISwapAndLock, CurveRouterSwapper, AccessControl, and ReentrancyGuard to leverage
 * swapping functionality, role-based access control, and reentrancy protection.
 */
contract SwapAndLock is ISwapAndLock, AccessControl, ReentrancyGuard {
    // Libraries
    using SafeERC20 for IERC20;

    // Constants
    // ETH mainnet token addresses for YFI and dYFI
    address private constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address private constant _D_YFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    // Immutables
    // Address of the YearnStakingDelegate contract
    // slither-disable-next-line naming-convention
    address private immutable _YEARN_STAKING_DELEGATE;

    /// @notice Address of the DYfiRedeemer contract.
    address private _dYfiRedeemer;

    event DYfiRedeemerSet(address oldRedeemer, address newRedeemer);

    /**
     * @notice Constructs the SwapAndLock contract.
     * @param yearnStakingDelegate_ Address of the YearnStakingDelegate contract.
     */
    constructor(address yearnStakingDelegate_, address admin) {
        // Checks
        if (yearnStakingDelegate_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        _YEARN_STAKING_DELEGATE = yearnStakingDelegate_;
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        // Interactions
        IERC20(_YFI).forceApprove(yearnStakingDelegate_, type(uint256).max);
    }

    /**
     * @notice Locks YFI in the YearnStakingDelegate contract.
     * @return The total amount of YFI locked and the end timestamp of the lock after the lock operation.
     */
    function lockYfi() external returns (IVotingYFI.LockedBalance memory) {
        return IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).lockYfi(IERC20(_YFI).balanceOf(address(this)));
    }

    /**
     * @notice Sets the address of the DYfiRedeemer contract and approves it to spend dYFI. If the redeemer was already
     * set, the approval is removed from the old redeemer.
     * @param newDYfiRedeemer Address of the new DYfiRedeemer contract.
     */
    function setDYfiRedeemer(address newDYfiRedeemer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Checks
        if (newDYfiRedeemer == address(0)) {
            revert Errors.ZeroAddress();
        }
        address currentDYfiRedeemer = _dYfiRedeemer;
        if (newDYfiRedeemer == currentDYfiRedeemer) {
            revert Errors.SameAddress();
        }
        // Effects
        _dYfiRedeemer = newDYfiRedeemer;
        // Interactions
        emit DYfiRedeemerSet(currentDYfiRedeemer, newDYfiRedeemer);
        if (currentDYfiRedeemer != address(0)) {
            IERC20(_D_YFI).forceApprove(currentDYfiRedeemer, 0);
        }
        IERC20(_D_YFI).forceApprove(newDYfiRedeemer, type(uint256).max);
    }

    /**
     * @notice Get the address of the dYFI redeemer contract.
     * @return The address of the dYFI redeemer contract.
     */
    function dYfiRedeemer() external view returns (address) {
        return _dYfiRedeemer;
    }
}

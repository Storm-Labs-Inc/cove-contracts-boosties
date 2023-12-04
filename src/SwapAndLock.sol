// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Errors } from "src/libraries/Errors.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { ISwapAndLock } from "src/interfaces/ISwapAndLock.sol";

/**
 * @title SwapAndLock
 * @dev This contract is designed to swap dYFI tokens to YFI and lock them in the YearnStakingDelegate.
 * It inherits from ISwapAndLock, CurveRouterSwapper, AccessControl, and ReentrancyGuard to leverage
 * swapping functionality, role-based access control, and reentrancy protection.
 */
contract SwapAndLock is ISwapAndLock, CurveRouterSwapper, AccessControl, ReentrancyGuard {
    // Libraries
    using SafeERC20 for IERC20;

    // Constants
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    // ETH mainnet token addresses for YFI and dYFI
    address private constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address private constant _D_YFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    // Immutables
    // Address of the YearnStakingDelegate contract
    // slither-disable-next-line naming-convention
    address private immutable _YEARN_STAKING_DELEGATE;

    // Struct to store parameters for Curve swaps
    CurveSwapParams internal _routerParam;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructs the SwapAndLock contract.
     * @param curveRouter_ Address of the Curve router used for token swaps.
     * @param yearnStakingDelegate_ Address of the YearnStakingDelegate contract.
     */
    constructor(address curveRouter_, address yearnStakingDelegate_) CurveRouterSwapper(curveRouter_) {
        // Checks
        if (yearnStakingDelegate_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        _YEARN_STAKING_DELEGATE = yearnStakingDelegate_;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // Interactions
        _approveTokenForSwap(_D_YFI);
        IERC20(_YFI).forceApprove(yearnStakingDelegate_, type(uint256).max);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Sets the parameters for the Curve router swap.
     * @param routerParam The swap parameters to be used by the Curve router.
     * @dev Only callable by the admin role. Validates the swap parameters before setting them.
     */
    function setRouterParams(CurveSwapParams calldata routerParam) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Checks
        _validateSwapParams(routerParam, _D_YFI, _YFI);
        _routerParam = routerParam;
    }

    /**
     * @notice Swaps dYFI to YFI and locks the YFI in the YearnStakingDelegate.
     * @param minYfiAmount The minimum amount of YFI expected to receive from the swap.
     * @dev This function is non-reentrant and can only be called by an account with the manager role.
     * It checks the contract's dYFI balance, performs the swap, and locks the YFI.
     * Emits a SwapAndLocked event upon success.
     */
    function swapDYfiToVeYfi(uint256 minYfiAmount) external nonReentrant onlyRole(MANAGER_ROLE) {
        // Checks
        uint256 dYfiAmount = IERC20(_D_YFI).balanceOf(address(this));
        if (dYfiAmount != 0) {
            // Interactions
            uint256 yfiAmount = _swap(_routerParam, dYfiAmount, minYfiAmount, address(this));
            uint256 totalYfiLocked = IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).lockYfi(yfiAmount).amount;
            emit SwapAndLocked(dYfiAmount, yfiAmount, totalYfiLocked);
        } else {
            revert Errors.NoDYfiToSwap();
        }
    }
}

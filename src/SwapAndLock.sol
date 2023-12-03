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

contract SwapAndLock is ISwapAndLock, CurveRouterSwapper, AccessControl, ReentrancyGuard {
    // Libraries
    using SafeERC20 for IERC20;

    // Constants
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    address private constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address private constant _D_YFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    // Immutables
    // slither-disable-next-line naming-convention
    address private immutable _YEARN_STAKING_DELEGATE;

    CurveSwapParams internal _routerParam;

    /* ========== CONSTRUCTOR ========== */

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
    function setRouterParams(CurveSwapParams calldata routerParam) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Checks
        _validateSwapParams(routerParam, _D_YFI, _YFI);
        _routerParam = routerParam;
    }

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

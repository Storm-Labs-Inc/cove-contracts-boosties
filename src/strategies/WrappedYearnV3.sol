// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Errors } from "../libraries/Errors.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract WrappedYearnV3 is CurveRouterSwapper {
    // Libraries
    using SafeERC20 for IERC20;

    // Immutable storage variables
    // slither-disable-start naming-convention
    address internal immutable _VAULT;
    address internal immutable _YEARN_STAKING_DELEGATE;
    address internal immutable _DYFI;
    // slither-disable-end naming-convention

    // Storage variables
    CurveSwapParams internal _harvestSwapParams;
    uint256 public totalUnderlyingVaultShares;

    constructor(address _vault, address _yearnStakingDelegate, address _dYfi) {
        // Check for zero addresses
        if (_vault == address(0) || _yearnStakingDelegate == address(0) || _dYfi == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // Set storage variable values
        _VAULT = _vault;
        _YEARN_STAKING_DELEGATE = _yearnStakingDelegate;
        _DYFI = _dYfi;
    }

    function _setHarvestSwapParams(address asset, CurveSwapParams memory curveSwapParams) internal virtual {
        // Checks (includes external view calls)
        _validateSwapParams(curveSwapParams, _DYFI, asset);

        // Effects
        _harvestSwapParams = curveSwapParams;
    }

    function _depositGaugeToYSD(address gauge, uint256 amount) internal virtual {
        totalUnderlyingVaultShares += amount;
        IERC20(gauge).forceApprove(_YEARN_STAKING_DELEGATE, amount);
        IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).deposit(gauge, amount);
    }

    function _withdrawGaugeFromYSD(address gauge, uint256 amount) internal virtual {
        // Update totalUnderlyingVaultShares
        totalUnderlyingVaultShares -= amount;
        // Withdraw gauge from YSD which transfers to msg.sender
        IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).withdraw(gauge, amount);
    }

    function vault() external view returns (address) {
        return _VAULT;
    }

    function yearnStakingDelegate() external view returns (address) {
        return _YEARN_STAKING_DELEGATE;
    }

    function dYfi() external view returns (address) {
        return _DYFI;
    }
}

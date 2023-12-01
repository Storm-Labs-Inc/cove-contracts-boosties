// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Errors } from "../libraries/Errors.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract WrappedYearnV3 {
    // Libraries
    using SafeERC20 for IERC20;

    // Immutable storage variables
    // slither-disable-start naming-convention
    address private immutable _YEARN_STAKING_DELEGATE;
    address private immutable _DYFI;
    // slither-disable-end naming-convention

    constructor(address asset, address _yearnStakingDelegate, address _dYfi) {
        // Check for zero addresses
        if (_yearnStakingDelegate == address(0) || _dYfi == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // Set storage variable values
        _YEARN_STAKING_DELEGATE = _yearnStakingDelegate;
        _DYFI = _dYfi;

        // Interactions
        IERC20(asset).forceApprove(_YEARN_STAKING_DELEGATE, type(uint256).max);
    }

    function _depositToYSD(address asset, uint256 amount) internal virtual {
        IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).deposit(asset, amount);
    }

    function _withdrawFromYSD(address asset, uint256 amount) internal virtual {
        // Withdraw gauge from YSD which transfers to msg.sender
        IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).withdraw(asset, amount);
    }

    function yearnStakingDelegate() public view returns (address) {
        return _YEARN_STAKING_DELEGATE;
    }

    function dYfi() public view returns (address) {
        return _DYFI;
    }
}

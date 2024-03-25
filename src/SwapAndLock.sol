// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IYearnStakingDelegate, IVotingYFI } from "src/interfaces/IYearnStakingDelegate.sol";
import { ISwapAndLock } from "src/interfaces/ISwapAndLock.sol";
import { CoveYFI } from "./CoveYFI.sol";

/**
 * @title SwapAndLock
 * @dev This contract is designed to swap dYFI tokens to YFI and lock them in the YearnStakingDelegate.
 * It inherits from ISwapAndLock and AccessControlEnumerable to leverage swapping functionality
 * and role-based access control.
 */
contract SwapAndLock is ISwapAndLock, AccessControlEnumerable {
    // Libraries
    using SafeERC20 for IERC20;

    // Constants
    /// @notice Address of the mainnet Yearn YFI token.
    address private constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    /// @notice Address of the mainnet Yearn D_YFI token.
    address private constant _D_YFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    // Immutables
    /// @dev Address of the YearnStakingDelegate contract, set at deployment and immutable thereafter.
    // slither-disable-next-line naming-convention
    address private immutable _YEARN_STAKING_DELEGATE;
    address private immutable _COVE_YFI;

    /// @notice Address of the DYfiRedeemer contract.
    address private _dYfiRedeemer;

    /**
     * @notice Emitted when the address of the DYfiRedeemer contract is updated.
     * @param oldRedeemer The address of the previous DYfiRedeemer contract.
     * @param newRedeemer The address of the new DYfiRedeemer contract.
     */
    event DYfiRedeemerSet(address oldRedeemer, address newRedeemer);

    /**
     * @notice Constructs the SwapAndLock contract.
     * @param yearnStakingDelegate_ Address of the YearnStakingDelegate contract.
     * @param coveYfi_ Address of the CoveYFI contract.
     * @param admin Address of the contract admin for rescuing tokens.
     */
    // slither-disable-next-line locked-ether
    constructor(address yearnStakingDelegate_, address coveYfi_, address admin) payable {
        // Checks
        if (coveYfi_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Effects
        _YEARN_STAKING_DELEGATE = yearnStakingDelegate_;
        _COVE_YFI = coveYfi_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // Interactions
        IERC20(_YFI).forceApprove(coveYfi_, type(uint256).max);
    }

    /**
     * @notice Converts any YFI held by this contract to CoveYFI, minting CoveYFI to the treasury. YFI will be locked as
     * veYFI under YearnStakingDelegate's ownership.
     * @return The amount of coveYFI minted.
     */
    function convertToCoveYfi() external returns (uint256) {
        address treasury = IYearnStakingDelegate(_YEARN_STAKING_DELEGATE).treasury();
        return CoveYFI(_COVE_YFI).deposit(IERC20(_YFI).balanceOf(address(this)), treasury);
    }

    /**
     * @notice Sets the address of the DYfiRedeemer contract and approves it to spend dYFI. If the redeemer was already
     * set, the approval is removed from the old redeemer.
     * @param newDYfiRedeemer Address of the new DYFIRedeemer contract.
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

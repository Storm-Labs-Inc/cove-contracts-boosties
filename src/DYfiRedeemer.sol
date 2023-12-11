// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { IFlashLoanProvider } from "src/interfaces/deps/balancer/IFlashLoanProvider.sol";
import { IRedemption } from "src/interfaces/deps/yearn/veYFI/IRedemption.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { AggregatorV3Interface } from "src/interfaces/deps/chainlink/AggregatorV3Interface.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICurveTwoAssetPool } from "src/interfaces/deps/curve/ICurveTwoAssetPool.sol";
import { IWETH } from "src/interfaces/deps/IWETH.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IDYfiRedeemer } from "src/interfaces/IDYfiRedeemer.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title DYfiRedeemer
 * @notice This contract can be used to redeem dYFI for YFI for multiple dYFI holders in a single transaction.
 * Any address that holds dYFI can approve this contract to spend their dYFI. Then the caller of massRedeem
 * will provide a list of dYFI holders and their dYFI amounts. By utilizing low-fee flash loans from Balancer,
 * this contract can redeem all dYFI for YFI, and sell the excess YFI for ETH to pay back the flash loan and
 * to reward the caller.
 * The users who approve this contract to spend their dYFI must acknowledge that they will not receive more than
 * the minimum amount of YFI that should be redeemed for their dYFI. The minimum amount of YFI at a given time can be
 * calculated using the `minYfiRedeem(uint256 dYfiAmount)` function.
 */
contract DYfiRedeemer is IDYfiRedeemer, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    address private constant _REDEMPTION = 0x7dC3A74F0684fc026f9163C6D5c3C99fda2cf60a;
    address private constant _YFI_ETH_PRICE_FEED = 0x3EbEACa272Ce4f60E800f6C5EE678f50D2882fd4;
    address private constant _FLASH_LOAN_PROVIDER = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address private constant _DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address private constant _YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address private constant _WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant _ETH_YFI_CURVE_POOL = 0xC26b89A667578ec7b3f11b2F98d6Fd15C07C54ba;
    uint256 private constant _MAX_SLIPPAGE = 0.05e18;
    uint256 private constant _DEFAULT_SLIPPAGE = 0.01e18;

    /// @notice The slippage that should be applied to the redemption process
    uint256 private _slippage;

    constructor() {
        // Effects
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _slippage = _DEFAULT_SLIPPAGE;
        // Interactions
        IERC20(_YFI).forceApprove(_ETH_YFI_CURVE_POOL, type(uint256).max);
        IERC20(_DYFI).forceApprove(_REDEMPTION, type(uint256).max);
    }

    /// @dev Allows this contract to receive ETH
    receive() external payable { }

    /**
     * @notice Redeems dYFI for YFI for multiple dYFI holders in a single transaction. Any extra ETH will be sent to the
     * caller.
     * @dev This function utilizes flash loans from Balancer to acquire ETH needed to redeem dYFI for YFI.
     * The amount of YFI to distribute is calculated as follows:
     *  YFI to distribute = dYFI amount - ETH required for redemption * YFI/ETH price * (1 + slippage)
     * The extra YFI is swapped for ETH and sent to the caller as an extra reward.
     * @param dYfiHolders list of addresses that hold dYFI and have approved this contract to spend their dYFI
     * @param dYfiAmounts list of dYFI amounts that should be redeemed for YFI from the corresponding dYFI holder
     */
    function massRedeem(
        address[] calldata dYfiHolders,
        uint256[] calldata dYfiAmounts
    )
        external
        nonReentrant
        whenNotPaused
    {
        if (dYfiHolders.length != dYfiAmounts.length) {
            revert Errors.InvalidArrayLength();
        }
        // Transfer all dYfi to this contract from dYfi holders who have approved this contract
        // List of dYfi holders and their dYfi amounts must be provided off-chain
        uint256 totalDYfiAmount;
        for (uint256 i = 0; i < dYfiHolders.length; i++) {
            totalDYfiAmount += dYfiAmounts[i];
            // slither-disable-next-line arbitrary-send-erc20
            IERC20(_DYFI).safeTransferFrom(dYfiHolders[i], address(this), dYfiAmounts[i]);
        }
        if (totalDYfiAmount == 0) {
            revert Errors.NoDYfiToRedeem();
        }
        // Determine ETH required for redemption
        uint256 ethRequired = _getEthRequired(totalDYfiAmount);
        // Calculate amount of YFI to swap based on the slippage and ETH required for redemption
        uint256 yfiToSwap = ethRequired * (1e18 + _slippage) / _getLatestPrice();
        // Calculate total YFI that should be sent to dYFI holders
        uint256 yfiToDistribute = totalDYfiAmount - yfiToSwap;
        // Construct flash loan parameters
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(_WETH);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ethRequired;
        // Flashloan ETH required for redemption. After the flash loan, this contract will have
        // YFI to distribute to dYFI holders and some ETH to reward the caller.
        IFlashLoanProvider(_FLASH_LOAN_PROVIDER).flashLoan(
            this, tokens, amounts, abi.encode(totalDYfiAmount, yfiToSwap)
        );
        // Distribute YFI to dYFI holders proportionally to their dYFI amounts
        // If for any reason, the flashLoan call resulted in less YFI than yfiToDistribute, the following
        // distribution would revert on a transfer call.
        for (uint256 i = 0; i < dYfiHolders.length; i++) {
            uint256 yfiAmount = yfiToDistribute * dYfiAmounts[i] / totalDYfiAmount;
            emit DYfiRedeemed(dYfiHolders[i], dYfiAmounts[i], yfiAmount);
            IERC20(_YFI).safeTransfer(dYfiHolders[i], yfiAmount);
        }
        // Send the remaining ETH to the caller
        uint256 callerReward = address(this).balance;
        emit CallerReward(msg.sender, callerReward);
        // slither-disable-next-line arbitrary-send-eth
        payable(msg.sender).transfer(callerReward);
    }

    /**
     * @notice Called by the flash loan provider to execute a flash loan of WETH.
     * @param tokens list of token addresses flash loaned.
     * @param amounts list of amounts flash loaned.
     * @param feeAmounts list of fee amounts that must be paid back.
     * @param userData additional data with no specified format.
     */
    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    )
        external
    {
        if (msg.sender != _FLASH_LOAN_PROVIDER) {
            revert Errors.NotAuthorized();
        }
        if (tokens.length != 1 || amounts.length != 1 || feeAmounts.length != 1 || tokens[0] != IERC20(_WETH)) {
            revert Errors.InvalidTokensReceived();
        }
        // Acquire ETH from flash loan
        IWETH(_WETH).withdraw(amounts[0]);
        // Calculate ETH payment to the flash loan provider
        uint256 flashLoanPayment = amounts[0] + feeAmounts[0];
        // Decode userData
        (uint256 totalDYfiAmount, uint256 yfiToSwap) = abi.decode(userData, (uint256, uint256));
        // Redeem all dYFI for YFI
        // Assume that the redemption contract will return the correct amount of YFI
        // slither-disable-next-line unused-return
        IRedemption(_REDEMPTION).redeem{ value: amounts[0] }(totalDYfiAmount);
        // Calculate amount of YFI to swap for ETH for the flash loan payment and the caller reward
        // Swap YFI for ETH. Require at least flashLoanPayment ETH to be received from the swap.
        // Any surplus ETH will be reserved for the caller of massRedeem.
        // slither-disable-next-line unused-return
        ICurveTwoAssetPool(_ETH_YFI_CURVE_POOL).exchange(1, 0, yfiToSwap, flashLoanPayment, true);
        // On correct behavior of the curve pool, the swap should result in at least flashLoanPayment ETH
        // If the swap behaved incorrectly and returned less than flashLoanPayment ETH, then the WETH deposit
        // call would fail with out of funds error.
        IWETH(_WETH).deposit{ value: flashLoanPayment }();
        // Pay back the flash loan
        IERC20(_WETH).safeTransfer(msg.sender, flashLoanPayment);
    }

    /**
     * @notice Sets the slippage that should be applied to DYFI -> YFI redeems.
     * @dev The slippage is applied to the YFI/ETH price. For example, if the slippage is 0.01e18,
     * then the YFI/ETH price will be multiplied by 1.01.
     * @param slippage_ The new slippage to use for YFI swaps.
     */
    function setSlippage(uint256 slippage_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (slippage_ > _MAX_SLIPPAGE) {
            revert Errors.SlippageTooHigh();
        }
        _setSlippage(slippage_);
    }

    /**
     * @notice Kills the contract. Only the admin can call this function.
     */
    function kill() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Returns the minimum amount of YFI that should be redeemed for a given amount of dYFI
     * @param dYfiAmount The amount of dYFI to redeem
     * @return The minimum amount of YFI that should be redeemed for a given amount of dYFI
     */
    function minYfiRedeem(uint256 dYfiAmount) external view returns (uint256) {
        return dYfiAmount - _getEthRequired(dYfiAmount) * (1e18 + _MAX_SLIPPAGE) / _getLatestPrice();
    }

    /**
     * @notice Returns the expected amount of YFI that should be redeemed for a given amount of dYFI
     * @param dYfiAmount The amount of dYFI to redeem
     * @return The expected amount of YFI that should be redeemed for a given amount of dYFI
     */
    function currentYfiRedeem(uint256 dYfiAmount) external view returns (uint256) {
        return dYfiAmount - _getEthRequired(dYfiAmount) * (1e18 + _slippage) / _getLatestPrice();
    }

    /**
     * @notice Calculates the expected amount of ETH the caller will receive for redeeming dYFI for YFI for the given
     * users and amounts.
     * @dev This assumes flash loan fee of 0.
     * @param dYfiAmount total dYFI amount that should be redeemed for YFI.
     * @return The expected amount of ETH the caller will receive for redeeming dYFI for YFI.
     */
    function expectedMassRedeemReward(uint256 dYfiAmount) external view returns (uint256) {
        if (dYfiAmount == 0) {
            return 0;
        }
        // The ETH required for redemption will be flash loaned from Balancer
        uint256 ethRequired = _getEthRequired(dYfiAmount);
        uint256 yfiToSwap = ethRequired * (1e18 + _slippage) / _getLatestPrice();
        uint256 minDy = ICurveTwoAssetPool(_ETH_YFI_CURVE_POOL).get_dy(1, 0, yfiToSwap);
        // Return surplus ETH
        return minDy - ethRequired;
    }

    /**
     * @notice Returns the latest YFI/ETH from the Chainlink price feed.
     * @return The latest ETH per 1 YFI from the Chainlink price feed.
     */
    function getLatestPrice() external view returns (uint256) {
        return _getLatestPrice();
    }

    /**
     * @notice Get the slippage that should be applied to DYFI -> YFI redeems.
     * @return The slippage in 1e18 precision.
     */
    function slippage() external view returns (uint256) {
        return _slippage;
    }

    /**
     * @dev Internal function to set the slippage that should be applied to DYFI -> YFI redeems.
     * @param slippage_ The new slippage to use for YFI swaps.
     */
    function _setSlippage(uint256 slippage_) internal {
        _slippage = slippage_;
        emit SlippageSet(slippage_);
    }

    /// @dev Returns ETH per 1 YFI in 1e18 precision
    function _getLatestPrice() internal view returns (uint256) {
        // slither-disable-next-line unused-return
        (, int256 price,, uint256 timeStamp,) = AggregatorV3Interface(_YFI_ETH_PRICE_FEED).latestRoundData();
        // slither-disable-next-line timestamp
        if (timeStamp + 3600 < block.timestamp) {
            revert Errors.PriceFeedOutdated();
        }
        return uint256(price);
    }

    /// @dev Returns the ETH required for redemption in 1e18 precision
    function _getEthRequired(uint256 dYfiAmount) internal view returns (uint256) {
        return IRedemption(_REDEMPTION).eth_required(dYfiAmount) * 997 / 1000 + 1;
    }
}

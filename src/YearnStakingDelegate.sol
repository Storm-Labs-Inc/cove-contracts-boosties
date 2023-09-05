// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract YearnStakingDelegate {
    /// @notice Mapping of vault to gauge
    mapping(address vault => address gauge) public associatedGauge;
    mapping(address user => mapping(address vault => uint256 balance)) public balances;
    address public manager;
    address public oYFI;

    using SafeERC20 for IERC20;

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager can call this function.");
        _;
    }

    function harvest(address vault) external {
        // TODO: implement harvest
        address strategy = msg.sender;
        address treasury = address(0);
        uint256 treasuryAmount = 0;
        uint256 compoundAmount = 0;
        // IYearnGauge(associatedGauge[vault]).claim();
        // Do actions based on configured parameters
        IERC20(oYFI).transfer(treasury, treasuryAmount);
        IERC20(oYFI).transfer(strategy, compoundAmount);
    }

    function depositAndStake(address vault, uint256 amount) external {
        IERC20(vault).transferFrom(msg.sender, address(this), amount);
        // IYearnGauge(associatedGauge[vault]).deposit(amount);
        balances[msg.sender][vault] += amount;
    }

    function withdraw(uint256 amount) external { }

    // Swaps any held oYFI to YFI using oYFI/YFI path on Curve
    function swapOYFIToYFI() external onlyManager { }
    // Lock all YFI and increase lock time
    function lockYFI() external onlyManager { }
}

// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

contract YearnStakingDelegate {
    /// @notice Mapping of vault to gauge
    mapping(address vault => address gauge) public associatedGauge;
    address public manager;

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager can call this function.");
        _;
    }

    function harvest(address vault) external {
        strategy = msg.sender;
        associatedGauge[vault].claim();
        // Do actions based on configured parameters
        oYFI.transfer(treasury, treasuryAmount);
        oYFI.transfer(strategy, compoundAmount);
    }

    function depositAndStake(address vault, uint256 amount) external {
        vault.transferFrom(msg.sender, amount, here);
        associatedGauge[vault].deposit(amount);
        balances[msg.sender][vault] += amount;
    }

    function withdraw(uint256 amount) external { }

    // Swaps any held oYFI to YFI using oYFI/YFI path on Curve
    function swapOYFIToYFI() external onlyManager { }
    // Lock all YFI and increase lock time
    function lockYFI() external onlyManager { }
}

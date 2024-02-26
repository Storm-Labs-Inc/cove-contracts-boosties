pragma solidity ^0.8.18;

contract MockYearnGaugeStrategy {
    uint256 public maxTotalAssets;
    uint256 public totalAssets;

    function setMaxTotalAssets(uint256 newMaxTotalAssets) external {
        maxTotalAssets = newMaxTotalAssets;
    }

    function setTotalAssets(uint256 newTotalAssets) external {
        totalAssets = newTotalAssets;
    }
}

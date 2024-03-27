// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

contract MockMiniChefRewarder {
    event FunctionHit();

    uint256 public pid = 0;
    mapping(uint256 => uint256) public spendGas;
    uint256 public gasLoop;

    function onReward(uint256, address, address, uint256, uint256) external {
        // use some gas
        for (uint256 i = 0; i < gasLoop; i++) {
            spendGas[i] += 1;
        }
        emit FunctionHit();
    }

    function setGasLoop(uint256 _gasLoop) external {
        gasLoop = _gasLoop;
    }
}

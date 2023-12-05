pragma solidity ^0.8.18;

import { IVotingYFI } from "src/interfaces/deps/yearn/veYFI/IVotingYFI.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockVotingYFI {
    address public immutable YFI;

    constructor(address yfi_) {
        YFI = yfi_;
    }

    function modify_lock(uint256 amount, uint256, address) external returns (IVotingYFI.LockedBalance memory) {
        IERC20(YFI).transferFrom(msg.sender, address(this), amount);
    }

    function withdraw() external returns (IVotingYFI.Withdrawn memory withdrawn) {
        uint256 amount = IERC20(YFI).balanceOf(address(this));
        IERC20(YFI).transfer(msg.sender, amount);
        withdrawn.amount = amount;
    }
}

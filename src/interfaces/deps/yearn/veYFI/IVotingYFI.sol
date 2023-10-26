// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVotingYFI is IERC20 {
    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    // TODO: this was removed, do we need to refactor?
    struct Withdrawn {
        uint256 amount;
        uint256 penalty;
    }

    function totalSupply() external view returns (uint256);

    function locked(address _user) external view returns (LockedBalance memory);

    function modify_lock(uint256 _amount, uint256 _unlock_time, address _user) external;

    // TODO: this was removed, do we need to refactor?
    function withdraw() external returns (Withdrawn memory);
}

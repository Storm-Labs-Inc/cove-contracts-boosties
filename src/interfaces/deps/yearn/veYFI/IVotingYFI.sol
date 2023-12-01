// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVotingYFI is IERC20 {
    event ModifyLock(address indexed sender, address indexed user, uint256 amount, uint256 locktime, uint256 ts);
    event Withdraw(address indexed user, uint256 amount, uint256 ts);
    event Penalty(address indexed user, uint256 amount, uint256 ts);
    event Supply(uint256 oldSupply, uint256 newSupply, uint256 ts);

    struct LockedBalance {
        uint256 amount;
        uint256 end;
    }

    struct Withdrawn {
        uint256 amount;
        uint256 penalty;
    }

    struct Point {
        int128 bias;
        int128 slope;
        uint256 ts;
        uint256 blk;
    }

    function totalSupply() external view returns (uint256);

    function locked(address _user) external view returns (LockedBalance memory);

    function modify_lock(
        uint256 _amount,
        uint256 _unlock_time,
        address _user
    )
        external
        returns (LockedBalance memory);

    function withdraw() external returns (Withdrawn memory);

    function point_history(address user, uint256 epoch) external view returns (Point memory);
}

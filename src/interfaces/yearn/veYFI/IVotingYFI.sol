// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-5.0/contracts/token/ERC20/IERC20.sol";

interface IVotingYFI is IERC20 {
    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    struct Withdrawn {
        uint256 amount;
        uint256 penalty;
    }

    function totalSupply() external view returns (uint256);

    function locked(address _user) external view returns (LockedBalance memory);

    // solhint-disable-next-line func-param-name-mixedcase,var-name-mixedcase
    function modify_lock(uint256 _amount, uint256 _unlock_time, address _user) external;

    function withdraw() external returns (Withdrawn memory);
}
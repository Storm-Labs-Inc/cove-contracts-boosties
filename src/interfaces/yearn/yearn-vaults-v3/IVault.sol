// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { IERC4626 } from "@openzeppelin-5.0/contracts/interfaces/IERC4626.sol";

interface IVault is IERC4626 {
    struct StrategyParams {
        uint256 activation;
        uint256 lastReport;
        uint256 currentDebt;
        uint256 maxDebt;
    }

    function strategies(address _strategy) external view returns (StrategyParams memory);

    function set_role(address, uint256) external;

    function roles(address _address) external view returns (uint256);

    function profitMaxUnlockTime() external view returns (uint256);

    function add_strategy(address) external;

    function update_max_debt_for_strategy(address, uint256) external;

    function update_debt(address, uint256) external;

    function process_report(address _strategy) external returns (uint256, uint256);

    function set_deposit_limit(uint256) external;

    function shutdown_vault() external;

    function shutdown() external view returns (bool);

    function deposit(uint256 assets, address receiver) external returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function totalDebt() external view returns (uint256);
    function totalIdle() external view returns (uint256);
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        // solhint-disable-next-line func-param-name-mixedcase,var-name-mixedcase
        uint256 max_loss,
        address[] memory strategies
    )
        external
        returns (uint256);
}
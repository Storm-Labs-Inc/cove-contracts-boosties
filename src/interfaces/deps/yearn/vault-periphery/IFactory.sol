// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IFactory {
    function api_version() external view returns (string memory);

    function vault_blueprint() external view returns (address);

    function deploy_new_vault(
        ERC20 asset,
        string calldata name,
        string calldata symbol,
        address roleManager,
        uint256 profitMaxUnlockTime
    )
        external
        returns (address);
}

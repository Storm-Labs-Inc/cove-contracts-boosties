// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { CoveToken } from "src/governance/CoveToken.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { CommonBase } from "forge-std/Base.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";

contract CoveTokenHandler is CommonBase, StdUtils, StdAssertions {
    CoveToken public coveToken;
    bytes32 public minterRole = keccak256("MINTER_ROLE");
    uint256 public totalSupply;
    bool public paused;

    constructor() {
        coveToken = new CoveToken(address(this), block.timestamp + 365 days);
        coveToken.grantRole(minterRole, address(this));
        totalSupply = coveToken.totalSupply();
        paused = true;
    }

    function transferBetweenApprovedSenders(address to, uint256 amount) public {
        if (address(to) == address(0)) {
            return;
        }
        amount = bound(amount, 0, coveToken.balanceOf(address(this)));
        coveToken.transfer(to, amount);
        coveToken.addAllowedTransferrer(to);
        vm.prank(to);
        coveToken.transfer(address(this), amount);
    }

    function mint(address to, uint256 amount) public {
        if (address(to) == address(0)) {
            return;
        }
        if (coveToken.mintingAllowedAfter() > block.timestamp) {
            vm.warp(coveToken.mintingAllowedAfter());
        }
        amount = bound(amount, 1, coveToken.availableSupplyToMint());
        totalSupply += amount;
        coveToken.mint(to, amount);
    }

    function unpause() public {
        if (paused) {
            if (coveToken.OWNER_CAN_UNPAUSE_AFTER() > block.timestamp) {
                vm.warp(coveToken.OWNER_CAN_UNPAUSE_AFTER());
            }
            coveToken.unpause();
            paused = false;
        }
    }
}

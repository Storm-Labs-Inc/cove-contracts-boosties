// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { YearnV3BaseTest, console } from "test/utils/YearnV3BaseTest.t.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISignatureTransfer } from "permit2/interfaces/ISignatureTransfer.sol";

contract PermitSignature_Test is YearnV3BaseTest {
    address testAccount;
    uint256 testAccountPK;

    function setUp() public override {
        super.setUp();
        // (0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000.000000000000000000 ETH)
        (testAccount, testAccountPK) = deriveRememberKey({ mnemonic: TEST_MNEMONIC, index: 0 });
    }

    function _generatePermitSignatureAndLog(
        address token,
        address owner,
        uint256 ownerPrivateKey,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    )
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        string memory typeHashInput =
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)";
        console.log("");
        console.log("Generating permit signature for token: ", token);
        console.log("EIP 712 input:");
        console.log("  DOMAIN_SEPARATOR: ", vm.toString(IERC20Permit(MAINNET_USDC).DOMAIN_SEPARATOR()));
        console.log("  TYPEHASH input: ", typeHashInput);
        console.log("  TYPEHASH: ", vm.toString(keccak256(bytes(typeHashInput))));
        console.log("Signature parameters:");
        console.log("  Private Key: ", vm.toString(bytes32(ownerPrivateKey)));
        console.log("  Owner: ", owner);
        console.log("  Spender: ", address(0xbeef));
        console.log("  Value: ", uint256(1000 ether));
        console.log("  Nonce: ", nonce);
        console.log("  Deadline: ", _MAX_UINT256);
        (v, r, s) = _generatePermitSignature(token, owner, ownerPrivateKey, spender, value, nonce, deadline);
        console.log("");
        console.log("Generated signature: ");
        console.log("  v: ", v);
        console.log("  r: ", vm.toString(r));
        console.log("  s: ", vm.toString(s));
    }

    function _generatePermit2PermitTransferFromSignatureAndLog(
        uint256 privateKey,
        address token,
        uint256 amount,
        address to,
        uint256 nonce,
        uint256 deadline
    )
        internal
        view
        returns (
            ISignatureTransfer.PermitTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails memory transferDetails,
            bytes memory signature
        )
    {
        string memory typeHashInput =
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)";
        console.log("");
        console.log("Generating Permit2 PermitTransferFrom signature");
        console.log("EIP 712 input:");
        console.log("  DOMAIN_SEPARATOR: ", vm.toString(IERC20Permit(MAINNET_PERMIT2).DOMAIN_SEPARATOR()));
        console.log("  TYPEHASH input: ", typeHashInput);
        console.log("  TYPEHASH: ", vm.toString(keccak256(bytes(typeHashInput))));
        console.log("Signature parameters:");
        console.log("  Private Key: ", vm.toString(bytes32(privateKey)));
        console.log("  TokenPermissions.token: ", token);
        console.log("  TokenPermissions.amount: ", amount);
        console.log("  To: ", to);
        console.log("  Nonce: ", nonce);
        console.log("  Deadline: ", deadline);

        (permit, transferDetails, signature) =
            _generateRouterPullTokenWithPermit2Params(privateKey, token, amount, to, nonce, deadline);

        console.log("Generated Permit2 PermitTransferFrom signature:");
        console.log("  Permit:");
        console.log("    Token: ", permit.permitted.token);
        console.log("    Amount: ", permit.permitted.amount);
        console.log("    Nonce: ", permit.nonce);
        console.log("    Deadline: ", permit.deadline);
        console.log("  Transfer Details:");
        console.log("    To: ", transferDetails.to);
        console.log("    Requested Amount: ", transferDetails.requestedAmount);
        console.log("  Signature: ", vm.toString(signature));
    }
    //// TESTS ////

    function test_permitSignature() public {
        // First permit
        address spender = address(0xbeef);
        uint256 value = 1000 ether;

        (uint8 v, bytes32 r, bytes32 s) = _generatePermitSignatureAndLog(
            MAINNET_USDC,
            testAccount,
            testAccountPK,
            spender,
            value,
            IERC20Permit(MAINNET_USDC).nonces(testAccount),
            _MAX_UINT256
        );

        IERC20Permit(MAINNET_USDC).permit(testAccount, spender, value, _MAX_UINT256, v, r, s);
        assertEq(IERC20(MAINNET_USDC).allowance(testAccount, spender), value);

        // Second permit
        spender = address(0xbeef);
        value = 2000 ether;

        (v, r, s) = _generatePermitSignatureAndLog(
            MAINNET_USDC,
            testAccount,
            testAccountPK,
            spender,
            value,
            IERC20Permit(MAINNET_USDC).nonces(testAccount),
            _MAX_UINT256
        );

        IERC20Permit(MAINNET_USDC).permit(testAccount, spender, value, _MAX_UINT256, v, r, s);
        assertEq(IERC20(MAINNET_USDC).allowance(testAccount, spender), value);
    }

    function test_permit2PermitTransferFromSignature() public {
        vm.prank(testAccount);
        IERC20(MAINNET_USDC).approve(MAINNET_PERMIT2, _MAX_UINT256);

        // First permitTransferFrom
        address to = address(0xdead);
        uint256 amount = 1000 ether;
        uint256 unorderedNonce = 42;

        (
            ISignatureTransfer.PermitTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails memory transferDetails,
            bytes memory signature
        ) = _generatePermit2PermitTransferFromSignatureAndLog(
            testAccountPK, MAINNET_USDC, amount, to, unorderedNonce, _MAX_UINT256
        );

        airdrop(IERC20(MAINNET_USDC), testAccount, amount);
        uint256 balanceBefore = IERC20(MAINNET_USDC).balanceOf(to);
        vm.prank(to);
        ISignatureTransfer(MAINNET_PERMIT2).permitTransferFrom(permit, transferDetails, testAccount, signature);
        assertEq(IERC20(MAINNET_USDC).balanceOf(to), balanceBefore + amount);

        // Second permitTransferFrom
        to = address(0xbeef);
        amount = 2000 ether;
        unorderedNonce = 420;

        (permit, transferDetails, signature) = _generatePermit2PermitTransferFromSignatureAndLog(
            testAccountPK, MAINNET_USDC, amount, to, unorderedNonce, _MAX_UINT256
        );

        airdrop(IERC20(MAINNET_USDC), testAccount, amount);
        balanceBefore = IERC20(MAINNET_USDC).balanceOf(to);
        vm.prank(to);
        ISignatureTransfer(MAINNET_PERMIT2).permitTransferFrom(permit, transferDetails, testAccount, signature);
        assertEq(IERC20(MAINNET_USDC).balanceOf(to), balanceBefore + amount);
    }
}

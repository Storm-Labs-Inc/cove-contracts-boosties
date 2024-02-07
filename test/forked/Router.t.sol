// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { Yearn4626RouterExt, ISignatureTransfer } from "src/Yearn4626RouterExt.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { PeripheryPayments, SelfPermit, Yearn4626RouterBase } from "Yearn-ERC4626-Router/Yearn4626RouterBase.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Router_ForkedTest is BaseTest {
    Yearn4626RouterExt public router;

    event Log(string message);
    event LogBytes(bytes data);

    address public user;
    uint256 public userPriv;

    function setUp() public override {
        // https://etherscan.io/block/19072737
        // Jan-23-2024 11:49:59 PM +UTC
        forkNetworkAt("mainnet", 19_072_737);
        _labelEthereumAddresses();
        super.setUp();
        router = new Yearn4626RouterExt("Yearn-4626-Router", MAINNET_WETH, MAINNET_PERMIT2);
        vm.label(address(router), "4626Router");

        (user, userPriv) = createUserAndKey("user");
    }

    function test_curveLpTokenToYearnGauge() public {
        uint256 depositAmount = 1 ether;
        airdrop(IERC20(MAINNET_CURVE_ETH_YFI_LP_TOKEN), user, depositAmount);

        // Generate a permit signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            userPriv, // user's private key
            keccak256(
                abi.encodePacked(
                    "\x19\x01", // EIP-712 encoding
                    IERC20Permit(MAINNET_CURVE_ETH_YFI_LP_TOKEN).DOMAIN_SEPARATOR(),
                    // Frontend should use deadline with enough buffer and with the correct nonce
                    // keccak256(abi.encode(PERMIT_TYPEHASH, user, address(router), depositAmount,
                    // sourceToken.nonces(user),
                    // block.timestamp + 100_000))
                    keccak256(abi.encode(PERMIT_TYPEHASH, user, address(router), depositAmount, 0, block.timestamp))
                )
            )
        );

        bytes[] memory data = new bytes[](6);
        data[0] = abi.encodeWithSelector(
            SelfPermit.selfPermit.selector, MAINNET_CURVE_ETH_YFI_LP_TOKEN, depositAmount, block.timestamp, v, r, s
        );
        data[1] = abi.encodeWithSelector(
            PeripheryPayments.pullToken.selector, MAINNET_CURVE_ETH_YFI_LP_TOKEN, depositAmount, address(router)
        );
        data[2] = abi.encodeWithSelector(
            PeripheryPayments.approve.selector, MAINNET_CURVE_ETH_YFI_LP_TOKEN, MAINNET_ETH_YFI_VAULT_V2, _MAX_UINT256
        );
        data[3] = abi.encodeWithSelector(
            Yearn4626RouterExt.depositToVaultV2.selector,
            MAINNET_ETH_YFI_VAULT_V2,
            depositAmount,
            address(router),
            // When depositing into vaults, the shares may be less than the deposit amount
            // For yearn v2 vaults, use pricePerShare to calculate the shares
            // 1e18 * depositAmount / YearnVaultV2.pricePerShare()
            949_289_266_142_683_599
        );
        data[4] = abi.encodeWithSelector(
            PeripheryPayments.approve.selector, MAINNET_ETH_YFI_VAULT_V2, MAINNET_ETH_YFI_GAUGE, _MAX_UINT256
        );
        data[5] = abi.encodeWithSelector(
            Yearn4626RouterBase.deposit.selector,
            MAINNET_ETH_YFI_GAUGE,
            949_289_266_142_683_599,
            user,
            // Gauges return shares 1:1 with the deposit amount
            949_289_266_142_683_599
        );

        vm.prank(user);
        router.multicall(data);

        assertEq(IERC20(MAINNET_CURVE_ETH_YFI_LP_TOKEN).balanceOf(user), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(user), 949_289_266_142_683_599);
    }

    function test_curveLpTokenToYearnGauge_revertWhen_insufficientShares() public {
        uint256 depositAmount = 1 ether;
        airdrop(IERC20(MAINNET_CURVE_ETH_YFI_LP_TOKEN), user, depositAmount);

        // Generate a permit signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            userPriv, // user's private key
            keccak256(
                abi.encodePacked(
                    "\x19\x01", // EIP-712 encoding
                    IERC20Permit(MAINNET_CURVE_ETH_YFI_LP_TOKEN).DOMAIN_SEPARATOR(),
                    // Frontend should use deadline with enough buffer and with the correct nonce
                    // keccak256(abi.encode(PERMIT_TYPEHASH, user, address(router), depositAmount,
                    // sourceToken.nonces(user),
                    // block.timestamp + 100_000))
                    keccak256(abi.encode(PERMIT_TYPEHASH, user, address(router), depositAmount, 0, block.timestamp))
                )
            )
        );

        bytes[] memory data = new bytes[](6);
        data[0] = abi.encodeWithSelector(
            SelfPermit.selfPermit.selector, MAINNET_CURVE_ETH_YFI_LP_TOKEN, depositAmount, block.timestamp, v, r, s
        );
        data[1] = abi.encodeWithSelector(
            PeripheryPayments.pullToken.selector, MAINNET_CURVE_ETH_YFI_LP_TOKEN, depositAmount, address(router)
        );
        data[2] = abi.encodeWithSelector(
            PeripheryPayments.approve.selector, MAINNET_CURVE_ETH_YFI_LP_TOKEN, MAINNET_ETH_YFI_VAULT_V2, _MAX_UINT256
        );
        data[3] = abi.encodeWithSelector(
            Yearn4626RouterExt.depositToVaultV2.selector,
            MAINNET_ETH_YFI_VAULT_V2,
            depositAmount,
            address(router),
            // When depositing into vaults, the shares may be less than the deposit amount
            // For yearn v2 vaults, use pricePerShare to calculate the shares
            // 1e18 * depositAmount / YearnVaultV2.pricePerShare()
            // setting as depositAmount to show fail case
            depositAmount
        );
        data[4] = abi.encodeWithSelector(
            PeripheryPayments.approve.selector, MAINNET_ETH_YFI_VAULT_V2, MAINNET_ETH_YFI_GAUGE, _MAX_UINT256
        );
        data[5] = abi.encodeWithSelector(
            Yearn4626RouterBase.deposit.selector,
            MAINNET_ETH_YFI_GAUGE,
            949_289_266_142_683_599,
            user,
            // Gauges return shares 1:1 with the deposit amount
            949_289_266_142_683_599
        );

        // uniswap code doesn't allow for below
        // vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.InsufficientShares.selector));
        vm.expectRevert(); // have to use generic revert for now
        vm.prank(user);
        router.multicall(data);
    }

    function test_pullTokensWithPermit2() public {
        uint256 depositAmount = 1 ether;
        // YFI allows for permit2
        airdrop(IERC20(MAINNET_YFI), user, depositAmount);
        // max approce permit2
        vm.prank(user);
        IERC20(MAINNET_YFI).approve(MAINNET_PERMIT2, _MAX_UINT256);

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: MAINNET_YFI, amount: depositAmount }),
            nonce: 0,
            deadline: block.timestamp + 100
        });

        bytes memory signature = _getPermitTransferSignature(
            permit, address(router), userPriv, ISignatureTransfer(MAINNET_PERMIT2).DOMAIN_SEPARATOR()
        );

        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({ to: address(router), requestedAmount: depositAmount });
        vm.prank(user);
        router.pullTokensWithPermit2(permit, transferDetails, signature);
        uint256 userBalanceAfter = IERC20(MAINNET_YFI).balanceOf(user);
        assertEq(userBalanceAfter, 0, "User should have 0 token after transfer");
        assertEq(IERC20(MAINNET_YFI).balanceOf(address(router)), depositAmount, "Router should have the token");
    }

    function test_pullTokensWithPermit2_revertWhen_InvalidTo() public {
        uint256 depositAmount = 1 ether;
        // YFI allows for permit2
        airdrop(IERC20(MAINNET_YFI), user, depositAmount);
        // max approce permit2
        vm.prank(user);
        IERC20(MAINNET_YFI).approve(MAINNET_PERMIT2, _MAX_UINT256);

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: MAINNET_YFI, amount: depositAmount }),
            nonce: 0,
            deadline: block.timestamp + 100
        });

        bytes memory signature = _getPermitTransferSignature(
            permit, address(this), userPriv, ISignatureTransfer(MAINNET_PERMIT2).DOMAIN_SEPARATOR()
        );

        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({ to: address(this), requestedAmount: depositAmount });
        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.InvalidTo.selector));
        vm.prank(user);
        router.pullTokensWithPermit2(permit, transferDetails, signature);
    }

    // Below from Permit2.PermitSignature.sol, only added a "to" parameter
    function _getPermitTransferSignature(
        ISignatureTransfer.PermitTransferFrom memory permit,
        address to,
        uint256 privateKey,
        bytes32 domainSeparator
    )
        internal
        view
        returns (bytes memory sig)
    {
        bytes32 tokenPermissions = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissions, to, permit.nonce, permit.deadline)
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }
}

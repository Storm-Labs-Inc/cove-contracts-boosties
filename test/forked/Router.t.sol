// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { Yearn4626RouterExt, ISignatureTransfer } from "src/Yearn4626RouterExt.sol";
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

    function test_previewDeposits() public {
        uint256 assetInAmount = 1 ether;
        Yearn4626RouterExt.Vault[] memory previewDeposit = new Yearn4626RouterExt.Vault[](2);
        previewDeposit[0] = Yearn4626RouterExt.Vault(MAINNET_ETH_YFI_VAULT_V2, true);
        previewDeposit[1] = Yearn4626RouterExt.Vault(MAINNET_ETH_YFI_GAUGE, false);

        (address assetInAddress, uint256[] memory sharesOut) = router.previewDeposits(previewDeposit, assetInAmount);
        assertEq(assetInAddress, MAINNET_ETH_YFI_POOL_LP_TOKEN);
        assertEq(sharesOut[0], 949_289_266_142_683_599);
        assertEq(sharesOut[1], 949_289_266_142_683_599);
    }

    function test_previewMints() public {
        uint256 shareOutAmount = 949_289_266_142_683_599;
        Yearn4626RouterExt.Vault[] memory previewMint = new Yearn4626RouterExt.Vault[](2);
        previewMint[0] = Yearn4626RouterExt.Vault(MAINNET_ETH_YFI_VAULT_V2, true);
        previewMint[1] = Yearn4626RouterExt.Vault(MAINNET_ETH_YFI_GAUGE, false);

        (address assetInAddress, uint256[] memory assetsIn) = router.previewMints(previewMint, shareOutAmount);
        assertEq(assetInAddress, MAINNET_ETH_YFI_POOL_LP_TOKEN);
        assertEq(assetsIn[0], 1 ether);
        assertEq(assetsIn[1], 1 ether);
    }

    function test_previewWithdraws() public {
        uint256 assetOutAmount = 1 ether;
        Yearn4626RouterExt.Vault[] memory previewWithdraw = new Yearn4626RouterExt.Vault[](2);
        previewWithdraw[0] = Yearn4626RouterExt.Vault(MAINNET_ETH_YFI_GAUGE, false);
        previewWithdraw[1] = Yearn4626RouterExt.Vault(MAINNET_ETH_YFI_VAULT_V2, true);

        (address assetOutAddress, uint256[] memory sharesIn) = router.previewWithdraws(previewWithdraw, assetOutAmount);
        assertEq(assetOutAddress, MAINNET_ETH_YFI_POOL_LP_TOKEN);
        assertEq(sharesIn[0], 1 ether);
        assertEq(sharesIn[1], 949_289_266_142_683_599);
    }

    function test_previewRedeems() public {
        uint256 shareInAmount = 949_289_266_142_683_599;
        Yearn4626RouterExt.Vault[] memory previewRedeem = new Yearn4626RouterExt.Vault[](2);
        previewRedeem[0] = Yearn4626RouterExt.Vault(MAINNET_ETH_YFI_GAUGE, false);
        previewRedeem[1] = Yearn4626RouterExt.Vault(MAINNET_ETH_YFI_VAULT_V2, true);

        (address assetOutAddress, uint256[] memory assetsOut) = router.previewRedeems(previewRedeem, shareInAmount);
        assertEq(assetOutAddress, MAINNET_ETH_YFI_POOL_LP_TOKEN);
        assertEq(assetsOut[0], 949_289_266_142_683_599);
        assertEq(assetsOut[1], 1 ether);
    }

    function test_curveLpTokenToYearnGauge() public {
        uint256 depositAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), user, depositAmount);

        // Generate a permit signature
        (uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(
            MAINNET_ETH_YFI_POOL_LP_TOKEN, user, userPriv, address(router), depositAmount, 0, block.timestamp
        );

        bytes[] memory data = new bytes[](6);
        data[0] = abi.encodeWithSelector(
            SelfPermit.selfPermit.selector, MAINNET_ETH_YFI_POOL_LP_TOKEN, depositAmount, block.timestamp, v, r, s
        );
        data[1] = abi.encodeWithSelector(
            PeripheryPayments.pullToken.selector, MAINNET_ETH_YFI_POOL_LP_TOKEN, depositAmount, address(router)
        );
        data[2] = abi.encodeWithSelector(
            PeripheryPayments.approve.selector, MAINNET_ETH_YFI_POOL_LP_TOKEN, MAINNET_ETH_YFI_VAULT_V2, _MAX_UINT256
        );
        data[3] = abi.encodeWithSelector(
            Yearn4626RouterExt.depositToVaultV2.selector,
            MAINNET_ETH_YFI_VAULT_V2,
            depositAmount,
            address(router),
            // When depositing into vaults, the shares may be less than the deposit amount
            // For yearn v2 vaults, use pricePerShare to calculate the shares
            // 1e18 * depositAmount / YearnVaultV2.pricePerShare() - 1
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

        assertEq(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN).balanceOf(user), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(user), 949_289_266_142_683_599);
    }

    function test_curveLpTokenToYearnGauge_revertWhen_insufficientShares() public {
        uint256 depositAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), user, depositAmount);

        // Generate a permit signature
        (uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(
            MAINNET_ETH_YFI_POOL_LP_TOKEN, user, userPriv, address(router), depositAmount, 0, block.timestamp
        );

        bytes[] memory data = new bytes[](6);
        data[0] = abi.encodeWithSelector(
            SelfPermit.selfPermit.selector, MAINNET_ETH_YFI_POOL_LP_TOKEN, depositAmount, block.timestamp, v, r, s
        );
        data[1] = abi.encodeWithSelector(
            PeripheryPayments.pullToken.selector, MAINNET_ETH_YFI_POOL_LP_TOKEN, depositAmount, address(router)
        );
        data[2] = abi.encodeWithSelector(
            PeripheryPayments.approve.selector, MAINNET_ETH_YFI_POOL_LP_TOKEN, MAINNET_ETH_YFI_VAULT_V2, _MAX_UINT256
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

        ISignatureTransfer.PermitTransferFrom memory permit =
            _getPermit2PermitTransferFrom(MAINNET_YFI, depositAmount, 0, block.timestamp + 100);

        bytes memory signature = _getPermit2PermitTransferSignature(
            permit, address(router), userPriv, ISignatureTransfer(MAINNET_PERMIT2).DOMAIN_SEPARATOR()
        );

        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            _getPerit2SignatureTransferDetails(address(router), depositAmount);
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

        ISignatureTransfer.PermitTransferFrom memory permit =
            _getPermit2PermitTransferFrom(MAINNET_YFI, depositAmount, 0, block.timestamp + 100);

        bytes memory signature = _getPermit2PermitTransferSignature(
            permit, address(this), userPriv, ISignatureTransfer(MAINNET_PERMIT2).DOMAIN_SEPARATOR()
        );

        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            _getPerit2SignatureTransferDetails(address(this), depositAmount);
        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.InvalidTo.selector));
        vm.prank(user);
        router.pullTokensWithPermit2(permit, transferDetails, signature);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { Yearn4626RouterExt, ISignatureTransfer } from "src/Yearn4626RouterExt.sol";
import { PeripheryPayments, SelfPermit, Yearn4626RouterBase } from "Yearn-ERC4626-Router/Yearn4626RouterBase.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IYearnVaultV2 } from "src/interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IPermit2 } from "permit2/interfaces/IPermit2.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IStakeDaoGauge } from "src/interfaces/deps/stakeDAO/IStakeDaoGauge.sol";

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
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_ETH_YFI_GAUGE;

        uint256[] memory sharesOut = router.previewDeposits(path, assetInAmount);
        assertEq(sharesOut.length, 2);
        assertEq(sharesOut[0], 949_289_266_142_683_599);
        assertEq(sharesOut[1], 949_289_266_142_683_599);
    }

    function test_previewDeposits_revertWhen_PathIsTooShort() public {
        uint256 assetInAmount = 1 ether;
        address[] memory path = new address[](1);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;

        vm.expectRevert(Yearn4626RouterExt.PathIsTooShort.selector);
        router.previewDeposits(path, assetInAmount);
    }

    function test_previewDeposits_revertWhen_NonVaultAddressInPath() public {
        uint256 assetInAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_YFI; // Use non 4626 address for the test

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.NonVaultAddressInPath.selector, MAINNET_YFI));
        router.previewDeposits(path, assetInAmount);
    }

    function test_previewDeposits_revertWhen_InvalidVaultInPath_NotAContract() public {
        uint256 assetInAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = address(0); // Use non 4626 address for the test

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.NonVaultAddressInPath.selector, address(0)));
        router.previewDeposits(path, assetInAmount);
    }

    function test_previewDeposits_revertWhen_VaultMismatch() public {
        uint256 assetInAmount = 1 ether;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_CRV_YCRV_POOL_GAUGE; // Intentional mismatch for the test

        vm.expectRevert(Yearn4626RouterExt.VaultMismatch.selector);
        router.previewDeposits(path, assetInAmount);
    }

    function test_previewMints() public {
        uint256 shareOutAmount = 949_289_266_142_683_599;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_ETH_YFI_GAUGE;

        uint256[] memory assetsIn = router.previewMints(path, shareOutAmount);
        assertEq(assetsIn.length, 2);
        assertEq(assetsIn[0], 1 ether);
        assertEq(assetsIn[1], 1 ether);
    }

    function test_previewMints_revertWhen_PathIsTooShort() public {
        uint256 shareOutAmount = 949_289_266_142_683_599;
        address[] memory path = new address[](1);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;

        vm.expectRevert(Yearn4626RouterExt.PathIsTooShort.selector);
        router.previewMints(path, shareOutAmount);
    }

    function test_previewMints_revertWhen_NonVaultAddressInPath() public {
        uint256 shareOutAmount = 949_289_266_142_683_599;
        address[] memory path = new address[](2);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_YFI; // Use non 4626 address for the test

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.NonVaultAddressInPath.selector, MAINNET_YFI));
        router.previewMints(path, shareOutAmount);
    }

    function test_previewMints_revertWhen_InvalidVaultInPath_NotAContract() public {
        uint256 shareOutAmount = 949_289_266_142_683_599;
        address[] memory path = new address[](2);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = address(0); // Use non 4626 address for the test

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.NonVaultAddressInPath.selector, address(0)));
        router.previewMints(path, shareOutAmount);
    }

    function test_previewMints_revertWhen_VaultMismatch() public {
        uint256 shareOutAmount = 949_289_266_142_683_599;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_CRV_YCRV_POOL_GAUGE; // Intentional mismatch for the test

        vm.expectRevert(Yearn4626RouterExt.VaultMismatch.selector);
        router.previewMints(path, shareOutAmount);
    }

    function test_previewWithdraws() public {
        uint256 assetOutAmount = 999_999_999_999_999_999;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_ETH_YFI_POOL_LP_TOKEN;

        uint256[] memory sharesIn = router.previewWithdraws(path, assetOutAmount);
        assertEq(sharesIn.length, 2);
        assertEq(sharesIn[0], 999_999_999_999_999_999);
        assertEq(sharesIn[1], 949_289_266_142_683_599);
    }

    function test_previewWithdraws_StakeDAO() public {
        uint256 assetOutAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = MAINNET_STAKE_DAO_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;

        (uint256[] memory sharesIn) = router.previewWithdraws(path, assetOutAmount);
        assertEq(sharesIn.length, 1);
        assertEq(sharesIn[0], 1 ether);
    }

    function test_previewWithdraws_revertWhen_PathIsTooShort() public {
        uint256 assetOutAmount = 1 ether;
        address[] memory path = new address[](1);
        path[0] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(Yearn4626RouterExt.PathIsTooShort.selector);
        router.previewWithdraws(path, assetOutAmount);
    }

    function test_previewWithdraws_revertWhen_NonVaultAddressInPath() public {
        uint256 assetOutAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = MAINNET_YFI; // Use non 4626 address for the test
        path[1] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.NonVaultAddressInPath.selector, MAINNET_YFI));
        router.previewWithdraws(path, assetOutAmount);
    }

    function test_previewWithdraws_revertWhen_InvalidVaultInPath_NotAContract() public {
        uint256 assetOutAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = address(0); // Use non 4626 address for the test
        path[1] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.NonVaultAddressInPath.selector, address(0)));
        router.previewWithdraws(path, assetOutAmount);
    }

    function test_previewWithdraws_revertWhen_VaultMismatch() public {
        uint256 assetOutAmount = 1 ether;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_CRV_YCRV_POOL_GAUGE; // Intentional mismatch for the test

        vm.expectRevert(Yearn4626RouterExt.VaultMismatch.selector);
        router.previewWithdraws(path, assetOutAmount);
    }

    function test_previewRedeems() public {
        uint256 shareInAmount = 949_289_266_142_683_599;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_ETH_YFI_POOL_LP_TOKEN;

        (uint256[] memory assetsOut) = router.previewRedeems(path, shareInAmount);
        assertEq(assetsOut.length, 2);
        assertEq(assetsOut[0], 949_289_266_142_683_599);
        assertEq(assetsOut[1], 999_999_999_999_999_999);
    }

    function test_previewRedeems_StakeDAO() public {
        uint256 shareInAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = MAINNET_STAKE_DAO_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;

        (uint256[] memory assetsOut) = router.previewRedeems(path, shareInAmount);
        assertEq(assetsOut.length, 1);
        assertEq(assetsOut[0], 1 ether);
    }

    function test_previewRedeems_revertWhen_PathIsTooShort() public {
        uint256 shareInAmount = 1 ether;
        address[] memory path = new address[](1);
        path[0] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(Yearn4626RouterExt.PathIsTooShort.selector);
        router.previewRedeems(path, shareInAmount);
    }

    function test_previewRedeems_revertWhen_NonVaultAddressInPath() public {
        uint256 shareInAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = MAINNET_YFI; // Use non 4626 address for the test
        path[1] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.NonVaultAddressInPath.selector, MAINNET_YFI));
        router.previewRedeems(path, shareInAmount);
    }

    function test_previewRedeems_revertWhen_NonVaultAddressInPath_NotAContract() public {
        uint256 shareInAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = address(0); // Use non 4626 address for the test
        path[1] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.NonVaultAddressInPath.selector, address(0)));
        router.previewRedeems(path, shareInAmount);
    }

    function test_previewRedeems_revertWhen_VaultMismatch() public {
        uint256 shareInAmount = 1 ether;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_CRV_YCRV_POOL_GAUGE; // Intentional mismatch for the test

        vm.expectRevert(Yearn4626RouterExt.VaultMismatch.selector);
        router.previewRedeems(path, shareInAmount);
    }

    function test_pullTokensWithPermit2() public {
        uint256 depositAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), user, depositAmount);
        // Yearn gauge does not support permit signing, therefore we must use Permit2
        // User's one time max approve Permit2.
        vm.prank(user);
        IERC20(MAINNET_ETH_YFI_GAUGE).approve(MAINNET_PERMIT2, _MAX_UINT256);

        // Generate Permit2 Signature
        // Find current approval nonce of the user
        (,, uint48 currentNonce) = IPermit2(MAINNET_PERMIT2).allowance(user, MAINNET_ETH_YFI_GAUGE, address(router));
        uint256 deadline = block.timestamp + 1000;
        (
            ISignatureTransfer.PermitTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails memory transferDetails,
            bytes memory signature
        ) = _generateRouterPullTokenWithPermit2Params({
            privateKey: userPriv,
            token: MAINNET_ETH_YFI_GAUGE,
            amount: depositAmount,
            to: address(router),
            nonce: currentNonce,
            deadline: deadline
        });

        vm.prank(user);
        router.pullTokenWithPermit2(permit, transferDetails, signature);
        uint256 userBalanceAfter = IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(user);
        assertEq(userBalanceAfter, 0, "User should have 0 token after transfer");
        assertEq(
            IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(address(router)), depositAmount, "Router should have the token"
        );
    }

    function test_pullTokensWithPermit2_revertWhen_InvalidTo() public {
        uint256 depositAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), user, depositAmount);
        // One time max approve Permit2.
        vm.prank(user);
        IERC20(MAINNET_ETH_YFI_GAUGE).approve(MAINNET_PERMIT2, _MAX_UINT256);

        // Generate Permit2 Signature
        // Find current approval nonce of the user's token to the router
        (,, uint48 currentNonce) = IPermit2(MAINNET_PERMIT2).allowance(user, MAINNET_ETH_YFI_GAUGE, address(router));
        uint256 deadline = block.timestamp + 1000;
        (
            ISignatureTransfer.PermitTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails memory transferDetails,
            bytes memory signature
        ) = _generateRouterPullTokenWithPermit2Params({
            privateKey: userPriv,
            token: MAINNET_ETH_YFI_GAUGE,
            amount: depositAmount,
            to: address(0), // Use invalid to address
            nonce: currentNonce,
            deadline: deadline
        });

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.InvalidTo.selector));
        vm.prank(user);
        router.pullTokenWithPermit2(permit, transferDetails, signature);
    }

    function test_redeemVaultV2() public {
        uint256 shareAmount = 949_289_266_142_683_599;
        airdrop(IERC20(MAINNET_ETH_YFI_VAULT_V2), address(router), shareAmount, false);
        router.redeemVaultV2(IYearnVaultV2(MAINNET_ETH_YFI_VAULT_V2), shareAmount, user, 0);

        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(user), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN).balanceOf(user), 999_999_999_999_999_999);
    }

    function test_redeemVaultV2_revertWhen_InsufficientAssets() public {
        uint256 shareAmount = 949_289_266_142_683_599;
        airdrop(IERC20(MAINNET_ETH_YFI_VAULT_V2), address(router), shareAmount);
        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.InsufficientAssets.selector));
        router.redeemVaultV2(IYearnVaultV2(MAINNET_ETH_YFI_VAULT_V2), shareAmount, user, 1 ether);
    }

    function test_redeemFromRouter() public {
        uint256 shareAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), address(router), shareAmount, false);
        router.redeemFromRouter(IERC4626(MAINNET_ETH_YFI_GAUGE), shareAmount, user, 0);

        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(user), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(user), shareAmount);
    }

    function test_withdrawFromRouter() public {
        uint256 shareAmount = 1 ether;
        uint256 assetAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), address(router), shareAmount, false);
        router.withdrawFromRouter(IERC4626(MAINNET_ETH_YFI_GAUGE), assetAmount, user, 1 ether);

        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(user), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(user), assetAmount);
    }

    function test_withdrawFromRouter_revertWhen_RequiresMoreThanMaxShares() public {
        uint256 shareAmount = 1 ether;
        uint256 assetAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), address(router), shareAmount);
        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.RequiresMoreThanMaxShares.selector));
        router.withdrawFromRouter(IERC4626(MAINNET_ETH_YFI_GAUGE), assetAmount, user, 0);
    }

    // ------------------ StakeDAO redeem tests ------------------
    function test_redeemStakeDaoGauge() public {
        uint256 shareAmount = 1 ether;
        airdrop(IERC20(MAINNET_STAKE_DAO_ETH_YFI_GAUGE), address(router), shareAmount, false);
        router.redeemStakeDaoGauge(IStakeDaoGauge(MAINNET_STAKE_DAO_ETH_YFI_GAUGE), shareAmount);

        assertEq(IERC20(MAINNET_STAKE_DAO_ETH_YFI_GAUGE).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_STAKE_DAO_ETH_YFI_GAUGE).balanceOf(user), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(address(router)), shareAmount);
    }

    //------------------- Multicall Tests -------------------
    function test_lpTokenToYearnGauge() public {
        uint256 depositAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), user, depositAmount, false);

        // Generate a permit signature
        uint256 currentNonce = IERC20Permit(MAINNET_ETH_YFI_POOL_LP_TOKEN).nonces(user);
        uint256 deadline = block.timestamp + 1000;
        (uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(
            MAINNET_ETH_YFI_POOL_LP_TOKEN, user, userPriv, address(router), depositAmount, currentNonce, deadline
        );

        bytes[] memory data = new bytes[](6);
        data[0] = abi.encodeWithSelector(
            SelfPermit.selfPermit.selector, MAINNET_ETH_YFI_POOL_LP_TOKEN, depositAmount, deadline, v, r, s
        );
        data[1] = abi.encodeWithSelector(
            PeripheryPayments.pullToken.selector, MAINNET_ETH_YFI_POOL_LP_TOKEN, depositAmount, address(router)
        );
        // One time max approval for the vault to spend the LP tokens
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
        // One time max approval for the vault to spend the LP tokens
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
        bytes[] memory ret = router.multicall(data);
        assertEq(ret[0], "", "SelfPermit should return empty bytes");
        assertEq(ret[1], "", "pullToken should return empty bytes");
        assertEq(ret[2], "", "approve should return empty bytes");
        assertEq(abi.decode(ret[3], (uint256)), 949_289_266_142_683_599, "depositToVaultV2 should return minted shares");
        assertEq(ret[4], "", "approve should return empty bytes");
        assertEq(abi.decode(ret[5], (uint256)), 949_289_266_142_683_599, "deposit should return minted shares");

        assertEq(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN).balanceOf(user), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(user), 949_289_266_142_683_599);
    }

    function test_yearnGaugeToLPToken() public {
        uint256 shareAmount = 949_289_266_142_683_599;
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), user, shareAmount, false);

        // Yearn gauge does not support permit signing, therefore we must use Permit2
        // User's one time max approve Permit2.
        vm.prank(user);
        IERC20(MAINNET_ETH_YFI_GAUGE).approve(MAINNET_PERMIT2, _MAX_UINT256);

        // Generate Permit2 Signature
        // Find current approval nonce of the user
        (,, uint48 currentNonce) = IPermit2(MAINNET_PERMIT2).allowance(user, MAINNET_ETH_YFI_GAUGE, address(router));
        uint256 deadline = block.timestamp + 1000;
        (
            ISignatureTransfer.PermitTransferFrom memory permit,
            ISignatureTransfer.SignatureTransferDetails memory transferDetails,
            bytes memory signature
        ) = _generateRouterPullTokenWithPermit2Params({
            privateKey: userPriv,
            token: MAINNET_ETH_YFI_GAUGE,
            amount: shareAmount,
            to: address(router),
            nonce: currentNonce,
            deadline: deadline
        });

        // Build multicall data
        bytes[] memory data = new bytes[](4);
        data[0] =
            abi.encodeWithSelector(Yearn4626RouterExt.pullTokenWithPermit2.selector, permit, transferDetails, signature);
        data[1] = abi.encodeWithSelector(
            Yearn4626RouterExt.redeemFromRouter.selector,
            MAINNET_ETH_YFI_GAUGE,
            shareAmount,
            address(router),
            // Yearn gauges return shares 1:1 with the deposit amount
            shareAmount
        );
        data[2] = abi.encodeWithSelector(
            PeripheryPayments.approve.selector, MAINNET_ETH_YFI_VAULT_V2, MAINNET_ETH_YFI_POOL_LP_TOKEN, _MAX_UINT256
        );
        data[3] = abi.encodeWithSelector(
            Yearn4626RouterExt.redeemVaultV2.selector,
            MAINNET_ETH_YFI_VAULT_V2,
            shareAmount,
            address(user),
            // When redeeming vault shares, the asset out may be different than the shares
            // For yearn v2 vaults, use pricePerShare to calculate the asset out
            // shareAmount * YearnVaultV2.pricePerShare() / 1e18
            999_999_999_999_999_999
        );

        vm.prank(user);
        bytes[] memory ret = router.multicall(data);
        assertEq(ret[0], "", "pullTokenWithPermit2 should return empty bytes");
        assertEq(abi.decode(ret[1], (uint256)), 949_289_266_142_683_599, "withdraw should return withdrawn shares");
        assertEq(ret[2], "", "approve should return empty bytes");
        assertEq(abi.decode(ret[3], (uint256)), 999_999_999_999_999_999, "redeemVaultV2 should return withdrawn amount");
    }

    function test_curveLpTokenToYearnGauge_revertWhen_insufficientShares() public {
        uint256 depositAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), user, depositAmount);

        // Generate a permit signature
        uint256 currentNonce = IERC20Permit(MAINNET_ETH_YFI_POOL_LP_TOKEN).nonces(user);
        uint256 deadline = block.timestamp + 1000;
        (uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(
            MAINNET_ETH_YFI_POOL_LP_TOKEN, user, userPriv, address(router), depositAmount, currentNonce, deadline
        );

        bytes[] memory data = new bytes[](6);
        data[0] = abi.encodeWithSelector(
            SelfPermit.selfPermit.selector, MAINNET_ETH_YFI_POOL_LP_TOKEN, depositAmount, block.timestamp, v, r, s
        );
        data[1] = abi.encodeWithSelector(
            PeripheryPayments.pullToken.selector, MAINNET_ETH_YFI_POOL_LP_TOKEN, depositAmount, address(router)
        );
        // One time max approval for the vault to spend the LP tokens
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
        // One time max approval for the vault to spend the LP tokens
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
}

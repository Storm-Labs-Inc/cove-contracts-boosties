// SPDX-License-Identifier: BUSL-1.1
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
import { IYearn4626 } from "Yearn-ERC4626-Router/interfaces/IYearn4626.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626Mock } from "@openzeppelin/contracts/mocks/ERC4626Mock.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { YearnVaultV2Helper } from "src/libraries/YearnVaultV2Helper.sol";

contract Router_ForkedTest is BaseTest {
    using YearnVaultV2Helper for IYearnVaultV2;

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

    // ------------------ Permit2 tests ------------------
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

    function test_pullTokensWithPermit2_revertWhen_InvalidPermit2TransferTo() public {
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

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.InvalidPermit2TransferTo.selector));
        vm.prank(user);
        router.pullTokenWithPermit2(permit, transferDetails, signature);
    }

    function test_pullTokensWithPermit2_revertWhen_InvalidPermit2TransferAmount() public {
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
            amount: depositAmount, // Use invalid amount
            to: address(router),
            nonce: currentNonce,
            deadline: deadline
        });
        // Corrupt the requested amount to be different than the permit amount
        transferDetails.requestedAmount = depositAmount + 1;

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.InvalidPermit2TransferAmount.selector));
        vm.prank(user);
        router.pullTokenWithPermit2(permit, transferDetails, signature);
    }

    // ------------------ Yearn Vault V2 tests ------------------

    function test_deposit_passWhen_WithYearnVaultV2() public {
        uint256 depositAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), address(router), depositAmount, false);
        router.approve(ERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), MAINNET_ETH_YFI_VAULT_V2, depositAmount);
        router.deposit(IYearn4626(MAINNET_ETH_YFI_VAULT_V2), depositAmount, user, 0);

        assertEq(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN).balanceOf(user), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(address(user)), 949_289_266_142_683_599);
    }

    function test_deposit_revertWhen_WithYearnVaultV2_MinShares() public {
        uint256 depositAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), address(router), depositAmount, false);
        router.approve(ERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), MAINNET_ETH_YFI_VAULT_V2, depositAmount);
        vm.expectRevert("!MinShares");
        router.deposit(IYearn4626(MAINNET_ETH_YFI_VAULT_V2), depositAmount, address(user), 100 ether);
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

    // --------------- IERC4626 withdraw/redeem router holdings tests ----------------

    function test_redeemFromRouter() public {
        uint256 shareAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), address(router), shareAmount, false);
        router.redeemFromRouter(IERC4626(MAINNET_ETH_YFI_GAUGE), shareAmount, user, 0);

        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(user), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(user), shareAmount);
    }

    function test_redeemFromRouter_revertWhen_InsufficientAssets() public {
        uint256 shareAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), address(router), shareAmount);
        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.InsufficientAssets.selector));
        router.redeemFromRouter(IERC4626(MAINNET_ETH_YFI_GAUGE), shareAmount, user, 100 ether);
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

        assertEq(
            router.redeemStakeDaoGauge(IStakeDaoGauge(MAINNET_STAKE_DAO_ETH_YFI_GAUGE), shareAmount, user), shareAmount
        );

        assertEq(IERC20(MAINNET_STAKE_DAO_ETH_YFI_GAUGE).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_STAKE_DAO_ETH_YFI_GAUGE).balanceOf(user), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(user), shareAmount);
    }

    function test_redeemStakeDaoGauge_ToRouter() public {
        uint256 shareAmount = 1 ether;
        airdrop(IERC20(MAINNET_STAKE_DAO_ETH_YFI_GAUGE), address(router), shareAmount, false);

        assertEq(
            router.redeemStakeDaoGauge(IStakeDaoGauge(MAINNET_STAKE_DAO_ETH_YFI_GAUGE), shareAmount, address(router)),
            shareAmount
        );

        assertEq(IERC20(MAINNET_STAKE_DAO_ETH_YFI_GAUGE).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(address(router)), shareAmount);
    }

    // ------------------ Preview tests ------------------
    function testFuzz_previewDeposits(uint256 assetInAmount) public {
        // When a vault's pricePerShare > 1, depositing with asset amount of 1 will be reverted due to minting 0 shares.
        assetInAmount = bound(assetInAmount, 2, 10_000e18);

        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_ETH_YFI_GAUGE;

        uint256[] memory sharesOut = router.previewDeposits(path, assetInAmount);
        assertEq(sharesOut.length, 2);

        airdrop(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), address(router), assetInAmount, false);
        router.approve(ERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), MAINNET_ETH_YFI_VAULT_V2, assetInAmount);

        // Deposit to the vault
        uint256 expectedVaultSharesOut =
            router.deposit(IYearn4626(MAINNET_ETH_YFI_VAULT_V2), assetInAmount, address(router), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(address(router)), expectedVaultSharesOut);
        router.approve(ERC20(MAINNET_ETH_YFI_VAULT_V2), MAINNET_ETH_YFI_GAUGE, expectedVaultSharesOut);

        // Deposit to the gauge
        uint256 expectedGaugeSharesOut =
            router.deposit(IYearn4626(MAINNET_ETH_YFI_GAUGE), expectedVaultSharesOut, user, 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(user), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(user), expectedGaugeSharesOut);

        // Verify the previewed sharesOut amount matches the actual sharesOut amount
        assertEq(sharesOut[0], expectedVaultSharesOut);
        assertEq(sharesOut[1], expectedGaugeSharesOut);
    }

    function test_previewDeposits_v2Vault() public {
        uint256 assetInAmount = 1e6;
        address[] memory path = new address[](2);
        path[0] = MAINNET_USDC;
        path[1] = MAINNET_YVUSDC_VAULT_V2;

        uint256[] memory sharesOut = router.previewDeposits(path, assetInAmount);
        assertEq(sharesOut.length, 1);
        assertEq(sharesOut[0], 944_890);
    }

    function test_previewDeposits_revertWhen_PreviewPathIsTooShort() public {
        uint256 assetInAmount = 1 ether;
        address[] memory path = new address[](1);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;

        vm.expectRevert(Yearn4626RouterExt.PreviewPathIsTooShort.selector);
        router.previewDeposits(path, assetInAmount);
    }

    function test_previewDeposits_revertWhen_PreviewNonVaultAddressInPath() public {
        uint256 assetInAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_YFI; // Use non 4626 address for the test

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.PreviewNonVaultAddressInPath.selector, MAINNET_YFI));
        router.previewDeposits(path, assetInAmount);
    }

    function test_previewDeposits_revertWhen_InvalidVaultInPath_NotAContract() public {
        uint256 assetInAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = address(0); // Use non 4626 address for the test

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.PreviewNonVaultAddressInPath.selector, address(0)));
        router.previewDeposits(path, assetInAmount);
    }

    function test_previewDeposits_revertWhen_PreviewVaultMismatch() public {
        uint256 assetInAmount = 1 ether;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_CRV_YCRV_GAUGE; // Intentional mismatch for the test

        vm.expectRevert(Yearn4626RouterExt.PreviewVaultMismatch.selector);
        router.previewDeposits(path, assetInAmount);
    }

    function testFuzz_previewMints(uint256 shareOutAmount) public {
        shareOutAmount = bound(shareOutAmount, 1, 10_000e18);

        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_ETH_YFI_GAUGE;

        uint256[] memory assetsIn = router.previewMints(path, shareOutAmount);
        assertEq(assetsIn.length, 2);

        airdrop(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), address(router), assetsIn[0], false);
        // Deposit the returned assetIn amount to the vault
        router.approve(ERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN), MAINNET_ETH_YFI_VAULT_V2, assetsIn[0]);
        uint256 actualVaultShareAmount =
            router.deposit(IYearn4626(MAINNET_ETH_YFI_VAULT_V2), assetsIn[0], address(router), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(address(router)), actualVaultShareAmount);
        // Confirm the actual share amount is equal to the expected share amount
        assertEq(assetsIn[1], actualVaultShareAmount);
        // Deposit the return assetIn amount to the gauge
        router.approve(ERC20(MAINNET_ETH_YFI_VAULT_V2), MAINNET_ETH_YFI_GAUGE, assetsIn[1]);
        uint256 actualGaugeShareAmount = router.deposit(IYearn4626(MAINNET_ETH_YFI_GAUGE), assetsIn[1], user, 0);
        // Confirm the final share amount is equal to the expected share amount
        assertEq(actualGaugeShareAmount, shareOutAmount);
    }

    function test_previewMints_Multiple4626() public {
        ERC20Mock baseAsset = new ERC20Mock();
        ERC4626Mock mock1 = new ERC4626Mock(address(baseAsset));
        ERC4626Mock mock2 = new ERC4626Mock(address(mock1));
        ERC4626Mock mock3 = new ERC4626Mock(address(mock2));

        baseAsset.mint(address(this), 10e18);
        baseAsset.approve(address(mock1), 10e18);
        mock1.approve(address(mock2), 10e18);
        mock2.approve(address(mock3), 10e18);

        mock1.deposit(2e18, address(this));
        baseAsset.transfer(address(mock1), 1e18);

        mock2.deposit(1e18, address(this));
        mock1.transfer(address(mock2), 1e18);

        mock3.deposit(0.5e18, address(this));
        mock2.transfer(address(mock3), 0.5e18);

        uint256 expectedAssetIn2 = mock3.previewMint(1e18);
        uint256 expectedAssetIn1 = mock2.previewMint(expectedAssetIn2);
        uint256 expectedBaseAssetIn = mock1.previewMint(expectedAssetIn1);

        assertEq(expectedBaseAssetIn, 5_999_999_999_999_999_995);
        assertEq(expectedAssetIn1, 3_999_999_999_999_999_997);
        assertEq(expectedAssetIn2, 1_999_999_999_999_999_999);

        address[] memory path = new address[](4);
        path[0] = address(baseAsset);
        path[1] = address(mock1);
        path[2] = address(mock2);
        path[3] = address(mock3);

        uint256[] memory assetsIn = router.previewMints(path, 1e18);
        assertEq(assetsIn.length, 3);
        assertEq(assetsIn[0], expectedBaseAssetIn);
        assertEq(assetsIn[1], expectedAssetIn1);
        assertEq(assetsIn[2], expectedAssetIn2);
    }

    function test_previewMints_v2Vault() public {
        uint256 assetInAmount = 1e6;
        address[] memory path = new address[](2);
        path[0] = MAINNET_USDC;
        path[1] = MAINNET_YVUSDC_VAULT_V2;

        uint256[] memory assetsIn = router.previewMints(path, assetInAmount);
        assertEq(assetsIn.length, 1);
        assertEq(assetsIn[0], 1_058_324);
    }

    function test_previewMints_revertWhen_PreviewPathIsTooShort() public {
        uint256 shareOutAmount = 949_289_266_142_683_599;
        address[] memory path = new address[](1);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;

        vm.expectRevert(Yearn4626RouterExt.PreviewPathIsTooShort.selector);
        router.previewMints(path, shareOutAmount);
    }

    function test_previewMints_revertWhen_PreviewNonVaultAddressInPath() public {
        uint256 shareOutAmount = 949_289_266_142_683_599;
        address[] memory path = new address[](2);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_YFI; // Use non 4626 address for the test

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.PreviewNonVaultAddressInPath.selector, MAINNET_YFI));
        router.previewMints(path, shareOutAmount);
    }

    function test_previewMints_revertWhen_InvalidVaultInPath_NotAContract() public {
        uint256 shareOutAmount = 949_289_266_142_683_599;
        address[] memory path = new address[](2);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = address(0); // Use non 4626 address for the test

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.PreviewNonVaultAddressInPath.selector, address(0)));
        router.previewMints(path, shareOutAmount);
    }

    function test_previewMints_revertWhen_PreviewVaultMismatch() public {
        uint256 shareOutAmount = 949_289_266_142_683_599;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_POOL_LP_TOKEN;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_CRV_YCRV_GAUGE; // Intentional mismatch for the test

        vm.expectRevert(Yearn4626RouterExt.PreviewVaultMismatch.selector);
        router.previewMints(path, shareOutAmount);
    }

    function test_previewWithdraws() public {
        uint256 assetOutAmount = 1e18;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_ETH_YFI_POOL_LP_TOKEN;

        uint256[] memory sharesIn = router.previewWithdraws(path, assetOutAmount);
        assertEq(sharesIn.length, 2);
        assertEq(sharesIn[0], 949_289_266_142_683_600);
        assertEq(sharesIn[1], 949_289_266_142_683_600);

        // Redeem shares and verify the preview result matches the actual result
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), address(router), sharesIn[0], false);
        uint256 vaultShares = router.redeemFromRouter(IERC4626(MAINNET_ETH_YFI_GAUGE), sharesIn[0], address(router), 0);
        assertEq(vaultShares, sharesIn[1]);
        uint256 lpShares =
            router.redeemVaultV2(IYearnVaultV2(MAINNET_ETH_YFI_VAULT_V2), vaultShares, address(router), 0);
        assertEq(lpShares, assetOutAmount);
    }

    function testFuzz_previewWithdraws(uint256 assetOut) public {
        // Bound the assetOut amount to the max asset out amount
        // This is the total amount of the underlying LP token that can be withdrawn by the total supply amount of the
        // gauge.
        uint256 maxAssetOut =
            IYearnVaultV2(MAINNET_ETH_YFI_VAULT_V2).previewRedeem(IERC4626(MAINNET_ETH_YFI_GAUGE).totalAssets());
        assertEq(maxAssetOut, 128_760_754_733_967_560_587);
        assetOut = bound(assetOut, 1, maxAssetOut);

        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_ETH_YFI_POOL_LP_TOKEN;

        uint256[] memory sharesIn = router.previewWithdraws(path, assetOut);
        assertEq(sharesIn.length, 2);

        // Redeem the returned sharesIn amount of gauge tokens
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), address(router), sharesIn[0], false);
        uint256 vaultShares = router.redeemFromRouter(IERC4626(MAINNET_ETH_YFI_GAUGE), sharesIn[0], address(router), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(address(router)), vaultShares);
        assertEq(sharesIn[1], vaultShares, "sharesIn[1] should be equal to vaultShares");
        // Redeem the returned sharesIn amount of vault tokens
        uint256 actualAssetOut =
            router.redeemVaultV2(IYearnVaultV2(MAINNET_ETH_YFI_VAULT_V2), vaultShares, address(router), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN).balanceOf(address(router)), actualAssetOut);
        // In some cases, the actual asset out you get back is greater than the previewed asset out
        // due to the way Yearn Vault v2 calculates the share price.
        // At most this is off by 1, in favor of the vault.
        assertApproxEqAbs(
            assetOut, actualAssetOut, 1, "finalAssetOut should be approximately equal to previewed assetOut"
        );
        assertLe(assetOut, actualAssetOut, "finalAssetOut should be greater than or equal to previewed assetOut");
    }

    function test_previewWithdraws_Multiple4626() public {
        // asset to vault flow:
        // baseAsset -> mock1 -> mock2 -> mock3
        ERC20Mock baseAsset = new ERC20Mock();
        ERC4626Mock mock1 = new ERC4626Mock(address(baseAsset));
        ERC4626Mock mock2 = new ERC4626Mock(address(mock1));
        ERC4626Mock mock3 = new ERC4626Mock(address(mock2));

        baseAsset.mint(address(this), 10e18);
        baseAsset.approve(address(mock1), 10e18);
        mock1.approve(address(mock2), 10e18);
        mock2.approve(address(mock3), 10e18);

        mock1.deposit(2e18, address(this));
        baseAsset.transfer(address(mock1), 1e18);

        mock2.deposit(1e18, address(this));
        mock1.transfer(address(mock2), 1e18);

        mock3.deposit(0.5e18, address(this));
        mock2.transfer(address(mock3), 0.5e18);

        uint256 expectedShareIn1 = mock1.previewWithdraw(1e18);
        uint256 expectedShareIn2 = mock2.previewWithdraw(expectedShareIn1);
        uint256 expectedShareIn3 = mock3.previewWithdraw(expectedShareIn2);

        assertEq(expectedShareIn3, 166_666_666_666_666_668);
        assertEq(expectedShareIn2, 333_333_333_333_333_334);
        assertEq(expectedShareIn1, 666_666_666_666_666_667);

        address[] memory path = new address[](4);
        path[0] = address(mock3);
        path[1] = address(mock2);
        path[2] = address(mock1);
        path[3] = address(baseAsset);

        uint256[] memory sharesIn = router.previewWithdraws(path, 1e18);
        assertEq(sharesIn.length, 3);
        assertEq(sharesIn[0], expectedShareIn3);
        assertEq(sharesIn[1], expectedShareIn2);
        assertEq(sharesIn[2], expectedShareIn1);
    }

    function test_previewWithdraws_v2Vault() public {
        uint256 assetInAmount = 1e6;
        address[] memory path = new address[](2);
        path[0] = MAINNET_YVUSDC_VAULT_V2;
        path[1] = MAINNET_USDC;

        uint256[] memory sharesOut = router.previewWithdraws(path, assetInAmount);
        assertEq(sharesOut.length, 1);
        assertEq(sharesOut[0], 944_891);
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

    function test_previewWithdraws_revertWhen_PreviewPathIsTooShort() public {
        uint256 assetOutAmount = 1 ether;
        address[] memory path = new address[](1);
        path[0] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(Yearn4626RouterExt.PreviewPathIsTooShort.selector);
        router.previewWithdraws(path, assetOutAmount);
    }

    function test_previewWithdraws_revertWhen_PreviewNonVaultAddressInPath() public {
        uint256 assetOutAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = MAINNET_YFI; // Use non 4626 address for the test
        path[1] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.PreviewNonVaultAddressInPath.selector, MAINNET_YFI));
        router.previewWithdraws(path, assetOutAmount);
    }

    function test_previewWithdraws_revertWhen_InvalidVaultInPath_NotAContract() public {
        uint256 assetOutAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = address(0); // Use non 4626 address for the test
        path[1] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.PreviewNonVaultAddressInPath.selector, address(0)));
        router.previewWithdraws(path, assetOutAmount);
    }

    function test_previewWithdraws_revertWhen_PreviewVaultMismatch() public {
        uint256 assetOutAmount = 1 ether;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_CRV_YCRV_GAUGE; // Intentional mismatch for the test

        vm.expectRevert(Yearn4626RouterExt.PreviewVaultMismatch.selector);
        router.previewWithdraws(path, assetOutAmount);
    }

    function testFuzz_previewRedeems(uint256 shareInAmount) public {
        // Bound share in amount [1, totalSupply]
        shareInAmount = bound(shareInAmount, 1, IERC20(MAINNET_ETH_YFI_GAUGE).totalSupply());

        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_ETH_YFI_POOL_LP_TOKEN;

        (uint256[] memory assetsOut) = router.previewRedeems(path, shareInAmount);
        assertEq(assetsOut.length, 2);

        // Redeem gauge shares
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), address(router), shareInAmount, false);
        uint256 expectedVaultTokenOut =
            router.redeemFromRouter(IERC4626(MAINNET_ETH_YFI_GAUGE), shareInAmount, address(router), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_GAUGE).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(address(router)), expectedVaultTokenOut);
        // Redeem VaultV2 shares
        uint256 expectedLPTokenOut =
            router.redeemVaultV2(IYearnVaultV2(MAINNET_ETH_YFI_VAULT_V2), expectedVaultTokenOut, address(router), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_VAULT_V2).balanceOf(address(router)), 0);
        assertEq(IERC20(MAINNET_ETH_YFI_POOL_LP_TOKEN).balanceOf(address(router)), expectedLPTokenOut);

        // Verify the previewed assetsOut amount matches the actual assetsOut amount
        assertEq(assetsOut[0], expectedVaultTokenOut);
        assertEq(assetsOut[1], expectedLPTokenOut);
    }

    function test_previewRedeems_v2Vault() public {
        uint256 assetInAmount = 1e6;
        address[] memory path = new address[](2);
        path[0] = MAINNET_YVUSDC_VAULT_V2;
        path[1] = MAINNET_USDC;

        uint256[] memory sharesOut = router.previewRedeems(path, assetInAmount);
        assertEq(sharesOut.length, 1);
        assertEq(sharesOut[0], 1_058_323);
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

    function test_previewRedeems_revertWhen_PreviewPathIsTooShort() public {
        uint256 shareInAmount = 1 ether;
        address[] memory path = new address[](1);
        path[0] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(Yearn4626RouterExt.PreviewPathIsTooShort.selector);
        router.previewRedeems(path, shareInAmount);
    }

    function test_previewRedeems_revertWhen_PreviewNonVaultAddressInPath() public {
        uint256 shareInAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = MAINNET_YFI; // Use non 4626 address for the test
        path[1] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.PreviewNonVaultAddressInPath.selector, MAINNET_YFI));
        router.previewRedeems(path, shareInAmount);
    }

    function test_previewRedeems_revertWhen_PreviewNonVaultAddressInPath_NotAContract() public {
        uint256 shareInAmount = 1 ether;
        address[] memory path = new address[](2);
        path[0] = address(0); // Use non 4626 address for the test
        path[1] = MAINNET_ETH_YFI_GAUGE;

        vm.expectRevert(abi.encodeWithSelector(Yearn4626RouterExt.PreviewNonVaultAddressInPath.selector, address(0)));
        router.previewRedeems(path, shareInAmount);
    }

    function test_previewRedeems_revertWhen_PreviewVaultMismatch() public {
        uint256 shareInAmount = 1 ether;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_CRV_YCRV_GAUGE; // Intentional mismatch for the test

        vm.expectRevert(Yearn4626RouterExt.PreviewVaultMismatch.selector);
        router.previewRedeems(path, shareInAmount);
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
            Yearn4626RouterBase.deposit.selector,
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
        assertEq(abi.decode(ret[3], (uint256)), 949_289_266_142_683_599, "deposit should return minted shares");
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
            Yearn4626RouterBase.deposit.selector,
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

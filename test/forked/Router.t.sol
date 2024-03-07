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
        uint256 assetOutAmount = 1 ether;
        address[] memory path = new address[](3);
        path[0] = MAINNET_ETH_YFI_GAUGE;
        path[1] = MAINNET_ETH_YFI_VAULT_V2;
        path[2] = MAINNET_ETH_YFI_POOL_LP_TOKEN;

        uint256[] memory sharesIn = router.previewWithdraws(path, assetOutAmount);
        assertEq(sharesIn.length, 2);
        assertEq(sharesIn[0], 1 ether);
        assertEq(sharesIn[1], 949_289_266_142_683_599);
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
        assertEq(assetsOut[1], 1 ether);
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

    function test_pullTokensWithPermit2() public {
        uint256 depositAmount = 1 ether;
        airdrop(IERC20(MAINNET_ETH_YFI_GAUGE), user, depositAmount);
        // Yearn gauge does not support permit signing, therefore we must use Permit2
        // User's one time max approve Permit2.
        vm.prank(user);
        IERC20(MAINNET_ETH_YFI_GAUGE).approve(MAINNET_PERMIT2, _MAX_UINT256);

        ISignatureTransfer.PermitTransferFrom memory permit =
            _getPermit2PermitTransferFrom(MAINNET_ETH_YFI_GAUGE, depositAmount, 0, block.timestamp + 100);

        bytes memory signature = _getPermit2PermitTransferSignature(
            permit, address(router), userPriv, ISignatureTransfer(MAINNET_PERMIT2).DOMAIN_SEPARATOR()
        );

        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            _getPerit2SignatureTransferDetails(address(router), depositAmount);
        vm.prank(user);
        router.pullTokensWithPermit2(permit, transferDetails, signature);
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

        ISignatureTransfer.PermitTransferFrom memory permit =
            _getPermit2PermitTransferFrom(MAINNET_ETH_YFI_GAUGE, depositAmount, 0, block.timestamp + 100);

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

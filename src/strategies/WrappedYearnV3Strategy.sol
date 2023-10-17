// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import { BaseTokenizedStrategy } from "src/deps/yearn/tokenized-strategy/BaseTokenizedStrategy.sol";
import { IVault } from "src/interfaces/deps/yearn/yearn-vaults-v3/IVault.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Errors } from "../libraries/Errors.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";

contract WrappedYearnV3Strategy is BaseTokenizedStrategy, CurveRouterSwapper {
    // Libraries
    using SafeERC20 for IERC20Metadata;

    // Immutable storage variables
    address public immutable vault;
    address public immutable yearnStakingDelegate;
    address public immutable dYFI;

    // Storage variables
    CurveSwapParams internal _harvestSwapParams;

    constructor(
        address _asset,
        address _vault,
        address _yearnStakingDelegate,
        address _dYFI,
        address _curveRouter
    )
        BaseTokenizedStrategy(_asset, "Wrapped YearnV3 Strategy")
        CurveRouterSwapper(_curveRouter)
    {
        // Checks
        // Check for zero addresses
        if (_asset == address(0) || _vault == address(0) || _yearnStakingDelegate == address(0) || _dYFI == address(0))
        {
            revert Errors.ZeroAddress();
        }
        // Check if the given asset is the same as the given vault's asset
        if (_asset != IVault(_vault).asset()) {
            revert Errors.VaultAssetDiffers();
        }

        // Effects
        // Set storage variable values
        vault = _vault;
        dYFI = _dYFI;
        yearnStakingDelegate = _yearnStakingDelegate;

        // Interactions
        _approveTokenForSwap(_dYFI);
        IERC20Metadata(_asset).approve(_vault, type(uint256).max);
        IERC20Metadata(_vault).approve(_yearnStakingDelegate, type(uint256).max);
    }

    function setHarvestSwapParams(CurveSwapParams memory curveSwapParams) external onlyManagement {
        // Checks (includes external view calls)
        _validateSwapParams(curveSwapParams, dYFI, asset);

        // effects
        _harvestSwapParams = curveSwapParams;
    }

    function _deployFunds(uint256 _amount) internal virtual override {
        // deposit _amount into vault
        address _vault = vault;
        uint256 shares = IVault(_vault).deposit(_amount, address(this));
        IYearnStakingDelegate(yearnStakingDelegate).depositToGauge(_vault, shares);
    }

    function _freeFunds(uint256 _amount) internal override {
        // withdraw _amount from gauge through yearn staking delegate
        address _vault = vault;
        uint256 assetDecimals = TokenizedStrategy.decimals();
        IYearnStakingDelegate _yearnStakingDelegate = IYearnStakingDelegate(yearnStakingDelegate);
        // Find percentage of total assets in this amount
        uint256 allocation = _amount * assetDecimals / TokenizedStrategy.totalAssets();
        // Total vault shares that wStrat has deposited into ysd
        uint256 totalUnderlyingVaultShares = uint256(_yearnStakingDelegate.userInfo(address(this), _vault).balance);
        // Find withdrawer's allocation of total ysd shares
        uint256 vaultSharesToWithdraw = totalUnderlyingVaultShares * allocation / assetDecimals;
        // Withdraw from gauge via YSD
        _yearnStakingDelegate.withdrawFromGauge(_vault, vaultSharesToWithdraw);
        // Withdraw from vault using redeem
        uint256 _withdrawnVaultAssetAmount = IVault(_vault).redeem(vaultSharesToWithdraw, address(this), address(this));
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        address _vault = vault;
        address _ysd = yearnStakingDelegate;
        // ysd.harvest() <- harvests gauge rewards (dFYI) and transfers them to this contract
        uint256 dYFIBalance = IYearnStakingDelegate(_ysd).harvest(_vault);
        // swap dYFI -> ETH -> vaultAsset if rewards were harvested

        if (dYFIBalance > 0) {
            uint256 receivedTokens = _swap(_harvestSwapParams, dYFIBalance, 0, address(this));
            // TODO: decide if funds should be deployed if the strategy is shutdown
            // if (!TokenizedStrategy.isShutdown()) {
            //     _deployFunds(ERC20(asset).balanceOf(address(this)));
            // }

            // redploy the harvestest rewards into the strategy
            _deployFunds(receivedTokens);
        }

        // TODO: below may not be accurate accounting as the underlying vault may not have realized gains/losses
        // additionally profits may have been awarded but not fully unlocked yet, these are concerns to be investigated
        // off-chain by management in the timing of calling _harvestAndReportvi
        return IVault(_vault).convertToAssets(IYearnStakingDelegate(_ysd).userInfo(address(this), _vault).balance);
    }
}

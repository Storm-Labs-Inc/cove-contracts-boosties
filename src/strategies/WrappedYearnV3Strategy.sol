// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { BaseStrategy } from "@tokenized-strategy/BaseStrategy.sol";
import { IStakingDelegateRewards } from "src/interfaces/deps/yearn/veYFI/IStakingDelegateRewards.sol";
import { IGauge } from "src/interfaces/deps/yearn/veYFI/IGauge.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { CurveRouterSwapper } from "src/swappers/CurveRouterSwapper.sol";
import { WrappedYearnV3 } from "./WrappedYearnV3.sol";
import { IYearnStakingDelegate } from "src/interfaces/IYearnStakingDelegate.sol";
import { Errors } from "src/libraries/Errors.sol";

contract WrappedYearnV3Strategy is BaseStrategy, CurveRouterSwapper, WrappedYearnV3 {
    // Libraries
    using SafeERC20 for IERC20;

    // slither-disable-start naming-convention
    address internal immutable _VAULT_ASSET;
    address internal immutable _VAULT;
    // slither-disable-end naming-convention

    CurveSwapParams internal _harvestSwapParams;

    constructor(
        address _asset,
        address _yearnStakingDelegate,
        address _dYFI,
        address _curveRouter
    )
        BaseStrategy(_asset, "Wrapped YearnV3 Strategy")
        CurveRouterSwapper(_curveRouter)
        WrappedYearnV3(_asset, _yearnStakingDelegate, _dYFI)
    {
        address vault = IGauge(_asset).asset();
        address vaultAsset = IERC4626(vault).asset();

        // Checks
        // Check for zero addresses
        if (vault == address(0) || vaultAsset == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Effects
        // Assume asset is yearn gauge
        address _vault = IGauge(_asset).asset();
        address _vaultAsset = IERC4626(_vault).asset();
        _VAULT = _vault;
        _VAULT_ASSET = _vaultAsset;

        // Interactions
        _approveTokenForSwap(_dYFI);
        IERC20(_vaultAsset).forceApprove(_vault, type(uint256).max);

        IERC20(_vault).forceApprove(_asset, type(uint256).max);
    }

    function setHarvestSwapParams(CurveSwapParams memory curveSwapParams) external virtual onlyManagement {
        // Checks (includes external view calls)
        _validateSwapParams(curveSwapParams, dYfi(), _VAULT_ASSET);

        // Effects
        _harvestSwapParams = curveSwapParams;
    }

    function _deployFunds(uint256 _amount) internal virtual override {
        _depositToYSD(TokenizedStrategy.asset(), _amount);
    }

    function _freeFunds(uint256 _amount) internal override {
        _withdrawFromYSD(TokenizedStrategy.asset(), _amount);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // Get any dYFI rewards
        address _asset = address(asset);
        address stakingDelegateRewards = IYearnStakingDelegate(yearnStakingDelegate()).gaugeStakingRewards(_asset);
        uint256 dYFIBalance = IStakingDelegateRewards(stakingDelegateRewards).getReward(_asset);
        uint256 newIdleBalance = 0;
        // If dYFI was received, swap it for vault asset
        if (dYFIBalance > 0) {
            uint256 receivedBaseTokens = _swap(_harvestSwapParams, dYFIBalance, 0, address(this));
            uint256 receivedVaultTokens = IERC4626(_VAULT).deposit(receivedBaseTokens, address(this));
            uint256 receivedGaugeTokens = IERC4626(_asset).deposit(receivedVaultTokens, address(this));

            // If the strategy is not shutdown, deploy the funds
            // Else add the received tokens to the idle balance
            if (!TokenizedStrategy.isShutdown()) {
                _deployFunds(receivedGaugeTokens);
            } else {
                // todo: do we return vault tokens or gauge
                newIdleBalance = receivedGaugeTokens;
            }
        }
        // TODO: below may not be accurate accounting as the underlying vault may not have realized gains/losses
        // additionally profits may have been awarded but not fully unlocked yet, these are concerns to be investigated
        // off-chain by management in the timing of calling _harvestAndReport
        return newIdleBalance + IYearnStakingDelegate(yearnStakingDelegate()).balances(_asset, address(this));
    }

    function vault() public view returns (address) {
        return _VAULT;
    }

    function vaultAsset() public view returns (address) {
        return _VAULT_ASSET;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { BaseRewardsGauge } from "src/rewards/BaseRewardsGauge.sol";
import { YSDRewardsGauge } from "src/rewards/YSDRewardsGauge.sol";
import { RewardForwarder } from "src/rewards/RewardForwarder.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IYearnVaultV2 } from "src/interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Errors } from "src/libraries/Errors.sol";

/**
 * @title Cove Yearn Gauge Factory
 * @notice Factory contract to deploy and manage Yearn gauge-related contracts for Cove protocol.
 * @dev This contract allows for the creation of Yearn gauge strategies, auto-compounding gauges, and
 * non-auto-compounding gauges.
 * It also manages the reward forwarder implementations and various administrative roles.
 */
contract CoveYearnGaugeFactory is AccessControl {
    struct GaugeInfoStored {
        address coveYearnStrategy;
        address autoCompoundingGauge;
        address nonAutoCompoundingGauge;
    }

    struct GaugeInfo {
        /// @dev The address of the yearn vault asset. Usually a curve LP token.
        address yearnVaultAsset;
        /// @dev The address of the yearn vault. Uses yearn vault asset as the depositing asset.
        address yearnVault;
        /// @dev The boolean flag to indicate if the yearn vault is a v2 vault.
        bool isVaultV2;
        /// @dev The address of the yearn gauge. Uses yearn vault as the depositing asset.
        address yearnGauge;
        /// @dev The address of the cove's yearn strategy. Uses yearn gauge as the depositing asset.
        address coveYearnStrategy;
        /// @dev The address of the auto-compounding gauge. Uses cove's yearn strategy as the depositing asset.
        address autoCompoundingGauge;
        /// @dev The address of the non-auto-compounding gauge. Uses yearn gauge as the depositing asset.
        address nonAutoCompoundingGauge;
    }

    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");
    address private constant _DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    // slither-disable-start naming-convention
    address public immutable YEARN_STAKING_DELEGATE;
    address public immutable COVE;
    // slither-disable-end naming-convention
    address public rewardForwarderImpl;
    address public baseRewardsGaugeImpl;
    address public ysdRewardsGaugeImpl;
    address public treasuryMultisig;
    address public gaugeAdmin;

    address[] public supportedYearnGauges;
    mapping(address => GaugeInfoStored) public yearnGaugeInfoStored;

    event CoveGaugesDeployed(
        address yearnGauge, address coveYearnStrategy, address autoCompoundingGauge, address nonAutoCompoundingGauge
    );

    /**
     * @dev Initializes the factory with the necessary contract implementations and administrative roles.
     * @param factoryAdmin The address that will be granted the factory admin role.
     * @param ysd The address of the Yearn staking delegate.
     * @param cove The address of the Cove token.
     * @param rewardForwarderImpl_ The implementation address of the RewardForwarder contract.
     * @param baseRewardsGaugeImpl_ The implementation address of the BaseRewardsGauge contract.
     * @param ysdRewardsGaugeImpl_ The implementation address of the YSDRewardsGauge contract.
     * @param treasuryMultisig_ The address of the treasury multisig.
     * @param gaugeAdmin_ The address that will be granted the gauge admin role.
     */
    // slither-disable-next-line locked-ether
    constructor(
        address factoryAdmin,
        address ysd,
        address cove,
        address rewardForwarderImpl_,
        address baseRewardsGaugeImpl_,
        address ysdRewardsGaugeImpl_,
        address treasuryMultisig_,
        address gaugeAdmin_
    )
        payable
    {
        if (ysd == address(0) || cove == address(0)) revert Errors.ZeroAddress();
        YEARN_STAKING_DELEGATE = ysd;
        COVE = cove;
        _setRewardForwarderImplementation(rewardForwarderImpl_);
        _setBaseRewardsGaugeImplementation(baseRewardsGaugeImpl_);
        _setYsdRewardsGaugeImplementation(ysdRewardsGaugeImpl_);
        _setTreasuryMultisig(treasuryMultisig_);
        _setGaugeAdmin(gaugeAdmin_);
        _grantRole(DEFAULT_ADMIN_ROLE, factoryAdmin);
        _grantRole(_MANAGER_ROLE, factoryAdmin);
    }

    /**
     * @notice Returns the number of supported Yearn gauges.
     * @return The count of supported Yearn gauges.
     */
    function numOfSupportedYearnGauges() external view returns (uint256) {
        return supportedYearnGauges.length;
    }

    /**
     * @notice Retrieves information for all supported Yearn gauges.
     * @return An array of GaugeInfo structs containing details for each supported Yearn gauge.
     */
    function getAllGaugeInfo() external view returns (GaugeInfo[] memory) {
        uint256 length = supportedYearnGauges.length;
        GaugeInfo[] memory result = new GaugeInfo[](length);
        for (uint256 i = 0; i < length; ++i) {
            result[i] = getGaugeInfo(supportedYearnGauges[i]);
        }
        return result;
    }

    /**
     * @notice Retrieves information for a specific Yearn gauge.
     * @dev Fetches gauge information from storage and attempts to determine the vault asset and version.
     * @param yearnGauge The address of the Yearn gauge to retrieve information for.
     * @return A GaugeInfo struct containing details for the specified Yearn gauge.
     */
    function getGaugeInfo(address yearnGauge) public view returns (GaugeInfo memory) {
        // slither-disable-start calls-loop
        GaugeInfoStored memory stored = yearnGaugeInfoStored[yearnGauge];
        address coveYearnStrategy = stored.coveYearnStrategy;
        if (coveYearnStrategy == address(0)) {
            revert Errors.GaugeNotDeployed();
        }
        address yearnVault = IERC4626(yearnGauge).asset();
        address yearnVaultAsset = address(0);
        bool isYearnVaultV2 = false;
        try IERC4626(yearnVault).asset() returns (address vaultAsset) {
            yearnVaultAsset = vaultAsset;
        } catch {
            isYearnVaultV2 = true;
            yearnVaultAsset = IYearnVaultV2(yearnVault).token();
        }
        return GaugeInfo({
            yearnVaultAsset: yearnVaultAsset,
            yearnVault: yearnVault,
            isVaultV2: isYearnVaultV2,
            yearnGauge: yearnGauge,
            coveYearnStrategy: coveYearnStrategy,
            autoCompoundingGauge: stored.autoCompoundingGauge,
            nonAutoCompoundingGauge: stored.nonAutoCompoundingGauge
        });
        // slither-disable-end calls-loop
    }

    /**
     * @notice Deploys Cove gauges for a given Yearn strategy.
     * @dev Creates new instances of auto-compounding and non-auto-compounding gauges, initializes them, and sets up
     * reward forwarders.
     * @param coveYearnStrategy The address of the Cove Yearn strategy for which to deploy gauges.
     */
    function deployCoveGauges(address coveYearnStrategy) external onlyRole(_MANAGER_ROLE) {
        // Sanity check
        if (coveYearnStrategy == address(0)) {
            revert Errors.ZeroAddress();
        }
        address yearnGauge = IERC4626(coveYearnStrategy).asset();
        // Check if the gauges are already deployed
        if (yearnGaugeInfoStored[yearnGauge].coveYearnStrategy != address(0)) {
            revert Errors.GaugeAlreadyDeployed();
        }
        // Cache storage vars as memory vars
        address gaugeAdmin_ = gaugeAdmin;
        address rewardForwarderImpl_ = rewardForwarderImpl;
        address treasuryMultisig_ = treasuryMultisig;

        // Deploy both gauges
        BaseRewardsGauge coveStratGauge = BaseRewardsGauge(Clones.clone(baseRewardsGaugeImpl));
        YSDRewardsGauge coveYsdGauge = YSDRewardsGauge(Clones.clone(ysdRewardsGaugeImpl));

        // Save the gauge info
        supportedYearnGauges.push(yearnGauge);
        yearnGaugeInfoStored[yearnGauge] = GaugeInfoStored({
            coveYearnStrategy: coveYearnStrategy,
            autoCompoundingGauge: address(coveStratGauge),
            nonAutoCompoundingGauge: address(coveYsdGauge)
        });

        // Emit the event
        emit CoveGaugesDeployed(yearnGauge, coveYearnStrategy, address(coveStratGauge), address(coveYsdGauge));

        // Initialize the auto-compounding gauge
        coveStratGauge.initialize(coveYearnStrategy);
        // Deploy and initialize the reward forwarder for the auto-compounding gauge
        {
            RewardForwarder forwarder = RewardForwarder(Clones.clone(rewardForwarderImpl_));
            forwarder.initialize({
                admin_: gaugeAdmin_,
                treasury_: treasuryMultisig_,
                destination_: address(coveStratGauge)
            });
            forwarder.approveRewardToken(COVE);
            // Add COVE reward to the auto-compounding gauge
            coveStratGauge.addReward(COVE, address(forwarder));
            // Replace admin and manager for the auto-compounding gauge
            coveStratGauge.grantRole(DEFAULT_ADMIN_ROLE, gaugeAdmin_);
            coveStratGauge.grantRole(_MANAGER_ROLE, gaugeAdmin_);
            coveStratGauge.renounceRole(DEFAULT_ADMIN_ROLE, address(this));
            coveStratGauge.renounceRole(_MANAGER_ROLE, address(this));
        }

        // Initialize the non-auto-compounding gauge
        coveYsdGauge.initialize(yearnGauge, YEARN_STAKING_DELEGATE, coveYearnStrategy);
        // Deploy and initialize the reward forwarder for the non-auto-compounding gauge
        {
            RewardForwarder forwarder = RewardForwarder(Clones.clone(rewardForwarderImpl_));
            forwarder.initialize({
                admin_: gaugeAdmin_,
                treasury_: treasuryMultisig_,
                destination_: address(coveYsdGauge)
            });
            forwarder.approveRewardToken(_DYFI);
            forwarder.approveRewardToken(COVE);
            // Set the dYFI rewards to be received by the reward forwarder
            coveYsdGauge.setStakingDelegateRewardsReceiver(address(forwarder));
            // Add dYFI and COVE rewards to the non-auto-compounding gauge
            coveYsdGauge.addReward(COVE, address(forwarder));
            coveYsdGauge.addReward(_DYFI, address(forwarder));
            // Replace admin and manager for the non-auto-compounding gauge
            coveYsdGauge.grantRole(DEFAULT_ADMIN_ROLE, gaugeAdmin_);
            coveYsdGauge.grantRole(_MANAGER_ROLE, gaugeAdmin_);
            coveYsdGauge.renounceRole(DEFAULT_ADMIN_ROLE, address(this));
            coveYsdGauge.renounceRole(_MANAGER_ROLE, address(this));
        }
    }

    /**
     * @notice Sets the implementation address for the RewardForwarder contract.
     * @dev Can only be called by the admin role. Reverts if the new implementation address is the zero address.
     * @param impl The new implementation address for the RewardForwarder contract.
     */
    function setRewardForwarderImplementation(address impl) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRewardForwarderImplementation(impl);
    }

    /**
     * @notice Sets the implementation address for the YSDRewardsGauge contract.
     * @dev Can only be called by the admin role. Reverts if the new implementation address is the zero address.
     * @param impl The new implementation address for the YSDRewardsGauge contract.
     */
    function setYsdRewardsGaugeImplementation(address impl) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setYsdRewardsGaugeImplementation(impl);
    }

    /**
     * @notice Sets the treasury multisig address.
     * @dev Can only be called by the admin role. Reverts if the new treasury multisig address is the zero address.
     * @param multisig The new treasury multisig address.
     */
    function setTreasuryMultisig(address multisig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTreasuryMultisig(multisig);
    }

    /**
     * @notice Sets the implementation address for the BaseRewardsGauge contract.
     * @dev Can only be called by the admin role. Reverts if the new implementation address is the zero address.
     * @param impl The new implementation address for the BaseRewardsGauge contract.
     */
    function setBaseRewardsGaugeImplementation(address impl) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBaseRewardsGaugeImplementation(impl);
    }

    /**
     * @notice Sets the gauge admin address.
     * @dev Can only be called by the admin role. Reverts if the new gauge admin address is the zero address.
     * @param admin The new gauge admin address.
     */
    function setGaugeAdmin(address admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setGaugeAdmin(admin);
    }

    function _setRewardForwarderImplementation(address impl) internal {
        if (impl == address(0)) {
            revert Errors.ZeroAddress();
        }
        rewardForwarderImpl = impl;
    }

    function _setBaseRewardsGaugeImplementation(address impl) internal {
        if (impl == address(0)) {
            revert Errors.ZeroAddress();
        }
        baseRewardsGaugeImpl = impl;
    }

    function _setTreasuryMultisig(address multisig) internal {
        if (multisig == address(0)) {
            revert Errors.ZeroAddress();
        }
        treasuryMultisig = multisig;
    }

    function _setYsdRewardsGaugeImplementation(address impl) internal {
        if (impl == address(0)) {
            revert Errors.ZeroAddress();
        }
        ysdRewardsGaugeImpl = impl;
    }

    function _setGaugeAdmin(address admin) internal {
        if (admin == address(0)) {
            revert Errors.ZeroAddress();
        }
        gaugeAdmin = admin;
    }
}

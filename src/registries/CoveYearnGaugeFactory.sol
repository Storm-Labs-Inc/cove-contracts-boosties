// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20RewardsGauge } from "src/rewards/ERC20RewardsGauge.sol";
import { YSDRewardsGauge } from "src/rewards/YSDRewardsGauge.sol";
import { RewardForwarder } from "src/rewards/RewardForwarder.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IYearnVaultV2 } from "src/interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Errors } from "src/libraries/Errors.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";

/**
 * @title Cove Yearn Gauge Factory
 * @notice Factory contract to deploy and manage Yearn gauge-related contracts for Cove protocol.
 * @dev This contract allows for the creation of Yearn gauge strategies, auto-compounding gauges, and
 * non-auto-compounding gauges.
 * It also manages the reward forwarder implementations and various administrative roles.
 */
contract CoveYearnGaugeFactory is AccessControlEnumerable, Multicall {
    struct GaugeInfoStored {
        /// @dev Address of the Cove Yearn Strategy contract interacting with Yearn Gauge.
        address coveYearnStrategy;
        /// @dev Address of the auto-compounding gauge contract for automatic reward reinvestment.
        address autoCompoundingGauge;
        /// @dev Address of the non-auto-compounding gauge contract allowing manual reward claims.
        address nonAutoCompoundingGauge;
    }

    struct GaugeInfo {
        /// @dev Address of the yearn vault asset (e.g. Curve LP tokens) for depositing into Yearn Vault.
        address yearnVaultAsset;
        /// @dev Address of the Yearn Vault accepting yearn vault asset as deposit.
        address yearnVault;
        /// @dev Boolean indicating if Yearn Vault is a version 2 vault.
        bool isVaultV2;
        /// @dev Address of the Yearn Gauge accepting Yearn Vault as deposit asset.
        address yearnGauge;
        /// @dev Address of the Cove's Yearn Strategy using Yearn Gauge as deposit asset.
        address coveYearnStrategy;
        /// @dev Address of the auto-compounding gauge using Cove's Yearn Strategy for deposits.
        address autoCompoundingGauge;
        /// @dev Address of the non-auto-compounding gauge using Yearn Gauge for deposits and manual rewards.
        address nonAutoCompoundingGauge;
    }

    /// @dev Role identifier for the manager role, used for privileged functions.
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @dev Role identifier for the pauser role, used to pause certain contract functionalities.
    bytes32 private constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @dev Address of the DYFI token, used within the contract for various functionalities.
    address private constant _DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    // slither-disable-start naming-convention
    /// @notice Address of the Yearn Staking Delegate, immutable for the lifetime of the contract.
    address public immutable YEARN_STAKING_DELEGATE;
    /// @notice Address of the COVE token, immutable for the lifetime of the contract.
    address public immutable COVE;
    // slither-disable-end naming-convention
    /// @notice Address of the current Reward Forwarder implementation.
    address public rewardForwarderImpl;
    /// @notice Address of the current ERC20 Rewards Gauge implementation.
    address public erc20RewardsGaugeImpl;
    /// @notice Address of the current YSD Rewards Gauge implementation.
    address public ysdRewardsGaugeImpl;
    /// @notice Address of the treasury.
    address public treasuryMultisig;
    /// @notice Address of the account with gauge admin privileges.
    address public gaugeAdmin;
    /// @notice Address of the account with gauge management privileges.
    address public gaugeManager;
    /// @notice Address of the account with gauge pausing privileges.
    address public gaugePauser;

    /// @notice Array of addresses for supported Yearn Gauges.
    address[] public supportedYearnGauges;
    /// @notice Mapping of Yearn Gauge addresses to their stored information.
    mapping(address => GaugeInfoStored) public yearnGaugeInfoStored;

    /**
     * @notice Event emitted when Cove gauges are deployed.
     * @param yearnGauge Address of the Yearn Gauge.
     * @param coveYearnStrategy Address of the Cove Yearn Strategy.
     * @param autoCompoundingGauge Address of the auto-compounding gauge.
     * @param nonAutoCompoundingGauge Address of the non-auto-compounding gauge.
     */
    event CoveGaugesDeployed(
        address indexed yearnGauge,
        address indexed coveYearnStrategy,
        address indexed autoCompoundingGauge,
        address nonAutoCompoundingGauge
    );

    /**
     * @dev Initializes the factory with the necessary contract implementations and administrative roles.
     * @param factoryAdmin The address that will be granted the factory admin role.
     * @param ysd The address of the Yearn staking delegate.
     * @param cove The address of the Cove token.
     * @param rewardForwarderImpl_ The implementation address of the RewardForwarder contract.
     * @param erc20RewardsGaugeImpl_ The implementation address of the ERC20RewardsGauge contract.
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
        address erc20RewardsGaugeImpl_,
        address ysdRewardsGaugeImpl_,
        address treasuryMultisig_,
        address gaugeAdmin_,
        address gaugeManager_,
        address gaugePauser_
    )
        payable
    {
        if (ysd == address(0) || cove == address(0)) revert Errors.ZeroAddress();
        YEARN_STAKING_DELEGATE = ysd;
        COVE = cove;
        _setRewardForwarderImplementation(rewardForwarderImpl_);
        _setERC20RewardsGaugeImplementation(erc20RewardsGaugeImpl_);
        _setYsdRewardsGaugeImplementation(ysdRewardsGaugeImpl_);
        _setTreasuryMultisig(treasuryMultisig_);
        _setGaugeAdmin(gaugeAdmin_);
        _setGaugeManager(gaugeManager_);
        _setGaugePauser(gaugePauser_);
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
     * @dev The usage of the limit and offset parameters matches the same pattern found in pagination/SQL queries.
     * @param limit The maximum number of gauges to fetch information for.
     * @param offset The starting gauge index to retrieve data from.
     * @return An array of GaugeInfo structs containing details for each supported Yearn gauge.
     */
    function getAllGaugeInfo(uint256 limit, uint256 offset) external view returns (GaugeInfo[] memory) {
        address[] memory gauges = supportedYearnGauges;
        uint256 numGauges = gauges.length;
        // Handle the case of offset + limit exceeding the remaining length by taking the min.
        // If the offset is >= the number of gauges there are no results to return.
        uint256 length = offset >= numGauges ? 0 : Math.min(limit, numGauges - offset);
        GaugeInfo[] memory result = new GaugeInfo[](length);
        for (uint256 i = offset; i < length;) {
            result[i] = getGaugeInfo(gauges[i]);

            /// @dev The unchecked block is used here because the loop index `i` is simply incremented in each
            /// iteration, ensuring that `i` will not exceed the length of the array and cause an overflow. Underflow is
            /// not a concern as `i` is initialized to 0 and only incremented.
            unchecked {
                ++i;
            }
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
        address gaugeManager_ = gaugeManager;
        address gaugePauser_ = gaugePauser;
        address rewardForwarderImpl_ = rewardForwarderImpl;
        address treasuryMultisig_ = treasuryMultisig;

        // Deploy both gauges
        ERC20RewardsGauge coveStratGauge = ERC20RewardsGauge(Clones.clone(erc20RewardsGaugeImpl));
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
            coveStratGauge.grantRole(_MANAGER_ROLE, gaugeManager_);
            coveStratGauge.grantRole(_PAUSER_ROLE, gaugePauser_);
            coveStratGauge.renounceRole(DEFAULT_ADMIN_ROLE, address(this));
            coveStratGauge.renounceRole(_MANAGER_ROLE, address(this));
            coveStratGauge.renounceRole(_PAUSER_ROLE, address(this));
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
            coveYsdGauge.grantRole(_MANAGER_ROLE, gaugeManager_);
            coveYsdGauge.grantRole(_PAUSER_ROLE, gaugePauser_);
            coveYsdGauge.renounceRole(DEFAULT_ADMIN_ROLE, address(this));
            coveYsdGauge.renounceRole(_MANAGER_ROLE, address(this));
            coveYsdGauge.renounceRole(_PAUSER_ROLE, address(this));
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
     * @notice Sets the implementation address for the ERC20RewardsGauge contract.
     * @dev Can only be called by the admin role. Reverts if the new implementation address is the zero address.
     * @param impl The new implementation address for the ERC20RewardsGauge contract.
     */
    function setERC20RewardsGaugeImplementation(address impl) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setERC20RewardsGaugeImplementation(impl);
    }

    /**
     * @notice Sets the gauge admin address.
     * @dev Can only be called by the admin role. Reverts if the new gauge admin address is the zero address.
     * @param admin The new gauge admin address.
     */
    function setGaugeAdmin(address admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setGaugeAdmin(admin);
    }

    /**
     * @notice Sets the gauge manager address.
     * @dev Can only be called by the admin role. Reverts if the new gauge manager address is the zero address.
     * @param manager The new gauge manager address.
     */
    function setGaugeManager(address manager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setGaugeManager(manager);
    }

    /**
     * @notice Sets the gauge pauser address.
     * @dev Can only be called by the admin role. Reverts if the new gauge pauser address is the zero address.
     * @param pauser The new gauge pauser address.
     */
    function setGaugePauser(address pauser) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setGaugePauser(pauser);
    }

    function _setRewardForwarderImplementation(address impl) internal {
        if (impl == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (!Address.isContract(impl)) {
            revert Errors.AddressNotContract();
        }
        rewardForwarderImpl = impl;
    }

    function _setERC20RewardsGaugeImplementation(address impl) internal {
        if (impl == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (!Address.isContract(impl)) {
            revert Errors.AddressNotContract();
        }
        erc20RewardsGaugeImpl = impl;
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
        if (!Address.isContract(impl)) {
            revert Errors.AddressNotContract();
        }
        ysdRewardsGaugeImpl = impl;
    }

    function _setGaugeAdmin(address admin) internal {
        if (admin == address(0)) {
            revert Errors.ZeroAddress();
        }
        gaugeAdmin = admin;
    }

    function _setGaugeManager(address manager) internal {
        if (manager == address(0)) {
            revert Errors.ZeroAddress();
        }
        gaugeManager = manager;
    }

    function _setGaugePauser(address pauser) internal {
        if (pauser == address(0)) {
            revert Errors.ZeroAddress();
        }
        gaugePauser = pauser;
    }
}

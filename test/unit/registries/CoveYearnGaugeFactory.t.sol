// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { CoveYearnGaugeFactory } from "src/registries/CoveYearnGaugeFactory.sol";
import { ERC20RewardsGauge, BaseRewardsGauge } from "src/rewards/ERC20RewardsGauge.sol";
import { YSDRewardsGauge } from "src/rewards/YSDRewardsGauge.sol";
import { RewardForwarder } from "src/rewards/RewardForwarder.sol";
import { MockStakingDelegateRewards } from "test/mocks/MockStakingDelegateRewards.sol";
import { MockYearnStakingDelegate } from "test/mocks/MockYearnStakingDelegate.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { ERC4626Mock, IERC4626 } from "@openzeppelin/contracts/mocks/ERC4626Mock.sol";
import { IYearnVaultV2 } from "src/interfaces/deps/yearn/veYFI/IYearnVaultV2.sol";
import { Errors } from "src/libraries/Errors.sol";

contract CoveYearnGaugeFactory_Test is BaseTest {
    CoveYearnGaugeFactory public factory;
    BaseRewardsGauge public erc20RewardsGaugeImpl;
    YSDRewardsGauge public ysdRewardsGaugeImpl;
    RewardForwarder public rewardForwarderImpl;
    MockYearnStakingDelegate public mockYearnStakingDelegate;
    MockStakingDelegateRewards public mockStakingDelegateRewards;
    ERC20Mock public cove;
    ERC20Mock public yearnVaultAsset;
    ERC4626Mock public yearnVaultV2;
    ERC4626Mock public yearnVaultV3;
    ERC4626Mock public yearnGaugeV2;
    ERC4626Mock public yearnGaugeV3;
    ERC4626Mock public mockCoveYearnStrategyV2;
    ERC4626Mock public mockCoveYearnStrategyV3;

    address public treasuryMultisig;
    address public gaugeAdmin;

    bytes32 public MANAGER_ROLE = keccak256("MANAGER_ROLE");

    function setUp() public override {
        cove = new ERC20Mock();
        vm.etch(MAINNET_DYFI, address(new ERC20Mock()).code);

        erc20RewardsGaugeImpl = new ERC20RewardsGauge();
        ysdRewardsGaugeImpl = new YSDRewardsGauge();
        rewardForwarderImpl = new RewardForwarder();
        mockYearnStakingDelegate = new MockYearnStakingDelegate();
        mockStakingDelegateRewards = new MockStakingDelegateRewards(MAINNET_DYFI);
        mockYearnStakingDelegate.setGaugeStakingRewards(address(mockStakingDelegateRewards));

        yearnVaultAsset = new ERC20Mock();
        // To mimic v2 vault, revert asset() call and pass token() call
        yearnVaultV2 = new ERC4626Mock(address(yearnVaultAsset));
        vm.mockCall(
            address(yearnVaultV2), abi.encodeWithSelector(IYearnVaultV2.token.selector), abi.encode(yearnVaultAsset)
        );
        vm.mockCallRevert(address(yearnVaultV2), abi.encodeWithSelector(IERC4626.asset.selector), "");
        yearnVaultV3 = new ERC4626Mock(address(yearnVaultAsset));
        yearnGaugeV2 = new ERC4626Mock(address(yearnVaultV2));
        yearnGaugeV3 = new ERC4626Mock(address(yearnVaultV3));
        mockCoveYearnStrategyV2 = new ERC4626Mock(address(yearnGaugeV2));
        mockCoveYearnStrategyV3 = new ERC4626Mock(address(yearnGaugeV3));

        treasuryMultisig = createUser("treasuryMultisig");
        gaugeAdmin = createUser("gaugeAdmin");

        factory = new CoveYearnGaugeFactory({
            factoryAdmin: address(this),
            ysd: address(mockYearnStakingDelegate),
            cove: address(cove),
            rewardForwarderImpl_: address(rewardForwarderImpl),
            erc20RewardsGaugeImpl_: address(erc20RewardsGaugeImpl),
            ysdRewardsGaugeImpl_: address(ysdRewardsGaugeImpl),
            treasuryMultisig_: treasuryMultisig,
            gaugeAdmin_: gaugeAdmin
        });
    }

    function test_constructor() public {
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(factory.hasRole(MANAGER_ROLE, address(this)));
        assertEq(factory.YEARN_STAKING_DELEGATE(), address(mockYearnStakingDelegate));
        assertEq(factory.COVE(), address(cove));
        assertEq(factory.rewardForwarderImpl(), address(rewardForwarderImpl));
        assertEq(factory.erc20RewardsGaugeImpl(), address(erc20RewardsGaugeImpl));
        assertEq(factory.ysdRewardsGaugeImpl(), address(ysdRewardsGaugeImpl));
        assertEq(factory.treasuryMultisig(), treasuryMultisig);
        assertEq(factory.gaugeAdmin(), gaugeAdmin);
    }

    function test_deployCoveGauges() public {
        factory.deployCoveGauges(address(mockCoveYearnStrategyV2));
        factory.deployCoveGauges(address(mockCoveYearnStrategyV3));

        CoveYearnGaugeFactory.GaugeInfo memory v2GaugeInfo = factory.getGaugeInfo(address(yearnGaugeV2));
        CoveYearnGaugeFactory.GaugeInfo memory v3GaugeInfo = factory.getGaugeInfo(address(yearnGaugeV3));
        assertEq(factory.numOfSupportedYearnGauges(), 2, "numOfSupportedYearnGauges");
        assertEq(v2GaugeInfo.yearnVaultAsset, address(yearnVaultAsset), "v2GaugeInfo.yearnVaultAsset");
        assertEq(v2GaugeInfo.yearnVault, address(yearnVaultV2), "v2GaugeInfo.yearnVault");
        assertTrue(v2GaugeInfo.isVaultV2, "v2GaugeInfo.isVaultV2");
        assertEq(v2GaugeInfo.yearnGauge, address(yearnGaugeV2), "v2GaugeInfo.yearnGauge");
        assertEq(v2GaugeInfo.coveYearnStrategy, address(mockCoveYearnStrategyV2), "v2GaugeInfo.coveYearnStrategy");
        assertFalse(v2GaugeInfo.autoCompoundingGauge == address(0), "v2GaugeInfo.autoCompoundingGauge");
        assertFalse(v2GaugeInfo.nonAutoCompoundingGauge == address(0), "v2GaugeInfo.nonAutoCompoundingGauge");

        assertEq(v3GaugeInfo.yearnVaultAsset, address(yearnVaultAsset), "v3GaugeInfo.yearnVaultAsset");
        assertEq(v3GaugeInfo.yearnVault, address(yearnVaultV3), "v3GaugeInfo.yearnVault");
        assertFalse(v3GaugeInfo.isVaultV2, "v3GaugeInfo.isVaultV2");
        assertEq(v3GaugeInfo.yearnGauge, address(yearnGaugeV3), "v3GaugeInfo.yearnGauge");
        assertEq(v3GaugeInfo.coveYearnStrategy, address(mockCoveYearnStrategyV3), "v3GaugeInfo.coveYearnStrategy");
        assertFalse(v3GaugeInfo.autoCompoundingGauge == address(0), "v3GaugeInfo.autoCompoundingGauge");
        assertFalse(v3GaugeInfo.nonAutoCompoundingGauge == address(0), "v3GaugeInfo.nonAutoCompoundingGauge");

        CoveYearnGaugeFactory.GaugeInfo[] memory allGaugeInfo = factory.getAllGaugeInfo(2, 0);
        assertEq(allGaugeInfo.length, 2, "allGaugeInfo.length");
        assertEq(abi.encode(allGaugeInfo[0]), abi.encode(v2GaugeInfo), "allGaugeInfo[0]==v2GaugeInfo");
        assertEq(abi.encode(allGaugeInfo[1]), abi.encode(v3GaugeInfo), "allGaugeInfo[1]==v3GaugeInfo");
    }

    function test_getAllGaugeInfo() public {
        factory.deployCoveGauges(address(mockCoveYearnStrategyV2));

        // 0 offset, limit matches the number of gauges
        CoveYearnGaugeFactory.GaugeInfo[] memory allGaugeInfo = factory.getAllGaugeInfo(1, 0);
        assertEq(allGaugeInfo.length, 1, "allGaugeInfo.length");

        // 0 offset, limit exceeds the number of gauges
        allGaugeInfo = factory.getAllGaugeInfo(2, 0);
        assertEq(allGaugeInfo.length, 1, "allGaugeInfo.length");

        // 1 offset, limit is 1 but there is only 1 gauge at the 0 index
        allGaugeInfo = factory.getAllGaugeInfo(1, 1);
        assertEq(allGaugeInfo.length, 0, "allGaugeInfo.length");

        factory.deployCoveGauges(address(mockCoveYearnStrategyV3));

        // non 0 offset, limit matches the number of gauges
        allGaugeInfo = factory.getAllGaugeInfo(1, 1);
        assertEq(allGaugeInfo.length, 1, "allGaugeInfo.length");

        // non 0 offset, limit exceeds the number of gauges
        allGaugeInfo = factory.getAllGaugeInfo(2, 1);
        assertEq(allGaugeInfo.length, 1, "allGaugeInfo.length");

        // offset exceeds the number of gauges
        allGaugeInfo = factory.getAllGaugeInfo(1, 3);
        assertEq(allGaugeInfo.length, 0, "allGaugeInfo.length");
    }

    function testFuzz_getAllGaugeInfo(uint256 limit, uint256 offset) public {
        factory.deployCoveGauges(address(mockCoveYearnStrategyV2));
        CoveYearnGaugeFactory.GaugeInfo[] memory allGaugeInfo = factory.getAllGaugeInfo(limit, offset);
        // only case where we expect the single gauge's info to be returned
        if (offset == 0 && limit >= 1) {
            assertEq(allGaugeInfo.length, 1, "allGaugeInfo.length");
        } else {
            assertEq(allGaugeInfo.length, 0, "allGaugeInfo.length");
        }
    }

    function test_deployCoveGauges_revertWhen_notManager() public {
        factory.revokeRole(MANAGER_ROLE, address(this));
        vm.expectRevert(_formatAccessControlError(address(this), MANAGER_ROLE));
        factory.deployCoveGauges(address(mockCoveYearnStrategyV2));
    }

    function test_deployCoveGauges_revertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        factory.deployCoveGauges(address(0));
    }

    function test_deployCoveGauges_revertWhen_GaugeAlreadyDeployed() public {
        factory.deployCoveGauges(address(mockCoveYearnStrategyV2));
        vm.expectRevert(Errors.GaugeAlreadyDeployed.selector);
        factory.deployCoveGauges(address(mockCoveYearnStrategyV2));
    }

    function test_setRewardForwarderImplementation() public {
        RewardForwarder newRewardForwarderImpl = new RewardForwarder();
        factory.setRewardForwarderImplementation(address(newRewardForwarderImpl));
        assertEq(factory.rewardForwarderImpl(), address(newRewardForwarderImpl));
    }

    function test_setRewardForwarderImplementation_revertWhen_notAdmin() public {
        RewardForwarder newRewardForwarderImpl = new RewardForwarder();
        factory.revokeRole(factory.DEFAULT_ADMIN_ROLE(), address(this));
        vm.expectRevert(_formatAccessControlError(address(this), factory.DEFAULT_ADMIN_ROLE()));
        factory.setRewardForwarderImplementation(address(newRewardForwarderImpl));
    }

    function test_setRewardForwarderImplementation_revertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        factory.setRewardForwarderImplementation(address(0));
    }

    function test_setBaseRewardsGaugeImplementation() public {
        ERC20RewardsGauge newBaseRewardsGaugeImpl = new ERC20RewardsGauge();
        factory.setERC20RewardsGaugeImplementation(address(newBaseRewardsGaugeImpl));
        assertEq(factory.erc20RewardsGaugeImpl(), address(newBaseRewardsGaugeImpl));
    }

    function test_setBaseRewardsGaugeImplementation_revertWhen_notAdmin() public {
        ERC20RewardsGauge newBaseRewardsGaugeImpl = new ERC20RewardsGauge();
        factory.revokeRole(factory.DEFAULT_ADMIN_ROLE(), address(this));
        vm.expectRevert(_formatAccessControlError(address(this), factory.DEFAULT_ADMIN_ROLE()));
        factory.setERC20RewardsGaugeImplementation(address(newBaseRewardsGaugeImpl));
    }

    function test_setBaseRewardsGaugeImplementation_revertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        factory.setERC20RewardsGaugeImplementation(address(0));
    }

    function test_setYsdRewardsGaugeImplementation() public {
        YSDRewardsGauge newYsdRewardsGaugeImpl = new YSDRewardsGauge();
        factory.setYsdRewardsGaugeImplementation(address(newYsdRewardsGaugeImpl));
        assertEq(factory.ysdRewardsGaugeImpl(), address(newYsdRewardsGaugeImpl));
    }

    function test_setYsdRewardsGaugeImplementation_revertWhen_notAdmin() public {
        YSDRewardsGauge newYsdRewardsGaugeImpl = new YSDRewardsGauge();
        factory.revokeRole(factory.DEFAULT_ADMIN_ROLE(), address(this));
        vm.expectRevert(_formatAccessControlError(address(this), factory.DEFAULT_ADMIN_ROLE()));
        factory.setYsdRewardsGaugeImplementation(address(newYsdRewardsGaugeImpl));
    }

    function test_setYsdRewardsGaugeImplementation_revertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        factory.setYsdRewardsGaugeImplementation(address(0));
    }

    function test_setTreasuryMultisig() public {
        address newTreasuryMultisig = createUser("newTreasuryMultisig");
        factory.setTreasuryMultisig(newTreasuryMultisig);
        assertEq(factory.treasuryMultisig(), newTreasuryMultisig);
    }

    function test_setTreasuryMultisig_revertWhen_notAdmin() public {
        address newTreasuryMultisig = createUser("newTreasuryMultisig");
        factory.revokeRole(factory.DEFAULT_ADMIN_ROLE(), address(this));
        vm.expectRevert(_formatAccessControlError(address(this), factory.DEFAULT_ADMIN_ROLE()));
        factory.setTreasuryMultisig(newTreasuryMultisig);
    }

    function test_setTreasuryMultisig_revertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        factory.setTreasuryMultisig(address(0));
    }

    function test_getGaugeInfo_revertWhen_GaugeNotDeployed(address gauge) public {
        vm.assume(gauge != address(yearnGaugeV2));
        factory.deployCoveGauges(address(mockCoveYearnStrategyV2));
        vm.expectRevert(Errors.GaugeNotDeployed.selector);
        factory.getGaugeInfo(address(gauge));
    }

    function test_setGaugeAdmin() public {
        address newGaugeAdmin = createUser("newAdmin");
        factory.setGaugeAdmin(newGaugeAdmin);
        assertEq(factory.gaugeAdmin(), newGaugeAdmin);
    }

    function test_setGaugeAdmin_revertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        factory.setGaugeAdmin(address(0));
    }
}

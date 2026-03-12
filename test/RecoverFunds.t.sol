// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IService} from "../contracts/interfaces/IService.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeProxy} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import {MultiSend} from "@gnosis.pm/safe-contracts/contracts/libraries/MultiSend.sol";
import {DefaultCallbackHandler} from "@gnosis.pm/safe-contracts/contracts/handler/DefaultCallbackHandler.sol";
import {Test} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {ERC20Token} from "../contracts/test/ERC20Token.sol";
import {GnosisSafeMultisig} from "../contracts/multisigs/GnosisSafeMultisig.sol";
import {SafeMultisigWithRecoveryModule} from "../contracts/multisigs/SafeMultisigWithRecoveryModule.sol";
import {RecoveryModule} from "../contracts/multisigs/RecoveryModule.sol";
import {ServiceRegistryL2} from "../contracts/ServiceRegistryL2.sol";
import {ServiceRegistryTokenUtility} from "../contracts/ServiceRegistryTokenUtility.sol";
import {ServiceManager} from "../contracts/ServiceManager.sol";
import {ServiceManagerProxy} from "../contracts/ServiceManagerProxy.sol";
import {MockIdentityRegistry} from "../contracts/test/MockIdentityRegistry.sol";
import {IdentityRegistryBridger} from "../contracts/8004/IdentityRegistryBridger.sol";
import {IdentityRegistryBridgerProxy} from "../contracts/8004/IdentityRegistryBridgerProxy.sol";
import {StakingNativeToken} from "../contracts/staking/StakingNativeToken.sol";
import {StakingBase, ServiceInfo} from "../contracts/staking/StakingBase.sol";
import {StakingActivityChecker} from "../contracts/staking/StakingActivityChecker.sol";

/// @title RecoverFundsTest - Tests the fund recovery flow matching the recover_funds.py script
/// @notice This test reproduces the exact setup described in the recovery planning doc:
///         Master EOA -> Master Safe -> RecoveryModule.recoverAccess() -> fund recovery via Agent Safe
contract RecoverFundsTest is Test {
    Utils internal utils;

    // Contracts
    ServiceRegistryL2 internal serviceRegistry;
    ServiceRegistryTokenUtility internal serviceRegistryTokenUtility;
    ServiceManager internal serviceManager;
    GnosisSafe internal gnosisSafe;
    GnosisSafeProxyFactory internal gnosisSafeProxyFactory;
    GnosisSafeMultisig internal gnosisSafeMultisig;
    SafeMultisigWithRecoveryModule internal safeMultisigWithRecoveryModule;
    RecoveryModule internal recoveryModule;
    MultiSend internal multiSend;
    DefaultCallbackHandler internal defaultCallbackHandler;
    ERC20Token internal tokenOLAS;
    ERC20Token internal tokenUSDC;

    // Addresses
    address payable[] internal users;
    address internal deployer;
    address internal operator;
    uint256 internal masterEOAPk;
    address internal masterEOA;
    address internal backupOwner;
    address internal agentInstance;

    // Master Safe and Agent Safe
    GnosisSafe internal masterSafe;
    GnosisSafe internal agentSafe;

    // Service params
    uint256 internal serviceId = 1;
    uint32 internal threshold = 1;
    uint96 internal regBond = 10 ether;
    uint256 internal regDeposit = 10 ether;
    bytes32 internal unitHash = 0x9999999999999999999999999999999999999999999999999999999999999999;
    bytes internal payload;

    function setUp() public {
        utils = new Utils();
        users = utils.createUsers(10);
        deployer = users[0];
        operator = users[1];
        agentInstance = users[2];
        backupOwner = users[3];

        // Create master EOA with known private key
        masterEOAPk = 0xA11CE;
        masterEOA = vm.addr(masterEOAPk);
        vm.deal(masterEOA, 100 ether);

        // Deploy core contracts
        serviceRegistry = new ServiceRegistryL2("Service Registry L2", "SERVICE", "https://localhost/service/");
        serviceRegistryTokenUtility = new ServiceRegistryTokenUtility(address(serviceRegistry));

        serviceManager = new ServiceManager(address(serviceRegistry), address(serviceRegistryTokenUtility));
        bytes memory proxyData = abi.encodeWithSelector(serviceManager.initialize.selector, "");
        ServiceManagerProxy serviceManagerProxy = new ServiceManagerProxy(address(serviceManager), proxyData);
        serviceManager = ServiceManager(address(serviceManagerProxy));

        serviceRegistry.changeManager(address(serviceManager));
        serviceRegistryTokenUtility.changeManager(address(serviceManager));

        // Deploy identity registry components (required by ServiceManager)
        MockIdentityRegistry identityRegistry = new MockIdentityRegistry();
        IdentityRegistryBridger identityRegistryBridger = new IdentityRegistryBridger(
            address(identityRegistry), address(serviceRegistry)
        );
        proxyData = abi.encodeWithSelector(identityRegistryBridger.initialize.selector, "");
        IdentityRegistryBridgerProxy identityRegistryBridgerProxy =
            new IdentityRegistryBridgerProxy(address(identityRegistryBridger), proxyData);
        identityRegistryBridger = IdentityRegistryBridger(address(identityRegistryBridgerProxy));
        serviceManager.setIdentityRegistryBridger(address(identityRegistryBridger));

        // Deploy Safe infrastructure
        gnosisSafe = new GnosisSafe();
        gnosisSafeProxyFactory = new GnosisSafeProxyFactory();
        gnosisSafeMultisig = new GnosisSafeMultisig(payable(address(gnosisSafe)), address(gnosisSafeProxyFactory));
        multiSend = new MultiSend();
        defaultCallbackHandler = new DefaultCallbackHandler();

        // Deploy recovery module
        recoveryModule = new RecoveryModule(address(multiSend), address(serviceRegistry));

        // Deploy SafeMultisigWithRecoveryModule (creates Safe with recovery module enabled)
        safeMultisigWithRecoveryModule = new SafeMultisigWithRecoveryModule(
            payable(address(gnosisSafe)), address(gnosisSafeProxyFactory), address(recoveryModule)
        );

        // Whitelist multisig implementations
        serviceRegistry.changeMultisigPermission(address(safeMultisigWithRecoveryModule), true);

        // Deploy ERC20 tokens
        tokenOLAS = new ERC20Token();
        tokenUSDC = new ERC20Token();

        // --- Create Master Safe (with masterEOA + backupOwner, threshold=1) ---
        address[] memory masterOwners = new address[](2);
        masterOwners[0] = masterEOA;
        masterOwners[1] = backupOwner;

        bytes memory masterSetupData = abi.encodeWithSelector(
            GnosisSafe.setup.selector,
            masterOwners,       // owners
            1,                  // threshold
            address(0),         // to
            "",                 // data
            address(defaultCallbackHandler), // fallbackHandler
            address(0),         // paymentToken
            0,                  // payment
            payable(address(0)) // paymentReceiver
        );

        GnosisSafeProxy masterSafeProxy = gnosisSafeProxyFactory.createProxyWithNonce(
            address(gnosisSafe), masterSetupData, 0
        );
        masterSafe = GnosisSafe(payable(address(masterSafeProxy)));

        // Verify Master Safe setup
        assertEq(masterSafe.getThreshold(), 1);
        address[] memory owners = masterSafe.getOwners();
        assertEq(owners.length, 2);

        // --- Create service owned by Master Safe ---
        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 1;
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = regBond;

        // ServiceManager.create uses msg.sender as manager, so we call from deployer (who is the manager owner)
        serviceManager.create(
            address(masterSafe),                    // owner = Master Safe
            serviceManager.ETH_TOKEN_ADDRESS(),     // token
            unitHash,                               // configHash
            agentIds,
            agentParams,
            threshold
        );

        // Verify service owner is Master Safe
        assertEq(serviceRegistry.ownerOf(serviceId), address(masterSafe));

        // --- Activate registration (Master Safe calls via Master EOA) ---
        _execMasterSafeTx(
            address(serviceManager),
            regDeposit,
            abi.encodeWithSelector(ServiceManager.activateRegistration.selector, serviceId)
        );

        // --- Register agent instance (operator) ---
        address[] memory instances = new address[](1);
        instances[0] = agentInstance;
        vm.prank(operator);
        serviceManager.registerAgents{value: regBond}(serviceId, instances, agentIds);

        // --- Deploy service (Master Safe calls via Master EOA) ---
        // This creates the Agent Safe with recovery module enabled
        _execMasterSafeTx(
            address(serviceManager),
            0,
            abi.encodeWithSelector(
                ServiceManager.deploy.selector,
                serviceId,
                address(safeMultisigWithRecoveryModule),
                payload
            )
        );

        // Get the Agent Safe address
        (, address multisig, , , , , ) = serviceRegistry.mapServices(serviceId);
        agentSafe = GnosisSafe(payable(multisig));

        // Verify Agent Safe is owned by agentInstance
        address[] memory agentOwners = agentSafe.getOwners();
        assertEq(agentOwners.length, 1);
        assertEq(agentOwners[0], agentInstance);

        // --- Fund Agent Safe with ERC20 tokens and native tokens ---
        tokenOLAS.mint(address(agentSafe), 1000 ether);
        tokenUSDC.mint(address(agentSafe), 5000 ether);
        vm.deal(address(agentSafe), 2 ether);

        // --- Terminate service (Master Safe calls via Master EOA) ---
        _execMasterSafeTx(
            address(serviceManager),
            0,
            abi.encodeWithSelector(ServiceManager.terminate.selector, serviceId)
        );

        // --- Unbond (operator) ---
        vm.prank(operator);
        serviceManager.unbond(serviceId);

        // Verify service is in PreRegistration state (1)
        (, , , , , , ServiceRegistryL2.ServiceState state) = serviceRegistry.mapServices(serviceId);
        assertEq(uint8(state), 1); // PreRegistration
    }

    // -----------------------------------------------------------------------
    // Helper: Execute a transaction on Master Safe signed by Master EOA
    // -----------------------------------------------------------------------
    function _execMasterSafeTx(address to, uint256 value, bytes memory data) internal {
        _execSafeTxWithEOA(masterSafe, masterEOAPk, to, value, data, Enum.Operation.Call);
    }

    function _execSafeTxWithEOA(
        GnosisSafe safe,
        uint256 signerPk,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal {
        uint256 nonce = safe.nonce();

        bytes32 txHash = safe.getTransactionHash(
            to, value, data, operation,
            0, 0, 0,
            address(0), payable(address(0)),
            nonce
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, txHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(vm.addr(signerPk));
        safe.execTransaction{value: value}(
            to, value, data, operation,
            0, 0, 0,
            address(0), payable(address(0)),
            signature
        );
    }

    // -----------------------------------------------------------------------
    // Helper: Build v=1 sender-approved signature for Safe owner
    // -----------------------------------------------------------------------
    function _buildApprovedOwnerSignature(address owner) internal pure returns (bytes memory) {
        // r = owner address padded to 32 bytes, s = 0, v = 1
        return abi.encodePacked(bytes12(0), owner, bytes32(0), uint8(1));
    }

    // -----------------------------------------------------------------------
    // Helper: Encode a single tx for MultiSend packed format
    // -----------------------------------------------------------------------
    function _encodeMultiSendTx(
        Enum.Operation operation,
        address to,
        uint256 value,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(operation), to, value, data.length, data);
    }

    // -----------------------------------------------------------------------
    // Test: Full recovery flow matching recover_funds.py
    // -----------------------------------------------------------------------
    function test_recoverAccess_and_transferFunds() public {
        // --- Step 1: Verify Agent Safe is NOT owned by Master Safe yet ---
        address[] memory agentOwners = agentSafe.getOwners();
        assertTrue(agentOwners.length != 1 || agentOwners[0] != address(masterSafe));

        // --- Step 2: Recovery - Master EOA -> Master Safe -> recoverAccess(serviceId) ---
        _execMasterSafeTx(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(RecoveryModule.recoverAccess.selector, serviceId)
        );

        // Verify Master Safe is now the sole owner of Agent Safe
        agentOwners = agentSafe.getOwners();
        assertEq(agentOwners.length, 1);
        assertEq(agentOwners[0], address(masterSafe));
        assertEq(agentSafe.getThreshold(), 1);

        // --- Step 3: Build Agent Safe multicall to transfer all tokens ---
        // Record balances before
        uint256 olasBalance = tokenOLAS.balanceOf(address(agentSafe));
        uint256 usdcBalance = tokenUSDC.balanceOf(address(agentSafe));
        uint256 nativeBalance = address(agentSafe).balance;

        assertGt(olasBalance, 0);
        assertGt(usdcBalance, 0);
        assertGt(nativeBalance, 0);

        // Build individual transfer calldata
        bytes memory olasTransfer = abi.encodeWithSelector(
            bytes4(keccak256("transfer(address,uint256)")), address(masterSafe), olasBalance
        );
        bytes memory usdcTransfer = abi.encodeWithSelector(
            bytes4(keccak256("transfer(address,uint256)")), address(masterSafe), usdcBalance
        );

        // Pack transfers into MultiSend format
        bytes memory multiSendData = abi.encodePacked(
            _encodeMultiSendTx(Enum.Operation.Call, address(tokenOLAS), 0, olasTransfer),
            _encodeMultiSendTx(Enum.Operation.Call, address(tokenUSDC), 0, usdcTransfer),
            _encodeMultiSendTx(Enum.Operation.Call, address(masterSafe), nativeBalance, "")
        );

        // Encode multiSend call
        bytes memory agentSafeInnerData = abi.encodeWithSelector(
            MultiSend.multiSend.selector, multiSendData
        );

        // --- Step 4: Build Agent Safe execTransaction with v=1 signature ---
        // Master Safe is sole owner and will be msg.sender, so v=1 works
        bytes memory masterSafeSignature = _buildApprovedOwnerSignature(address(masterSafe));

        bytes memory agentExecData = abi.encodeWithSelector(
            GnosisSafe.execTransaction.selector,
            address(multiSend),      // to: MultiSend
            uint256(0),              // value
            agentSafeInnerData,      // data
            Enum.Operation.DelegateCall, // operation
            uint256(0),              // safeTxGas
            uint256(0),              // baseGas
            uint256(0),              // gasPrice
            address(0),              // gasToken
            payable(address(0)),     // refundReceiver
            masterSafeSignature      // signatures
        );

        // --- Step 5: Master EOA -> Master Safe -> Agent Safe.execTransaction ---
        _execMasterSafeTx(
            address(agentSafe),
            0,
            agentExecData
        );

        // --- Step 6: Verify all funds transferred ---
        assertEq(tokenOLAS.balanceOf(address(agentSafe)), 0);
        assertEq(tokenUSDC.balanceOf(address(agentSafe)), 0);
        assertEq(address(agentSafe).balance, 0);

        // Verify Master Safe received funds
        assertEq(tokenOLAS.balanceOf(address(masterSafe)), olasBalance);
        assertEq(tokenUSDC.balanceOf(address(masterSafe)), usdcBalance);
        assertGe(address(masterSafe).balance, nativeBalance);
    }

    // -----------------------------------------------------------------------
    // Test: Recovery when Agent Safe already owned by Master Safe (skip recovery)
    // -----------------------------------------------------------------------
    function test_skipRecovery_whenAlreadyOwner() public {
        // First recover
        _execMasterSafeTx(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(RecoveryModule.recoverAccess.selector, serviceId)
        );

        // Verify Master Safe is sole owner
        address[] memory agentOwners = agentSafe.getOwners();
        assertEq(agentOwners.length, 1);
        assertEq(agentOwners[0], address(masterSafe));

        // Now do fund transfer (no recovery step needed)
        uint256 olasBalance = tokenOLAS.balanceOf(address(agentSafe));
        bytes memory olasTransfer = abi.encodeWithSelector(
            bytes4(keccak256("transfer(address,uint256)")), address(masterSafe), olasBalance
        );

        bytes memory multiSendData = _encodeMultiSendTx(
            Enum.Operation.Call, address(tokenOLAS), 0, olasTransfer
        );

        bytes memory agentSafeInnerData = abi.encodeWithSelector(
            MultiSend.multiSend.selector, multiSendData
        );

        bytes memory masterSafeSignature = _buildApprovedOwnerSignature(address(masterSafe));

        bytes memory agentExecData = abi.encodeWithSelector(
            GnosisSafe.execTransaction.selector,
            address(multiSend),
            uint256(0),
            agentSafeInnerData,
            Enum.Operation.DelegateCall,
            uint256(0),
            uint256(0),
            uint256(0),
            address(0),
            payable(address(0)),
            masterSafeSignature
        );

        _execMasterSafeTx(address(agentSafe), 0, agentExecData);

        assertEq(tokenOLAS.balanceOf(address(agentSafe)), 0);
        assertEq(tokenOLAS.balanceOf(address(masterSafe)), olasBalance);
    }

    // -----------------------------------------------------------------------
    // Test: Recovery with only native token (no ERC20s)
    // -----------------------------------------------------------------------
    function test_recoverNativeTokenOnly() public {
        // Recover access
        _execMasterSafeTx(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(RecoveryModule.recoverAccess.selector, serviceId)
        );

        uint256 nativeBalance = address(agentSafe).balance;
        assertGt(nativeBalance, 0);

        // Build a simple native transfer (no multiSend needed for single tx, but we use it
        // to match the script pattern)
        bytes memory multiSendData = _encodeMultiSendTx(
            Enum.Operation.Call, address(masterSafe), nativeBalance, ""
        );

        bytes memory agentSafeInnerData = abi.encodeWithSelector(
            MultiSend.multiSend.selector, multiSendData
        );

        bytes memory masterSafeSignature = _buildApprovedOwnerSignature(address(masterSafe));

        bytes memory agentExecData = abi.encodeWithSelector(
            GnosisSafe.execTransaction.selector,
            address(multiSend),
            uint256(0),
            agentSafeInnerData,
            Enum.Operation.DelegateCall,
            uint256(0),
            uint256(0),
            uint256(0),
            address(0),
            payable(address(0)),
            masterSafeSignature
        );

        uint256 masterSafeBalanceBefore = address(masterSafe).balance;

        _execMasterSafeTx(address(agentSafe), 0, agentExecData);

        assertEq(address(agentSafe).balance, 0);
        assertEq(address(masterSafe).balance, masterSafeBalanceBefore + nativeBalance);
    }

    // -----------------------------------------------------------------------
    // Test: Recovery with multiple agent instances
    // -----------------------------------------------------------------------
    function test_recoverAccess_multipleAgentInstances() public {
        // Create a second service with 2 agent instances
        address agentInstance2 = users[4];

        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 1;
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0].slots = 2;
        agentParams[0].bond = regBond;

        uint256 sid = 2;

        serviceManager.create(
            address(masterSafe),
            serviceManager.ETH_TOKEN_ADDRESS(),
            unitHash,
            agentIds,
            agentParams,
            2  // threshold = 2
        );

        // Activate
        _execMasterSafeTx(
            address(serviceManager),
            regDeposit,
            abi.encodeWithSelector(ServiceManager.activateRegistration.selector, sid)
        );

        // Register 2 agent instances
        address[] memory instances = new address[](2);
        instances[0] = users[5];
        instances[1] = agentInstance2;
        uint32[] memory ids = new uint32[](2);
        ids[0] = 1;
        ids[1] = 1;
        vm.prank(operator);
        serviceManager.registerAgents{value: 2 * regBond}(sid, instances, ids);

        // Deploy
        _execMasterSafeTx(
            address(serviceManager),
            0,
            abi.encodeWithSelector(
                ServiceManager.deploy.selector,
                sid,
                address(safeMultisigWithRecoveryModule),
                payload
            )
        );

        // Get agent safe
        (, address multisig2, , , , , ) = serviceRegistry.mapServices(sid);
        GnosisSafe agentSafe2 = GnosisSafe(payable(multisig2));

        // Verify 2 owners
        address[] memory owners2 = agentSafe2.getOwners();
        assertEq(owners2.length, 2);

        // Fund it
        tokenOLAS.mint(address(agentSafe2), 500 ether);
        vm.deal(address(agentSafe2), 1 ether);

        // Terminate and unbond
        _execMasterSafeTx(
            address(serviceManager),
            0,
            abi.encodeWithSelector(ServiceManager.terminate.selector, sid)
        );
        vm.prank(operator);
        serviceManager.unbond(sid);

        // Recovery
        _execMasterSafeTx(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(RecoveryModule.recoverAccess.selector, sid)
        );

        // Verify sole owner
        owners2 = agentSafe2.getOwners();
        assertEq(owners2.length, 1);
        assertEq(owners2[0], address(masterSafe));

        // Transfer funds
        uint256 olasBalance = tokenOLAS.balanceOf(address(agentSafe2));
        uint256 nativeBalance = address(agentSafe2).balance;

        bytes memory multiSendData = abi.encodePacked(
            _encodeMultiSendTx(
                Enum.Operation.Call,
                address(tokenOLAS),
                0,
                abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), address(masterSafe), olasBalance)
            ),
            _encodeMultiSendTx(Enum.Operation.Call, address(masterSafe), nativeBalance, "")
        );

        bytes memory agentSafeInnerData = abi.encodeWithSelector(
            MultiSend.multiSend.selector, multiSendData
        );

        bytes memory sig = _buildApprovedOwnerSignature(address(masterSafe));

        bytes memory agentExecData = abi.encodeWithSelector(
            GnosisSafe.execTransaction.selector,
            address(multiSend),
            uint256(0),
            agentSafeInnerData,
            Enum.Operation.DelegateCall,
            uint256(0),
            uint256(0),
            uint256(0),
            address(0),
            payable(address(0)),
            sig
        );

        _execMasterSafeTx(address(agentSafe2), 0, agentExecData);

        assertEq(tokenOLAS.balanceOf(address(agentSafe2)), 0);
        assertEq(address(agentSafe2).balance, 0);
    }

    // -----------------------------------------------------------------------
    // Helper: Create a service, deploy it, and return the Agent Safe
    // -----------------------------------------------------------------------
    function _createAndDeployService(uint256 sid, address agentInst) internal returns (GnosisSafe) {
        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 1;
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = regBond;

        serviceManager.create(
            address(masterSafe),
            serviceManager.ETH_TOKEN_ADDRESS(),
            unitHash,
            agentIds,
            agentParams,
            threshold
        );

        _execMasterSafeTx(
            address(serviceManager),
            regDeposit,
            abi.encodeWithSelector(ServiceManager.activateRegistration.selector, sid)
        );

        // Master Safe registers as operator
        address[] memory instances = new address[](1);
        instances[0] = agentInst;
        uint32[] memory ids = new uint32[](1);
        ids[0] = 1;
        _execMasterSafeTx(
            address(serviceManager),
            regBond,
            abi.encodeWithSelector(ServiceManager.registerAgents.selector, sid, instances, ids)
        );

        _execMasterSafeTx(
            address(serviceManager),
            0,
            abi.encodeWithSelector(
                ServiceManager.deploy.selector,
                sid,
                address(safeMultisigWithRecoveryModule),
                payload
            )
        );

        (, address multisig2, , , , , ) = serviceRegistry.mapServices(sid);
        return GnosisSafe(payable(multisig2));
    }

    // -----------------------------------------------------------------------
    // Helper: Deploy staking, stake a service, return staking contract address
    // -----------------------------------------------------------------------
    function _deployStakingAndStake(uint256 sid, address agentSafeAddr)
        internal
        returns (StakingNativeToken)
    {
        StakingActivityChecker activityChecker = new StakingActivityChecker(1e15);
        bytes32 safeProxyHash = agentSafeAddr.codehash;

        StakingBase.StakingParams memory stakingParams = StakingBase.StakingParams({
            metadataHash: bytes32(uint256(1)),
            maxNumServices: 10,
            rewardsPerSecond: 1e15,
            minStakingDeposit: 2,
            minNumStakingPeriods: 10,
            maxNumInactivityPeriods: 10,
            livenessPeriod: 10,
            timeForEmissions: 1000,
            numAgentInstances: 1,
            agentIds: new uint256[](0),
            threshold: 0,
            configHash: bytes32(0),
            proxyHash: safeProxyHash,
            serviceRegistry: address(serviceRegistry),
            activityChecker: address(activityChecker)
        });

        StakingNativeToken snt = new StakingNativeToken();
        snt.initialize(stakingParams);

        // Fund staking contract with rewards
        vm.deal(address(this), 100 ether);
        (bool sent, ) = address(snt).call{value: 10 ether}("");
        assertTrue(sent);

        // Approve and stake
        _execMasterSafeTx(
            address(serviceRegistry),
            0,
            abi.encodeWithSelector(serviceRegistry.approve.selector, address(snt), sid)
        );
        _execMasterSafeTx(
            address(snt),
            0,
            abi.encodeWithSelector(bytes4(keccak256("stake(uint256)")), sid)
        );

        return snt;
    }

    // -----------------------------------------------------------------------
    // Helper: Build and execute fund transfer via MultiSend on recovered Agent Safe
    // -----------------------------------------------------------------------
    function _transferFundsFromAgentSafe(GnosisSafe targetAgentSafe) internal {
        uint256 olasBalance = tokenOLAS.balanceOf(address(targetAgentSafe));
        uint256 nativeBalance = address(targetAgentSafe).balance;

        bytes memory multiSendData = abi.encodePacked(
            _encodeMultiSendTx(
                Enum.Operation.Call,
                address(tokenOLAS),
                0,
                abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), address(masterSafe), olasBalance)
            ),
            _encodeMultiSendTx(Enum.Operation.Call, address(masterSafe), nativeBalance, "")
        );

        bytes memory agentSafeInnerData = abi.encodeWithSelector(
            MultiSend.multiSend.selector, multiSendData
        );

        bytes memory sig = _buildApprovedOwnerSignature(address(masterSafe));

        bytes memory agentExecData = abi.encodeWithSelector(
            GnosisSafe.execTransaction.selector,
            address(multiSend),
            uint256(0),
            agentSafeInnerData,
            Enum.Operation.DelegateCall,
            uint256(0),
            uint256(0),
            uint256(0),
            address(0),
            payable(address(0)),
            sig
        );

        _execMasterSafeTx(address(targetAgentSafe), 0, agentExecData);
    }

    // -----------------------------------------------------------------------
    // Test: Full recovery from staked service
    // Unstake -> Terminate -> Unbond -> Recover -> Transfer
    // -----------------------------------------------------------------------
    function test_recoverFromStakedService() public {
        uint256 sid = 2;

        // Create and deploy a new service with Master Safe as operator
        GnosisSafe agentSafe2 = _createAndDeployService(sid, users[5]);

        // Fund Agent Safe
        tokenOLAS.mint(address(agentSafe2), 777 ether);
        vm.deal(address(agentSafe2), 3 ether);

        // Deploy staking and stake the service
        StakingNativeToken stakingNativeToken = _deployStakingAndStake(sid, address(agentSafe2));

        // Verify staking setup
        assertEq(serviceRegistry.ownerOf(sid), address(stakingNativeToken));
        ServiceInfo memory sInfo = stakingNativeToken.getServiceInfo(sid);
        assertEq(sInfo.owner, address(masterSafe));

        // --- Full recovery flow (matching recover_funds.py) ---

        // Step 1: Unstake
        vm.warp(block.timestamp + 101);
        _execMasterSafeTx(
            address(stakingNativeToken),
            0,
            abi.encodeWithSelector(bytes4(keccak256("unstake(uint256)")), sid)
        );
        assertEq(serviceRegistry.ownerOf(sid), address(masterSafe));

        // Step 2: Terminate
        _execMasterSafeTx(
            address(serviceManager),
            0,
            abi.encodeWithSelector(ServiceManager.terminate.selector, sid)
        );

        // Step 3: Unbond (Master Safe is operator)
        _execMasterSafeTx(
            address(serviceManager),
            0,
            abi.encodeWithSelector(ServiceManager.unbond.selector, sid)
        );

        // Verify PreRegistration state
        (, , , , , , ServiceRegistryL2.ServiceState state2) = serviceRegistry.mapServices(sid);
        assertEq(uint8(state2), 1);

        // Step 4: Recovery
        _execMasterSafeTx(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(RecoveryModule.recoverAccess.selector, sid)
        );

        address[] memory owners2 = agentSafe2.getOwners();
        assertEq(owners2.length, 1);
        assertEq(owners2[0], address(masterSafe));

        // Step 5: Transfer funds
        uint256 olasBalanceBefore = tokenOLAS.balanceOf(address(agentSafe2));
        assertEq(olasBalanceBefore, 777 ether);
        assertGt(address(agentSafe2).balance, 0);

        _transferFundsFromAgentSafe(agentSafe2);

        // Verify all funds transferred
        assertEq(tokenOLAS.balanceOf(address(agentSafe2)), 0);
        assertEq(address(agentSafe2).balance, 0);
        assertEq(tokenOLAS.balanceOf(address(masterSafe)), olasBalanceBefore);
    }
}

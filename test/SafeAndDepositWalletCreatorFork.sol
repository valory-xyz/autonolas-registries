// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Utils} from "./utils/Utils.sol";
import {GnosisSafe, Enum} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {SignMessageLib} from "@gnosis.pm/safe-contracts/contracts/examples/libraries/SignMessage.sol";
import {
    SafeAndDepositWalletCreator,
    IDepositWallet,
    WrongDepositWalletAddress,
    DepositWalletNotDeployed
} from "../contracts/multisigs/SafeAndDepositWalletCreator.sol";

// Polymarket DepositWalletFactory ABI subset used by this fork test
interface IDepositWalletFactory {
    function deploy(address[] calldata _owners, bytes32[] calldata _ids) external;
    function rolesOf(address) external view returns (uint256);
    function predictWalletAddress(address _implementation, bytes32 _id) external view returns (address);
}

/// @dev Fork test only. Run with `forge test -f $POLYGON_RPC_URL --match-contract SafeAndDepositWalletCreatorFork -vvv`.
contract SafeAndDepositWalletCreatorFork is Test {
    Utils internal utils;

    // Polygon mainnet pre-deployed addresses (sourced from scripts/deployment/l2/globals_polygon_mainnet.json
    // and the merged @polymarket/builder-relayer-client@0.0.9 src/config/index.ts)
    address internal constant SAFE_SINGLETON = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
    address internal constant SAFE_PROXY_FACTORY = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
    address internal constant RECOVERY_MODULE = 0x02C26437B292D86c5F4F21bbCcE0771948274f84;
    address internal constant DEPOSIT_WALLET_FACTORY = 0x00000000000Fb5C9ADea0298D729A0CB3823Cc07;
    // Polymarket DepositWallet logic implementation on Polygon (per Sourcify probe; see
    // docs/polymarket/clob_v2_deposit_wallet_creator_plan.md "Verified factory + impl addresses" table).
    // Differs from Amoy (`0x50a88fE9…D7Fbd`).
    address internal constant DEPOSIT_WALLET_IMPLEMENTATION = 0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB;
    address internal constant FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;

    // Known caller of the very first DepositWalletFactory.deploy() on Polygon (block 86272144,
    // 2026-05-01T19:38:52Z). Almost certainly Polymarket's operator EOA. If this address ever loses the
    // operator role on-chain, capture a fresh operator from a recent factory event and update.
    address internal constant POLYMARKET_OPERATOR = 0x829BDEf266CEA938A81D911BaA68b5D138b3ba02;

    SafeAndDepositWalletCreator internal creator;

    function setUp() public {
        utils = new Utils();

        creator = new SafeAndDepositWalletCreator(
            SAFE_SINGLETON,
            SAFE_PROXY_FACTORY,
            RECOVERY_MODULE,
            DEPOSIT_WALLET_FACTORY,
            DEPOSIT_WALLET_IMPLEMENTATION
        );
    }

    /// @dev Impersonates the Polymarket operator EOA and calls `DepositWalletFactory.deploy` for `_agent`,
    ///      mirroring what the relayer does in production. Reads the deployed wallet address from the deploy
    ///      logs rather than predicting it on-chain — this avoids depending on solady's ERC1967 init-code hash,
    ///      which would otherwise need to be captured separately from the runtime codehash.
    function _operatorDeployDepositWallet(address _agent) internal returns (address depositWallet) {
        address[] memory owners = new address[](1);
        owners[0] = _agent;
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(uint160(_agent)));

        // Confirm the impersonated EOA still has the operator role
        require(IDepositWalletFactory(DEPOSIT_WALLET_FACTORY).rolesOf(POLYMARKET_OPERATOR) != 0,
            "POLYMARKET_OPERATOR no longer has operator role; capture a fresh operator and update");

        vm.recordLogs();

        vm.prank(POLYMARKET_OPERATOR);
        IDepositWalletFactory(DEPOSIT_WALLET_FACTORY).deploy(owners, ids);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Locate the new deposit wallet by scanning logs for any `address.code.length > 0` event emitter that
        // didn't have code before this call. Most robust against unknown event signatures: the first newly
        // code-bearing emitter under the factory's deploy is the wallet.
        for (uint256 i = 0; i < entries.length; ++i) {
            address emitter = entries[i].emitter;
            if (emitter == DEPOSIT_WALLET_FACTORY) continue;
            if (emitter.code.length == 0) continue;
            // Must own the expected agent
            try IDepositWallet(emitter).owner() returns (address ownerEoa) {
                if (ownerEoa == _agent) {
                    depositWallet = emitter;
                    break;
                }
            } catch {}
        }
        require(depositWallet != address(0), "deposit wallet address not found in deploy logs");
    }

    // -----------------------------------------------------------------------
    // Tests
    // -----------------------------------------------------------------------

    /// @dev Happy path on a forked chain: relayer-style operator pre-deploys a DW, then the creator deploys a Safe
    ///      with RecoveryModule enabled and links the DW.
    function testFork_Create_HappyPath() public {
        (address agentInstance, ) = makeAddrAndKey("agentInstance-fork-happy");

        // Phase 2 (off-chain HTTP in production): operator pre-deploys the deposit wallet
        address depositWallet = _operatorDeployDepositWallet(agentInstance);

        // Phase 3 (single on-chain user tx): creator deploys the Safe + RecoveryModule and verifies the DW
        address[] memory owners = new address[](1);
        owners[0] = agentInstance;
        bytes memory data = abi.encode(FALLBACK_HANDLER, uint256(uint160(agentInstance)), depositWallet);

        address multisig = creator.create(owners, 1, data);

        // Multisig is a freshly deployed Safe with the agent as sole owner, threshold one, recovery module enabled
        GnosisSafe safe = GnosisSafe(payable(multisig));
        assertEq(safe.getThreshold(), 1);
        address[] memory safeOwners = safe.getOwners();
        assertEq(safeOwners.length, 1);
        assertEq(safeOwners[0], agentInstance);
        assertTrue(safe.isModuleEnabled(RECOVERY_MODULE));

        // Deposit wallet linkage is recorded on-chain
        assertEq(creator.mapMultisigDepositWallets(multisig), depositWallet);

        // The deposit wallet is reachable and owned by the agent EOA
        bytes memory ownerCallData = abi.encodeWithSignature("owner()");
        (bool ok, bytes memory ret) = depositWallet.staticcall(ownerCallData);
        assertTrue(ok);
        assertEq(abi.decode(ret, (address)), agentInstance);
    }

    /// @dev Two services with distinct agent EOAs each get a distinct (Safe, deposit wallet) pair.
    function testFork_Create_TwoServicesAreIndependent() public {
        (address agentA, ) = makeAddrAndKey("agentInstance-fork-A");
        (address agentB, ) = makeAddrAndKey("agentInstance-fork-B");

        address dwA = _operatorDeployDepositWallet(agentA);
        address dwB = _operatorDeployDepositWallet(agentB);
        assertTrue(dwA != dwB);

        address[] memory ownersA = new address[](1);
        ownersA[0] = agentA;
        address multisigA = creator.create(ownersA, 1, abi.encode(FALLBACK_HANDLER, uint256(101), dwA));

        address[] memory ownersB = new address[](1);
        ownersB[0] = agentB;
        address multisigB = creator.create(ownersB, 1, abi.encode(FALLBACK_HANDLER, uint256(102), dwB));

        assertTrue(multisigA != multisigB);
        assertEq(creator.mapMultisigDepositWallets(multisigA), dwA);
        assertEq(creator.mapMultisigDepositWallets(multisigB), dwB);
    }

    /// @dev Reverts with `WrongDepositWalletAddress` when the caller supplies an address that doesn't match the
    ///      live factory's CREATE2 prediction for the agent EOA. Exercises the M-1 audit-fix check against the
    ///      real `DepositWalletFactory.predictWalletAddress` rather than a mock.
    function testFork_Create_RevertsOnWrongDepositWalletAddress() public {
        (address agentInstance, ) = makeAddrAndKey("agentInstance-fork-wrongaddr");
        address bogus = makeAddr("not-a-deposit-wallet");

        bytes32 walletId = bytes32(uint256(uint160(agentInstance)));
        address predicted = IDepositWalletFactory(DEPOSIT_WALLET_FACTORY)
            .predictWalletAddress(DEPOSIT_WALLET_IMPLEMENTATION, walletId);
        assertTrue(bogus != predicted);

        address[] memory owners = new address[](1);
        owners[0] = agentInstance;
        bytes memory data = abi.encode(FALLBACK_HANDLER, uint256(0), bogus);

        vm.expectRevert(abi.encodeWithSelector(WrongDepositWalletAddress.selector, predicted, bogus));
        creator.create(owners, 1, data);
    }

    /// @dev Reverts with `DepositWalletNotDeployed` when the caller supplies the canonical predicted address but
    ///      the relayer has not yet executed `DepositWalletFactory.deploy` — simulates Pearl racing Phase 3 ahead
    ///      of the off-chain HTTP-call mining.
    function testFork_Create_RevertsWhenRelayerSkipped() public {
        (address agentInstance, ) = makeAddrAndKey("agentInstance-fork-norelayer");

        bytes32 walletId = bytes32(uint256(uint160(agentInstance)));
        address predicted = IDepositWalletFactory(DEPOSIT_WALLET_FACTORY)
            .predictWalletAddress(DEPOSIT_WALLET_IMPLEMENTATION, walletId);
        // The canonical address must currently have no code on the forked block (we did not deploy)
        assertEq(predicted.code.length, 0);

        address[] memory owners = new address[](1);
        owners[0] = agentInstance;
        bytes memory data = abi.encode(FALLBACK_HANDLER, uint256(0), predicted);

        vm.expectRevert(abi.encodeWithSelector(DepositWalletNotDeployed.selector, predicted));
        creator.create(owners, 1, data);
    }
}

// Subset of the Polygon-deployed ServiceManager / ServiceRegistry / ERC20 ABI used by the e2e test
interface IServiceManager {
    struct AgentParams { uint32 slots; uint96 bond; }
    function ETH_TOKEN_ADDRESS() external view returns (address);
    function create(
        address serviceOwner,
        address token,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold
    ) external returns (uint256 serviceId);
    function activateRegistration(uint256 serviceId) external payable;
    function registerAgents(uint256 serviceId, address[] memory agentInstances, uint32[] memory agentIds)
        external payable;
    function deploy(uint256 serviceId, address multisigImplementation, bytes memory data)
        external returns (address multisig);
}

interface IServiceRegistry {
    function mapServices(uint256 serviceId) external view returns (
        uint96 securityDeposit, address multisig, bytes32 configHash, uint32 threshold,
        uint32 maxNumAgentInstances, uint32 numAgentInstances, uint8 state
    );
    function changeMultisigPermission(address multisig, bool permission) external;
}

interface IERC20Like {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IIdentityRegistryBridger {
    function mapMultisigAgentIds(address multisig) external view returns (uint256);
    function setAgentWallet(uint256 deadline, bytes memory signature) external;
}

interface IIdentityRegistry {
    function getAgentWallet(uint256 agentId) external view returns (address);
    function ownerOf(uint256 agentId) external view returns (address);
    function eip712Domain() external view returns (
        bytes1 fields, string memory name, string memory version, uint256 chainId,
        address verifyingContract, bytes32 salt, uint256[] memory extensions
    );
}

/// @dev End-to-end fork test: walks Phase 1 (OLAS service registration, multiple user txs), Phase 2 (off-chain
///      HTTP simulated via the impersonated Polymarket operator), and Phase 3 (the single on-chain user tx that
///      runs `serviceManager.deploy` → `creator.create`). Demonstrates the design lock-in: any number of off-chain
///      calls + exactly one on-chain user tx for the load-bearing deploy step. Run with
///      `forge test -f $POLYGON_RPC_URL --match-contract SafeAndDepositWalletCreatorE2E -vvv`.
contract SafeAndDepositWalletCreatorE2E is Test {
    Utils internal utils;

    // Polygon mainnet pre-deployed addresses (from scripts/deployment/l2/globals_polygon_mainnet.json
    // and the Polymarket deposit-wallet stack)
    address internal constant SAFE_SINGLETON = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
    address internal constant SAFE_PROXY_FACTORY = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
    address internal constant RECOVERY_MODULE = 0x02C26437B292D86c5F4F21bbCcE0771948274f84;
    address internal constant DEPOSIT_WALLET_FACTORY = 0x00000000000Fb5C9ADea0298D729A0CB3823Cc07;
    // Polymarket DepositWallet logic implementation on Polygon (per Sourcify probe; see
    // docs/polymarket/clob_v2_deposit_wallet_creator_plan.md "Verified factory + impl addresses" table).
    // Differs from Amoy (`0x50a88fE9…D7Fbd`).
    address internal constant DEPOSIT_WALLET_IMPLEMENTATION = 0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB;
    address internal constant FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;
    address internal constant POLYMARKET_OPERATOR = 0x829BDEf266CEA938A81D911BaA68b5D138b3ba02;

    address internal constant SERVICE_REGISTRY = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address internal constant SERVICE_MANAGER_PROXY = 0xE3e5Df46060370af5Fd37B2aA11e7dac3cCB4bd0;
    address internal constant SERVICE_REGISTRY_TOKEN_UTILITY = 0xa45E64d13A30a51b91ae0eb182e88a40e9b18eD8;
    address internal constant OLAS = 0xFEF5d947472e72Efbb2E388c730B7428406F2F95;
    // Bridge mediator on Polygon — owns ServiceRegistryL2 on this chain (governance flows from mainnet timelock
    // through the AMB bridge to this address; in production it would receive a cross-chain message)
    address internal constant SERVICE_REGISTRY_OWNER = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;
    address internal constant IDENTITY_REGISTRY_BRIDGER_PROXY = 0x6F121552765424f0B2331B541C0938480cA314Db;
    address internal constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;

    bytes32 internal constant CONFIG_HASH = 0x4d82a931d803e2b46b0dcd53f558f8de8305fd44b36288b42287ef1450a6611f;

    SafeAndDepositWalletCreator internal creator;

    address payable[] internal users;
    address internal deployer;

    function setUp() public {
        utils = new Utils();
        users = utils.createUsers(5);
        deployer = users[0];
        vm.deal(deployer, 5 ether);

        // Deploy creator
        creator = new SafeAndDepositWalletCreator(
            SAFE_SINGLETON, SAFE_PROXY_FACTORY, RECOVERY_MODULE, DEPOSIT_WALLET_FACTORY, DEPOSIT_WALLET_IMPLEMENTATION
        );

        // Whitelist creator on the on-chain ServiceRegistryL2. In production this requires a governance proposal
        // on mainnet that bridges through the AMB to the Polygon mediator; here we vm.prank the mediator directly
        vm.prank(SERVICE_REGISTRY_OWNER);
        IServiceRegistry(SERVICE_REGISTRY).changeMultisigPermission(address(creator), true);
    }

    /// @dev Impersonates the Polymarket operator EOA and calls `DepositWalletFactory.deploy` for `_agent`. Reads
    ///      the deployed wallet address back from the deploy logs.
    function _operatorDeployDepositWallet(address _agent) internal returns (address depositWallet) {
        address[] memory owners = new address[](1);
        owners[0] = _agent;
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(uint160(_agent)));

        require(IDepositWalletFactory(DEPOSIT_WALLET_FACTORY).rolesOf(POLYMARKET_OPERATOR) != 0,
            "POLYMARKET_OPERATOR no longer has operator role; capture a fresh operator and update");

        vm.recordLogs();
        vm.prank(POLYMARKET_OPERATOR);
        IDepositWalletFactory(DEPOSIT_WALLET_FACTORY).deploy(owners, ids);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        for (uint256 i = 0; i < entries.length; ++i) {
            address emitter = entries[i].emitter;
            if (emitter == DEPOSIT_WALLET_FACTORY) continue;
            if (emitter.code.length == 0) continue;
            try IDepositWallet(emitter).owner() returns (address ownerEoa) {
                if (ownerEoa == _agent) {
                    depositWallet = emitter;
                    break;
                }
            } catch {}
        }
        require(depositWallet != address(0), "deposit wallet address not found in deploy logs");
    }

    /// @dev Full end-to-end workflow against real Polygon mainnet contracts: off-chain DW pre-deploy + on-chain
    ///      service registration + the single load-bearing on-chain deploy tx that runs creator.create().
    function testForkE2E_FullWorkflow() public {
        // ---- T = 0 (off-chain compute, no calls) ---------------------------------------------------------------
        (address agentInstance, ) = makeAddrAndKey("agentInstance-e2e");

        // ---- T = 0+ (off-chain HTTP call: relayer pre-deploys the deposit wallet — Phase 2) ----------------------
        address depositWallet = _operatorDeployDepositWallet(agentInstance);
        assertEq(IDepositWallet(depositWallet).owner(), agentInstance);

        // ---- Phase 1: OLAS service registration (multiple user txs, none affect the deposit wallet) ---------------
        deal(OLAS, deployer, 50000 ether);
        IServiceManager.AgentParams[] memory agentParams = new IServiceManager.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = 50 ether;
        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 86;

        vm.startPrank(deployer);
        IERC20Like(OLAS).approve(SERVICE_REGISTRY_TOKEN_UTILITY, 1000 ether);
        uint256 serviceId = IServiceManager(SERVICE_MANAGER_PROXY).create(
            deployer, OLAS, CONFIG_HASH, agentIds, agentParams, 1
        );
        IServiceManager(SERVICE_MANAGER_PROXY).activateRegistration{value: 1}(serviceId);
        address[] memory agentInstances = new address[](1);
        agentInstances[0] = agentInstance;
        IServiceManager(SERVICE_MANAGER_PROXY).registerAgents{value: 1}(serviceId, agentInstances, agentIds);
        vm.stopPrank();

        // ---- T = max(Phase1, Phase2): Phase 3 — THE SINGLE LOAD-BEARING ON-CHAIN USER TRANSACTION ------------------
        // Pearl submits this tx; ServiceManager.deploy → creator.create runs atomically.
        bytes memory data = abi.encode(FALLBACK_HANDLER, uint256(uint160(agentInstance)), depositWallet);
        vm.prank(deployer);
        IServiceManager(SERVICE_MANAGER_PROXY).deploy(serviceId, address(creator), data);

        // ---- End-state verification ----------------------------------------------------------------------------
        (, address multisig, , , , , uint8 state) =
            IServiceRegistry(SERVICE_REGISTRY).mapServices(serviceId);

        // Service is in Deployed state (4)
        assertEq(state, 4);

        // Multisig is a Safe with the agent EOA as sole owner and the recovery module enabled
        GnosisSafe safe = GnosisSafe(payable(multisig));
        address[] memory safeOwners = safe.getOwners();
        assertEq(safeOwners.length, 1);
        assertEq(safeOwners[0], agentInstance);
        assertEq(safe.getThreshold(), 1);
        assertTrue(safe.isModuleEnabled(RECOVERY_MODULE));

        // Deposit wallet linkage is recorded on the creator and discoverable on-chain by third parties
        assertEq(creator.mapMultisigDepositWallets(multisig), depositWallet);

        // The deposit wallet is owned by the agent EOA — Pearl can now sign Phase 4 batches via Privy and submit
        // them to the Polymarket relayer's `proxy()` endpoint to authorize session signers and approve trading
        // collateral on the deposit wallet. Phase 4 batch construction is off-chain orchestration that does not
        // affect the on-chain Safe state, so we don't exercise it here — but the link is in place.
        assertEq(IDepositWallet(depositWallet).owner(), agentInstance);
    }

    /// @dev Demonstrates the full ERC-8004 `setAgentWallet` flow through the new Safe — the same pattern used by
    ///      `ServiceManagerNative.js`'s middleware-workflow test for the existing PolySafe path. The Safe is set up
    ///      with the Polygon-canonical CompatibilityFallbackHandler, so its ERC-1271 `isValidSignature` follows the
    ///      `signedMessages` lookup path. The agent EOA executes a Safe-tx that delegatecalls `SignMessageLib` to
    ///      pre-store the IdentityRegistry's `AgentWalletSet` typed-data digest, then a second Safe-tx calls
    ///      `bridger.setAgentWallet(deadline, "")` — IdentityRegistry's ERC-1271 check passes against the empty
    ///      signature because the digest is in `signedMessages`. **No `SignMessageLib` logic is "ported" by the
    ///      creator contract** — this is the standard Safe v1.3.0 + CompatibilityFallbackHandler flow, equivalent
    ///      to what the existing PolySafe creator inherits via Polymarket's PolySafeProxyFactory.
    function testForkE2E_SetAgentWalletViaSignMessageLib() public {
        (address agentInstance, uint256 agentInstancePk) = makeAddrAndKey("agentInstance-setagent");
        address multisig = _runDeployWorkflow(agentInstance);
        _signAndSetAgentWallet(GnosisSafe(payable(multisig)), agentInstance, agentInstancePk);

        // IdentityRegistry now records the multisig as the agent wallet
        uint256 agentId = IIdentityRegistryBridger(IDENTITY_REGISTRY_BRIDGER_PROXY).mapMultisigAgentIds(multisig);
        assertEq(IIdentityRegistry(IDENTITY_REGISTRY).getAgentWallet(agentId), multisig);
    }

    /// @dev Walks Phase 1 + 2 + 3 of the workflow and returns the deployed multisig.
    function _runDeployWorkflow(address _agentInstance) internal returns (address multisig) {
        address depositWallet = _operatorDeployDepositWallet(_agentInstance);

        deal(OLAS, deployer, 50000 ether);
        IServiceManager.AgentParams[] memory agentParams = new IServiceManager.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = 50 ether;
        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 86;

        vm.startPrank(deployer);
        IERC20Like(OLAS).approve(SERVICE_REGISTRY_TOKEN_UTILITY, 1000 ether);
        uint256 serviceId = IServiceManager(SERVICE_MANAGER_PROXY).create(
            deployer, OLAS, CONFIG_HASH, agentIds, agentParams, 1
        );
        IServiceManager(SERVICE_MANAGER_PROXY).activateRegistration{value: 1}(serviceId);
        address[] memory agentInstances = new address[](1);
        agentInstances[0] = _agentInstance;
        IServiceManager(SERVICE_MANAGER_PROXY).registerAgents{value: 1}(serviceId, agentInstances, agentIds);
        vm.stopPrank();

        // Fallback handler must be the CompatibilityFallbackHandler so the Safe's ERC-1271
        // `isValidSignature(bytes32,bytes)` routes through the `signedMessages` path
        bytes memory data = abi.encode(FALLBACK_HANDLER, uint256(uint160(_agentInstance)), depositWallet);
        vm.prank(deployer);
        IServiceManager(SERVICE_MANAGER_PROXY).deploy(serviceId, address(creator), data);

        (, multisig, , , , , ) = IServiceRegistry(SERVICE_REGISTRY).mapServices(serviceId);
    }

    /// @dev Pre-signs the IdentityRegistry's `AgentWalletSet` digest via `SignMessageLib`, then submits the
    ///      `bridger.setAgentWallet(deadline, "")` call from the multisig.
    function _signAndSetAgentWallet(GnosisSafe _safe, address _agentInstance, uint256 _signerPk) internal {
        // Pre-checks: agent is registered in the bridger but agentWallet on the IdentityRegistry is unset
        uint256 agentId =
            IIdentityRegistryBridger(IDENTITY_REGISTRY_BRIDGER_PROXY).mapMultisigAgentIds(address(_safe));
        require(agentId > 0, "agent not registered");
        address agentNftOwner = IIdentityRegistry(IDENTITY_REGISTRY).ownerOf(agentId);
        require(agentNftOwner == IDENTITY_REGISTRY_BRIDGER_PROXY, "unexpected agent owner");
        require(IIdentityRegistry(IDENTITY_REGISTRY).getAgentWallet(agentId) == address(0), "wallet already set");

        // Build the EIP-712 digest the IdentityRegistry's `setAgentWallet` will validate
        uint256 deadline = block.timestamp + 100;
        bytes32 digest = _agentWalletSetDigest(agentId, address(_safe), agentNftOwner, deadline);

        // Step 1: pre-sign the digest via SignMessageLib delegatecall
        SignMessageLib signMessageLib = new SignMessageLib();
        bytes memory signMsgCall =
            abi.encodeCall(SignMessageLib.signMessage, (abi.encodePacked(digest)));
        _execSafeTx(_safe, _signerPk, address(signMessageLib), 0, signMsgCall, Enum.Operation.DelegateCall);
        // CompatibilityFallbackHandler will look up `signedMessages[_safeMessageHash(safe, digest)]`
        require(_safe.signedMessages(_safeMessageHash(address(_safe), digest)) != 0, "message not signed");

        // Step 2: call `bridger.setAgentWallet(deadline, "")` from the multisig — IdentityRegistry tries ECDSA
        // first (fails since recovered != newWallet), then ERC-1271 against the multisig with empty signature,
        // which routes through the `signedMessages` path we just populated
        bytes memory setCall = abi.encodeCall(IIdentityRegistryBridger.setAgentWallet, (deadline, ""));
        _execSafeTx(_safe, _signerPk, IDENTITY_REGISTRY_BRIDGER_PROXY, 0, setCall, Enum.Operation.Call);

        _agentInstance; // silence unused-parameter warning; agent address is implicit in _signerPk
    }

    // -----------------------------------------------------------------------
    // Helpers for SignMessageLib + EIP-712 typed-data construction
    // -----------------------------------------------------------------------

    bytes32 internal constant AGENT_WALLET_SET_TYPEHASH =
        keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");
    bytes32 internal constant SAFE_MSG_TYPEHASH =
        0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca;

    /// @dev Builds the IdentityRegistry's `AgentWalletSet` EIP-712 digest using its on-chain domain.
    function _agentWalletSetDigest(uint256 _agentId, address _newWallet, address _agentOwner, uint256 _deadline)
        internal view returns (bytes32)
    {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract, ,) =
            IIdentityRegistry(IDENTITY_REGISTRY).eip712Domain();
        bytes32 domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract
        ));
        bytes32 structHash = keccak256(abi.encode(
            AGENT_WALLET_SET_TYPEHASH, _agentId, _newWallet, _agentOwner, _deadline
        ));
        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, structHash));
    }

    /// @dev Mirrors `CompatibilityFallbackHandler.getMessageHashForSafe`: the wrapped Safe-side hash that
    ///      `signMessage` stores and `isValidSignature` looks up.
    function _safeMessageHash(address _safe, bytes32 _digest) internal view returns (bytes32) {
        bytes32 safeMessageHash = keccak256(abi.encode(SAFE_MSG_TYPEHASH, keccak256(abi.encodePacked(_digest))));
        return keccak256(abi.encodePacked(
            bytes1(0x19), bytes1(0x01), GnosisSafe(payable(_safe)).domainSeparator(), safeMessageHash
        ));
    }

    /// @dev Executes a single-owner Safe transaction signed by `_signerPk` using ECDSA. Mirrors the pattern in
    ///      `RecoverFunds.t.sol`.
    function _execSafeTx(
        GnosisSafe _safe,
        uint256 _signerPk,
        address _to,
        uint256 _value,
        bytes memory _data,
        Enum.Operation _operation
    ) internal {
        uint256 nonce = _safe.nonce();
        bytes32 txHash = _safe.getTransactionHash(
            _to, _value, _data, _operation, 0, 0, 0, address(0), payable(address(0)), nonce
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPk, txHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(vm.addr(_signerPk));
        _safe.execTransaction{value: _value}(
            _to, _value, _data, _operation, 0, 0, 0, address(0), payable(address(0)), signature
        );
    }
}

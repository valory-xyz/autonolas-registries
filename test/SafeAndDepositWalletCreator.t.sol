// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Utils} from "./utils/Utils.sol";
import {GnosisSafe} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import {MultiSend} from "@gnosis.pm/safe-contracts/contracts/libraries/MultiSend.sol";
import {DefaultCallbackHandler} from "@gnosis.pm/safe-contracts/contracts/handler/DefaultCallbackHandler.sol";
import {RecoveryModule} from "../contracts/multisigs/RecoveryModule.sol";
import {
    SafeAndDepositWalletCreator,
    ZeroAddress,
    IncorrectDataLength,
    WrongNumOwners,
    DepositWalletNotDeployed,
    WrongDepositWalletOwner,
    WrongDepositWalletAddress
} from "../contracts/multisigs/SafeAndDepositWalletCreator.sol";
import {MockDepositWalletFactory, MockDepositWallet} from "../contracts/test/MockDepositWalletFactory.sol";

contract BaseSetup is Test {
    Utils internal utils;
    GnosisSafe internal gnosisSafe;
    GnosisSafeProxyFactory internal gnosisSafeProxyFactory;
    DefaultCallbackHandler internal fallbackHandler;
    MultiSend internal multiSend;
    RecoveryModule internal recoveryModule;
    MockDepositWalletFactory internal depositWalletFactory;
    SafeAndDepositWalletCreator internal creator;
    // Stand-in for Polymarket's deposit wallet implementation address. The mock factory ignores this argument
    // when computing CREATE2 addresses (see MockDepositWalletFactory NatSpec); any non-zero address works.
    address internal depositWalletImplementation;

    address payable[] internal users;
    address internal deployer;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(10);
        deployer = users[0];
        vm.label(deployer, "Deployer");

        // Deploy Safe infrastructure
        gnosisSafe = new GnosisSafe();
        gnosisSafeProxyFactory = new GnosisSafeProxyFactory();
        fallbackHandler = new DefaultCallbackHandler();
        multiSend = new MultiSend();

        // Deploy recovery module (serviceRegistry not exercised in the create() path, any non-zero address suffices)
        recoveryModule = new RecoveryModule(address(multiSend), address(gnosisSafe));

        // Deploy deposit wallet mock factory and pick a stand-in implementation address
        depositWalletFactory = new MockDepositWalletFactory();
        depositWalletImplementation = address(0xC0DE);

        // Deploy creator
        creator = new SafeAndDepositWalletCreator(
            address(gnosisSafe),
            address(gnosisSafeProxyFactory),
            address(recoveryModule),
            address(depositWalletFactory),
            depositWalletImplementation
        );
    }

    /// @dev Pre-deploys a mock deposit wallet for `_owner` via the mock factory and returns the address.
    function _preDeployDepositWallet(address _owner) internal returns (address) {
        address[] memory owners = new address[](1);
        owners[0] = _owner;
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(uint160(_owner)));

        address predicted = depositWalletFactory.computeWalletAddress(_owner);
        depositWalletFactory.deploy(owners, ids);

        return predicted;
    }
}

contract SafeAndDepositWalletCreatorConstructor is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Constructor reverts on any zero address.
    function testConstructor_RevertsOnZeroAddress() public {
        vm.expectRevert(ZeroAddress.selector);
        new SafeAndDepositWalletCreator(
            address(0), address(gnosisSafeProxyFactory), address(recoveryModule),
            address(depositWalletFactory), depositWalletImplementation
        );

        vm.expectRevert(ZeroAddress.selector);
        new SafeAndDepositWalletCreator(
            address(gnosisSafe), address(0), address(recoveryModule),
            address(depositWalletFactory), depositWalletImplementation
        );

        vm.expectRevert(ZeroAddress.selector);
        new SafeAndDepositWalletCreator(
            address(gnosisSafe), address(gnosisSafeProxyFactory), address(0),
            address(depositWalletFactory), depositWalletImplementation
        );

        vm.expectRevert(ZeroAddress.selector);
        new SafeAndDepositWalletCreator(
            address(gnosisSafe), address(gnosisSafeProxyFactory), address(recoveryModule),
            address(0), depositWalletImplementation
        );

        vm.expectRevert(ZeroAddress.selector);
        new SafeAndDepositWalletCreator(
            address(gnosisSafe), address(gnosisSafeProxyFactory), address(recoveryModule),
            address(depositWalletFactory), address(0)
        );
    }

    /// @dev Constructor stores all immutables and constants.
    function testConstructor_StoresImmutables() public view {
        assertEq(creator.safe(), address(gnosisSafe));
        assertEq(creator.safeProxyFactory(), address(gnosisSafeProxyFactory));
        assertEq(creator.recoveryModule(), address(recoveryModule));
        assertEq(creator.depositWalletFactory(), address(depositWalletFactory));
        assertEq(creator.depositWalletImplementation(), depositWalletImplementation);
        assertEq(creator.SAFE_SETUP_SELECTOR(), bytes4(0xb63e800d));
        assertEq(creator.ENABLE_MODULE_SELECTOR(), bytes4(0x24292962));
        assertEq(creator.DEFAULT_DATA_LENGTH(), 96);
    }
}

contract SafeAndDepositWalletCreatorCreate is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Happy path: pre-deploy a DW, then call create() with a single owner matching the DW owner.
    function testCreate_HappyPath() public {
        address agentInstance = users[1];
        address depositWallet = _preDeployDepositWallet(agentInstance);

        address[] memory owners = new address[](1);
        owners[0] = agentInstance;

        bytes memory data = abi.encode(address(fallbackHandler), uint256(1), depositWallet);

        address multisig = creator.create(owners, 1, data);

        // Multisig is a Safe with one owner equal to agentInstance and threshold one
        GnosisSafe safe = GnosisSafe(payable(multisig));
        assertEq(safe.getThreshold(), 1);
        address[] memory safeOwners = safe.getOwners();
        assertEq(safeOwners.length, 1);
        assertEq(safeOwners[0], agentInstance);

        // Recovery module is enabled
        assertTrue(safe.isModuleEnabled(address(recoveryModule)));

        // Deposit wallet linkage is recorded
        assertEq(creator.mapMultisigDepositWallets(multisig), depositWallet);
        assertEq(MockDepositWallet(depositWallet).owner(), agentInstance);
    }

    /// @dev Both events are emitted with the expected indexed topics.
    function testCreate_EmitsEvents() public {
        address agentInstance = users[2];
        address depositWallet = _preDeployDepositWallet(agentInstance);

        address[] memory owners = new address[](1);
        owners[0] = agentInstance;

        bytes memory data = abi.encode(address(fallbackHandler), uint256(2), depositWallet);

        vm.recordLogs();
        address multisig = creator.create(owners, 1, data);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 createdSig = keccak256("MultisigCreated(address,address)");
        bytes32 linkedSig = keccak256("DepositWalletLinked(address,address)");
        bool sawCreated;
        bool sawLinked;
        for (uint256 i = 0; i < entries.length; ++i) {
            if (entries[i].emitter != address(creator)) continue;
            if (entries[i].topics[0] == createdSig) {
                assertEq(address(uint160(uint256(entries[i].topics[1]))), multisig);
                assertEq(address(uint160(uint256(entries[i].topics[2]))), agentInstance);
                sawCreated = true;
            } else if (entries[i].topics[0] == linkedSig) {
                assertEq(address(uint160(uint256(entries[i].topics[1]))), multisig);
                assertEq(address(uint160(uint256(entries[i].topics[2]))), depositWallet);
                sawLinked = true;
            }
        }
        assertTrue(sawCreated);
        assertTrue(sawLinked);
    }

    /// @dev Reverts with `WrongDepositWalletAddress` when the provided address differs from the canonical
    ///      CREATE2 prediction. This is the primary defense added by the M-1 audit fix: even an attacker-controlled
    ///      contract exposing `owner()` returning the agent EOA will be rejected unless it sits at the canonical
    ///      address derived from `(factory, impl, walletId)`.
    function testCreate_RevertsOnWrongDepositWalletAddress() public {
        address agentInstance = users[3];
        address predicted = depositWalletFactory.computeWalletAddress(agentInstance);
        address bogus = address(0xBAD);

        address[] memory owners = new address[](1);
        owners[0] = agentInstance;

        bytes memory data = abi.encode(address(fallbackHandler), uint256(0), bogus);

        vm.expectRevert(abi.encodeWithSelector(WrongDepositWalletAddress.selector, predicted, bogus));
        creator.create(owners, 1, data);
    }

    /// @dev Address prediction check rejects a fake "DepositWallet" lookalike contract — the exact attack vector
    ///      M-1 highlighted. A `Fake { address public owner; constructor(address o){owner=o;} }` deployed at an
    ///      arbitrary address satisfies the legacy shape checks but not the canonical CREATE2 prediction.
    function testCreate_RejectsFakeDepositWalletAtNonCanonicalAddress() public {
        address agentInstance = users[4];
        address[] memory owners = new address[](1);
        owners[0] = agentInstance;

        // Deploy a deceptive lookalike: exposes owner() returning the agent EOA, but not at the canonical address
        FakeDepositWalletLookalike fake = new FakeDepositWalletLookalike(agentInstance);
        assertEq(fake.owner(), agentInstance);

        address predicted = depositWalletFactory.computeWalletAddress(agentInstance);
        assertTrue(address(fake) != predicted);

        bytes memory data = abi.encode(address(fallbackHandler), uint256(0), address(fake));

        vm.expectRevert(abi.encodeWithSelector(WrongDepositWalletAddress.selector, predicted, address(fake)));
        creator.create(owners, 1, data);
    }

    /// @dev Reverts with `DepositWalletNotDeployed` when the canonical address is supplied but no wallet has been
    ///      deployed there yet — simulates Pearl submitting Phase 3 before the off-chain relayer-deploy has mined.
    function testCreate_RevertsWhenDepositWalletNotDeployed() public {
        address agentInstance = users[3];
        address predicted = depositWalletFactory.computeWalletAddress(agentInstance);

        address[] memory owners = new address[](1);
        owners[0] = agentInstance;

        bytes memory data = abi.encode(address(fallbackHandler), uint256(0), predicted);

        vm.expectRevert(abi.encodeWithSelector(DepositWalletNotDeployed.selector, predicted));
        creator.create(owners, 1, data);
    }

    /// @dev Reverts with `WrongDepositWalletOwner` when the wallet sits at the canonical address but was
    ///      initialized for a different owner — exercises the operator-chosen-`_ids` deviation the factory permits
    ///      (factory does not enforce `_ids[i] == bytes32(_owners[i])`; that is a relayer convention). The
    ///      address-prediction check passes because the wallet was deployed with `walletId = bytes32(agentInstance)`,
    ///      while the `_owners[i]` argument was a different EOA — only the owner cross-check catches it.
    function testCreate_RevertsWhenDepositWalletOwnerMismatch() public {
        address agentInstance = users[5];
        address other = users[6];

        // Deploy via mock factory at the agentInstance-predicted address but with `other` as the owner —
        // exactly what an operator deviating from the relayer's `bytes32(owner)` convention would produce.
        address[] memory deployOwners = new address[](1);
        deployOwners[0] = other;
        bytes32[] memory deployIds = new bytes32[](1);
        deployIds[0] = bytes32(uint256(uint160(agentInstance)));
        depositWalletFactory.deploy(deployOwners, deployIds);

        address depositWallet = depositWalletFactory.computeWalletAddress(agentInstance);
        assertEq(MockDepositWallet(depositWallet).owner(), other);

        address[] memory owners = new address[](1);
        owners[0] = agentInstance;

        bytes memory data = abi.encode(address(fallbackHandler), uint256(0), depositWallet);

        vm.expectRevert(abi.encodeWithSelector(WrongDepositWalletOwner.selector, agentInstance, other));
        creator.create(owners, 1, data);
    }

    /// @dev Reverts when zero owners are provided.
    function testCreate_RevertsOnZeroOwners() public {
        address[] memory owners = new address[](0);
        bytes memory data = abi.encode(address(fallbackHandler), uint256(0), address(0));

        vm.expectRevert(abi.encodeWithSelector(WrongNumOwners.selector, 1, 0));
        creator.create(owners, 1, data);
    }

    /// @dev Reverts when more than one owner is provided.
    function testCreate_RevertsOnMultipleOwners() public {
        address[] memory owners = new address[](2);
        owners[0] = users[1];
        owners[1] = users[2];
        bytes memory data = abi.encode(address(fallbackHandler), uint256(0), address(0));

        vm.expectRevert(abi.encodeWithSelector(WrongNumOwners.selector, 1, 2));
        creator.create(owners, 1, data);
    }

    /// @dev Reverts when data length does not match the expected encoding.
    function testCreate_RevertsOnIncorrectDataLength() public {
        address agentInstance = users[7];
        _preDeployDepositWallet(agentInstance);

        address[] memory owners = new address[](1);
        owners[0] = agentInstance;

        // Too short (matches SafeMultisigWithRecoveryModule's 64-byte payload)
        bytes memory shortData = abi.encode(address(fallbackHandler), uint256(0));
        vm.expectRevert(abi.encodeWithSelector(IncorrectDataLength.selector, 96, 64));
        creator.create(owners, 1, shortData);

        // Empty data
        vm.expectRevert(abi.encodeWithSelector(IncorrectDataLength.selector, 96, 0));
        creator.create(owners, 1, "");

        // Too long
        bytes memory longData = abi.encode(address(fallbackHandler), uint256(0), address(0), uint256(0));
        vm.expectRevert(abi.encodeWithSelector(IncorrectDataLength.selector, 96, 128));
        creator.create(owners, 1, longData);
    }

    /// @dev Mapping is populated only on successful create; entries for distinct services are independent.
    function testCreate_MappingIsPopulatedAndPreservedAcrossCalls() public {
        address agentA = users[1];
        address agentB = users[2];

        address dwA = _preDeployDepositWallet(agentA);
        address dwB = _preDeployDepositWallet(agentB);

        address[] memory ownersA = new address[](1);
        ownersA[0] = agentA;
        address multisigA = creator.create(ownersA, 1, abi.encode(address(fallbackHandler), uint256(11), dwA));

        address[] memory ownersB = new address[](1);
        ownersB[0] = agentB;
        address multisigB = creator.create(ownersB, 1, abi.encode(address(fallbackHandler), uint256(22), dwB));

        assertEq(creator.mapMultisigDepositWallets(multisigA), dwA);
        assertEq(creator.mapMultisigDepositWallets(multisigB), dwB);
        assertTrue(multisigA != multisigB);
    }
}

/// @dev Minimal lookalike contract used by `testCreate_RejectsFakeDepositWalletAtNonCanonicalAddress` — the exact
///      attack pattern flagged by M-1. Satisfies the legacy `owner()` shape check but is not at the canonical
///      CREATE2 address `DepositWalletFactory.predictWalletAddress(impl, walletId)` would compute.
contract FakeDepositWalletLookalike {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }
}

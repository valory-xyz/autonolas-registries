// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RecoverFundsTest} from "./RecoverFunds.t.sol";
import {IService} from "../contracts/interfaces/IService.sol";
import {GnosisSafe} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeSameAddressMultisig} from "../contracts/multisigs/GnosisSafeSameAddressMultisig.sol";
import {ServiceManager, MultisigAlreadyBound} from "../contracts/ServiceManager.sol";
import {ServiceRegistryL2} from "../contracts/ServiceRegistryL2.sol";

/// @title ServiceManagerMultisigBindingTest
/// @notice Proves the 81064 fix: after the ServiceManager implementation is updated, and WITHOUT any
///         bindMultisig back-fill, the same-address takeover can no longer be set up — deploy() reverts
///         for an attacker trying to bind a multisig that already belongs to a different service, even
///         after that service has been terminated and unbonded.
///
///         Reuses RecoverFundsTest.setUp() which, on the FIXED ServiceManager, deploys service #1's Agent
///         Safe (recovery-enabled), then terminates + unbonds it → service #1 ends in PreRegistration with
///         its multisig pointer preserved and auto-claimed at deploy. (Inheriting also re-runs the recovery
///         tests under this contract, confirming the fix does not break the legitimate recovery flow.)
contract ServiceManagerMultisigBindingTest is RecoverFundsTest {
    GnosisSafeSameAddressMultisig internal sameAddrMultisig;
    uint256 internal constant VICTIM_ID = 1; // service created in RecoverFundsTest.setUp()

    // Deploy + whitelist a same-address adapter (the binding tool used in the 81064 attack).
    // proxyHash = runtime code hash of a GnosisSafeProxy from this factory (the Agent Safe is one).
    // Called inside tests that need it (parent setUp() is not virtual, so it can't be overridden).
    function _setupAdapter() internal {
        bytes32 proxyHash = keccak256(address(agentSafe).code);
        sameAddrMultisig = new GnosisSafeSameAddressMultisig(proxyHash);
        serviceRegistry.changeMultisigPermission(address(sameAddrMultisig), true);
    }

    /// @dev The victim Safe was auto-claimed by service #1 at deploy — no bindMultisig was ever called.
    function test_autoClaim_onDeploy_noBackfill() public view {
        assertEq(serviceManager.mapMultisigServiceIds(address(agentSafe)), VICTIM_ID, "victim Safe not auto-claimed");
    }

    /// @dev HEADLINE: an unprivileged attacker cannot bind the victim's (terminated+unbonded) Safe to a new
    ///      service — deploy() reverts MultisigAlreadyBound. No bindMultisig back-fill is needed.
    function test_attackerBindingReverts_afterTerminateUnbond() public {
        _setupAdapter();
        // Sanity: victim #1 is in PreRegistration with its Safe pointer preserved and claimed.
        (, address vMultisig, , , , , ServiceRegistryL2.ServiceState vState) = serviceRegistry.mapServices(VICTIM_ID);
        assertEq(vMultisig, address(agentSafe));
        assertEq(uint8(vState), 1); // PreRegistration
        assertEq(serviceManager.mapMultisigServiceIds(address(agentSafe)), VICTIM_ID);

        address attacker = address(0xA77ACE);
        vm.deal(attacker, 100 ether);

        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 1;
        IService.AgentParams[] memory ap = new IService.AgentParams[](1);
        ap[0].slots = 1;
        ap[0].bond = regBond;

        // 1) attacker mints its own service (#2)
        serviceManager.create(attacker, serviceManager.ETH_TOKEN_ADDRESS(), unitHash, agentIds, ap, threshold);
        uint256 attackerId = 2;
        assertEq(serviceRegistry.ownerOf(attackerId), attacker);

        // 2) activate + 3) register the victim Safe's owner (free again after unbond) as the agent instance
        vm.prank(attacker);
        serviceManager.activateRegistration{value: regDeposit}(attackerId);

        address[] memory instances = new address[](1);
        instances[0] = agentInstance; // == agentSafe.getOwners()[0]
        vm.prank(attacker);
        serviceManager.registerAgents{value: regBond}(attackerId, instances, agentIds);

        // 4) attacker tries to bind the victim's Safe via the same-address adapter -> MUST REVERT
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(MultisigAlreadyBound.selector, address(agentSafe), VICTIM_ID, attackerId));
        serviceManager.deploy(attackerId, address(sameAddrMultisig), abi.encodePacked(address(agentSafe)));
    }

    /// @dev The legitimate owner can still re-deploy its OWN Safe via the same-address adapter (no-op claim).
    function test_legitOwnerRedeploy_succeeds() public {
        _setupAdapter();
        // service #1 owner (Master Safe) re-activates and re-registers the same agent instance
        _execMasterSafeTx(
            address(serviceManager),
            regDeposit,
            abi.encodeWithSelector(ServiceManager.activateRegistration.selector, VICTIM_ID)
        );

        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 1;
        address[] memory instances = new address[](1);
        instances[0] = agentInstance;
        vm.prank(operator);
        serviceManager.registerAgents{value: regBond}(VICTIM_ID, instances, agentIds);

        // re-deploy to the SAME Safe via the same-address adapter -> succeeds; binding stays serviceId #1
        _execMasterSafeTx(
            address(serviceManager),
            0,
            abi.encodeWithSelector(
                ServiceManager.deploy.selector,
                VICTIM_ID,
                address(sameAddrMultisig),
                abi.encodePacked(address(agentSafe))
            )
        );

        (, address ms, , , , , ServiceRegistryL2.ServiceState st) = serviceRegistry.mapServices(VICTIM_ID);
        assertEq(ms, address(agentSafe), "redeploy changed multisig");
        assertEq(uint8(st), 4, "service not Deployed after redeploy");
        assertEq(serviceManager.mapMultisigServiceIds(address(agentSafe)), VICTIM_ID, "binding changed");
    }

    /// @dev bindMultisig is idempotent: re-claiming an already-claimed multisig is a no-op (no revert, no overwrite).
    function test_bindMultisig_idempotent() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = VICTIM_ID;
        serviceManager.bindMultisig(ids); // already claimed -> no-op
        assertEq(serviceManager.mapMultisigServiceIds(address(agentSafe)), VICTIM_ID);
    }

    /// @dev When the legitimate owner re-deploys to a DIFFERENT Safe, the old binding is released (set to 0)
    ///      and the new one is claimed. Same-address redeploy (covered above) does NOT release.
    function test_movingToNewMultisig_releasesOldBinding() public {
        assertEq(serviceManager.mapMultisigServiceIds(address(agentSafe)), VICTIM_ID);

        // Permit the new-Safe adapter, then move service #1 onto a brand-new Safe.
        serviceRegistry.changeMultisigPermission(address(gnosisSafeMultisig), true);

        _execMasterSafeTx(
            address(serviceManager),
            regDeposit,
            abi.encodeWithSelector(ServiceManager.activateRegistration.selector, VICTIM_ID)
        );
        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 1;
        address[] memory instances = new address[](1);
        instances[0] = agentInstance;
        vm.prank(operator);
        serviceManager.registerAgents{value: regBond}(VICTIM_ID, instances, agentIds);

        // GnosisSafeMultisig creates a fresh Safe (different from the recovery-module agentSafe)
        _execMasterSafeTx(
            address(serviceManager),
            0,
            abi.encodeWithSelector(ServiceManager.deploy.selector, VICTIM_ID, address(gnosisSafeMultisig), bytes(""))
        );

        (, address newMultisig, , , , , ) = serviceRegistry.mapServices(VICTIM_ID);
        assertTrue(newMultisig != address(agentSafe), "expected a different multisig");
        assertEq(serviceManager.mapMultisigServiceIds(newMultisig), VICTIM_ID, "new multisig not claimed");
        assertEq(serviceManager.mapMultisigServiceIds(address(agentSafe)), 0, "old binding not released");
    }

    /// @dev The `mapMultisigServiceIds[lastMultisig] == serviceId` guard is NOT redundant: it protects a
    ///      legit binding from being wiped by a stale service whose registry multisig points at a Safe owned
    ///      by another service (a pre-fix 81064 dangling pointer). Such state is unreachable post-fix, so it
    ///      is emulated with a single storage write to the registry.
    function test_guard_doesNotClearForeignBinding() public {
        assertEq(serviceManager.mapMultisigServiceIds(address(agentSafe)), VICTIM_ID); // V (service #1) owns agentSafe

        serviceRegistry.changeMultisigPermission(address(gnosisSafeMultisig), true);

        // Attacker brings a stale service Z (#2) to FinishedRegistration.
        address attacker = address(0xA77ACE);
        vm.deal(attacker, 100 ether);
        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 1;
        IService.AgentParams[] memory ap = new IService.AgentParams[](1);
        ap[0].slots = 1;
        ap[0].bond = regBond;
        serviceManager.create(attacker, serviceManager.ETH_TOKEN_ADDRESS(), unitHash, agentIds, ap, threshold);
        uint256 zId = 2;
        vm.prank(attacker);
        serviceManager.activateRegistration{value: regDeposit}(zId);
        address[] memory zi = new address[](1);
        zi[0] = backupOwner; // a free EOA as Z's agent instance
        vm.prank(attacker);
        serviceManager.registerAgents{value: regBond}(zId, zi, agentIds);

        // Emulate the dangling pointer: Z.multisig := agentSafe (V's Safe), while map[agentSafe] stays V.
        // mapServices is slot 19; Service packs securityDeposit(uint96)|multisig(address) in its first slot.
        bytes32 slot = keccak256(abi.encode(zId, uint256(19)));
        uint256 cur = uint256(vm.load(address(serviceRegistry), slot));
        uint256 packed = (cur & ((uint256(1) << 96) - 1)) | (uint256(uint160(address(agentSafe))) << 96);
        vm.store(address(serviceRegistry), slot, bytes32(packed));
        (, address zMs, , , , , ) = serviceRegistry.mapServices(zId);
        assertEq(zMs, address(agentSafe), "dangling-pointer emulation failed");

        // Z moves to a fresh Safe. The release branch must NOT clear V's binding (guard: map[agentSafe] != Z).
        vm.prank(attacker);
        serviceManager.deploy(zId, address(gnosisSafeMultisig), bytes(""));

        assertEq(
            serviceManager.mapMultisigServiceIds(address(agentSafe)),
            VICTIM_ID,
            "guard failed: a foreign binding was wiped"
        );
    }
}

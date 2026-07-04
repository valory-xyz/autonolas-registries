// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

// ============================================================================================
// PROPOSAL 24 — de-whitelist same-address multisigs + extend the GuardCM allowlist.
//
// This is the FIRST of the two proposals that replace the original single 41-action bundle,
// which reverted on-chain (tx 0x540c...20f) because its execute() needed ~19.9M gas while
// EIP-7825 (Fusaka) caps a single transaction at 2^24 = 16,777,216 gas. The bundle was split so
// each proposal's execute stays well under that cap. 24 carries the de-whitelists + GuardCM
// batch (~10.3M gas measured on a mainnet fork); the 32 removeNominee calls (~9.55M) are in 25.
//
// Actions (9):
//   (1) DE-WHITELIST the same-address multisig implementations from ServiceRegistry (L1) /
//       ServiceRegistryL2 (every L2) via changeMultisigPermission(address,false) — closing the
//       same-address multisig adoption path. Mainnet direct; each L2 bridged through its mediator
//       (AMB / FxRoot / Arbitrum-retryable / OP-stack). Polygon carries TWO adapters
//       (GnosisSafeSameAddressMultisig + PolySafeSameAddressMultisig), batched in one FxRoot message.
//   (2) EXTEND the GuardCM allowlist via setTargetSelectorChainIds with 19 (target, selector,
//       chainId) emergency-pause/drain triples (all statuses = true).
//
// Bridge encodings and the GuardCM batch are byte-for-byte identical to the original bundle
// (same mediators, same _packed tuple, same MIN_GAS, same Arbitrum retryable params), so the L2
// delivery was already simulated; only the bundling changed.
//
// proposalId = keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))).
// description.txt MUST match the DESCRIPTION string below byte-for-byte before on-chain submission.
// ============================================================================================
abstract contract Proposal24Builder {
    // ---- core ----
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;

    // ---- L1 bridge entry points ----
    address internal constant AMB_L1     = 0x4C36d2919e407f0Cc2Ee3c993ccF8ac26d9CE64e; // Gnosis
    address internal constant FXROOT_L1  = 0xfe5e5D361b2ad62c541bAb87C45a0B9B018389a2; // Polygon
    address internal constant INBOX_L1   = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f; // Arbitrum
    address internal constant OP_L1CDM   = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1; // Optimism
    address internal constant BASE_L1CDM = 0x866E82a600A1414e583f7F13623F1aC5d58b0Afa; // Base
    address internal constant CELO_L1CDM = 0x1AC1181fc4e4F877963680587AEAa2C90D7EbB95; // Celo
    address internal constant MODE_L1CDM = 0x95bDCA6c8EdEB69C98Bd5bd17660BaCef1298A6f; // Mode

    // ---- L2 mediators / messengers ----
    address internal constant HOME_MEDIATOR_L2  = 0x15bd56669F57192a97dF41A2aa8f4403e9491776; // Gnosis
    address internal constant FX_TUNNEL_L2      = 0x9338b5153AE39BB89f50468E608eD9d764B755fD; // Polygon
    address internal constant ARB_MEDIATOR_L2   = 0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F; // Arbitrum (aliased L1 Timelock)
    address internal constant OP_MESSENGER_L2   = 0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c; // Optimism
    address internal constant BASE_MESSENGER_L2 = 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA; // Base
    address internal constant CELO_MESSENGER_L2 = 0xC14E191A64a7FB0e5790a8a0B9a58683dFFce04d; // Celo
    address internal constant MODE_MESSENGER_L2 = 0x9338b5153AE39BB89f50468E608eD9d764B755fD; // Mode

    // ---- ServiceRegistry / ServiceRegistryL2 (de-whitelist targets) ----
    address internal constant SR_MAINNET    = 0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA;
    address internal constant SRL2_GNOSIS   = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;
    address internal constant SRL2_POLYGON  = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address internal constant SRL2_ARBITRUM = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address internal constant SRL2_OPTIMISM = 0x3d77596beb0f130a4415df3D2D8232B3d3D31e44;
    address internal constant SRL2_BASE     = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant SRL2_CELO     = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address internal constant SRL2_MODE     = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;

    // ---- same-address multisig implementations per chain (the implementations being disabled) ----
    address internal constant SAME_MAINNET  = 0xfa517d01DaA100cB1932FA4345F68874f7E7eF46;
    address internal constant SAME_GNOSIS   = 0x6e7f594f680f7aBad18b7a63de50F0FeE47dfD06;
    address internal constant SAME_POLYGON  = 0xd8BCC126ff31d2582018715d5291A508530587b0;
    // Polygon also has a PolySafeSameAddressMultisig (same adopt-existing-Safe primitive, PolySafe proxy hash).
    address internal constant SAME_POLYGON_POLYSAFE = 0xBcb1BAC84B5BcAb350C89c50ADc9064eD15a4485;
    address internal constant SAME_ARBITRUM = 0xBb7e1D6Cb6F243D6bdE81CE92a9f2aFF7Fbe7eac;
    address internal constant SAME_OPTIMISM = 0xb09CcF0Dbf0C178806Aaee28956c74bd66d21f73;
    address internal constant SAME_BASE     = 0xFbBEc0C8b13B38a9aC0499694A69a10204c5E2aB;
    address internal constant SAME_CELO     = 0xBb7e1D6Cb6F243D6bdE81CE92a9f2aFF7Fbe7eac;
    address internal constant SAME_MODE     = 0xFbBEc0C8b13B38a9aC0499694A69a10204c5E2aB;

    uint32 internal constant MIN_GAS = 2_000_000; // changeMultisigPermission is a trivial sstore

    // ---- GuardCM Phase 1 whitelist additions (team-approved Option A0: pure pauses + Mode drain backfill) ----
    // GuardCM is on L1, owned by the Timelock; setTargetSelectorChainIds is a direct L1 call. This is the SAME
    // live guard that holds the Phase 0 batch (verified: Phase 0 triples already true, Phase 1 triples not yet).
    address internal constant GUARD_CM = 0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B;
    bytes4 internal constant SEL_PAUSE           = 0x8456cb59; // pause()
    bytes4 internal constant SEL_SET_PAUSE_STATE = 0x63096509; // setPauseState(uint8)
    bytes4 internal constant SEL_DRAIN           = 0x9890220b; // drain()
    bytes4 internal constant SEL_DRAIN_ADDRESS   = 0xece53132; // drain(address)

    // Arbitrum retryable params — estimated via the Arbitrum SDK estimateAll the same way as
    // scripts/proposals/proposal_15 (default base + maxSubmissionFee/maxFeePerGas +1000% buffers,
    // gasLimit min 2M +30%), then value = deposit * 10. Re-run estimate_arb_submission_cost.js right
    // before submission to refresh against L1 basefee drift.
    uint256 internal constant ARB_MAX_SUBMISSION_COST = 4_944_601_833_776;     // SDK maxSubmissionCost (already +1000%)
    uint256 internal constant ARB_GAS_LIMIT           = 2_000_000;             // SDK gasLimit (2M min)
    uint256 internal constant ARB_MAX_FEE_PER_GAS     = 220_000_000;           // SDK BUFFERED maxFeePerGas (+1000%), not the raw gas price
    uint256 internal constant ARB_RETRYABLE_VALUE     = 4_449_446_018_337_760; // SDK deposit * 10

    // NOTE: regenerate description.txt to match this byte-for-byte before submission.
    string internal constant DESCRIPTION =
        "Olas protocol security hardening and Community Multisig guard whitelist extension. This proposal: (1) de-whitelists the same-address multisig implementations (GnosisSafeSameAddressMultisig on Ethereum and the ServiceRegistryL2 of each supported network: Gnosis, Polygon, Arbitrum, Optimism, Base, Celo, Mode; and additionally the PolySafeSameAddressMultisig on Polygon) by calling changeMultisigPermission(address,false), removing the same-address multisig adoption path from service deployment; and (2) extends the Community Multisig GuardCM allowlist via setTargetSelectorChainIds with 19 additional (target, selector, chainId) combinations enabling emergency pause actions across Ethereum and all supported L2 networks (Dispenser setPauseState, ServiceManager and RegistriesManager pause, and TargetDispenserL2 pause on each L2) together with the Mode ServiceRegistryL2 and ServiceRegistryTokenUtility drain backfill. In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u";

    function buildProposal()
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        // 8 de-whitelist + 1 GuardCM Phase 1 whitelist = 9
        targets = new address[](9);
        values = new uint256[](9);
        calldatas = new bytes[](9);
        uint256 k;

        // ===================== Part 1: de-whitelist same-address multisigs (8) =====================
        // 1.1 mainnet — direct Timelock call
        targets[k] = SR_MAINNET; calldatas[k++] = _changePerm(SAME_MAINNET);
        // 1.2 Gnosis (AMB)
        targets[k] = AMB_L1; calldatas[k++] = _gnosis();
        // 1.3 Polygon (FxRoot) — two adapters batched
        targets[k] = FXROOT_L1; calldatas[k++] = _polygon();
        // 1.4 Arbitrum (Inbox retryable — carries value; recompute at submission)
        targets[k] = INBOX_L1; values[k] = ARB_RETRYABLE_VALUE; calldatas[k++] = _arbitrum();
        // 1.5 Optimism / Base / Celo / Mode (OP-stack)
        targets[k] = OP_L1CDM;   calldatas[k++] = _opStack(OP_MESSENGER_L2,   SRL2_OPTIMISM, SAME_OPTIMISM);
        targets[k] = BASE_L1CDM; calldatas[k++] = _opStack(BASE_MESSENGER_L2, SRL2_BASE,     SAME_BASE);
        targets[k] = CELO_L1CDM; calldatas[k++] = _opStack(CELO_MESSENGER_L2, SRL2_CELO,     SAME_CELO);
        targets[k] = MODE_L1CDM; calldatas[k++] = _opStack(MODE_MESSENGER_L2, SRL2_MODE,     SAME_MODE);

        // ===================== Part 2: GuardCM Phase 1 whitelist additions (1 call, direct L1) =====================
        targets[k] = GUARD_CM; calldatas[k++] = _phase1Allowlist();

        require(k == 9, "length mismatch");
        description = DESCRIPTION;
    }

    /// @dev GuardCM Phase 1 (Option A0): 19 (target, selector, chainId) triples, all statuses = true (additions).
    function _phase1Allowlist() internal pure returns (bytes memory) {
        (address[] memory t, bytes4[] memory s, uint256[] memory c, bool[] memory st) = phase1Triples();
        return abi.encodeWithSignature(
            "setTargetSelectorChainIds(address[],bytes4[],uint256[],bool[])", t, s, c, st);
    }

    /// @dev The 19 Phase 1 triples (exposed so fork tests can assert each landed). statuses all true.
    function phase1Triples()
        public pure returns (address[] memory t, bytes4[] memory s, uint256[] memory c, bool[] memory st)
    {
        t = new address[](19);
        s = new bytes4[](19);
        c = new uint256[](19);
        st = new bool[](19);
        t[0] = 0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0; s[0] = SEL_SET_PAUSE_STATE; c[0] = 1; st[0] = true; // Dispenser.setPauseState
        t[1] = 0x94a1892D91c05D0C61c3f49F42205D2285b914c9; s[1] = SEL_PAUSE; c[1] = 1; st[1] = true; // ServiceManagerProxy (mainnet)
        t[2] = 0x9eC9156dEF5C613B2a7D4c46C383F9B58DfcD6fE; s[2] = SEL_PAUSE; c[2] = 1; st[2] = true; // RegistriesManager
        t[3] = 0xA5C7FbCCFf28441b7d250412b0Fb87AA1c8b14AD; s[3] = SEL_PAUSE; c[3] = 10; st[3] = true; // ServiceManagerProxy (Optimism)
        t[4] = 0xaea9ef993d8a1A164397642648DF43F053d43D85; s[4] = SEL_PAUSE; c[4] = 10; st[4] = true; // OptimismTargetDispenserL2
        t[5] = 0x068a4f0946cF8c7f9C1B58a3b5243Ac8843bf473; s[5] = SEL_PAUSE; c[5] = 100; st[5] = true; // ServiceManagerProxy (Gnosis)
        t[6] = 0x5b6c538C7b2E0b44Fa8A3B7a0532EF797b07d0E9; s[6] = SEL_PAUSE; c[6] = 100; st[6] = true; // GnosisTargetDispenserL2
        t[7] = 0xE3e5Df46060370af5Fd37B2aA11e7dac3cCB4bd0; s[7] = SEL_PAUSE; c[7] = 137; st[7] = true; // ServiceManagerProxy (Polygon)
        t[8] = 0x17d96ba4532fe91809326092fE4D5606A7B7a0d8; s[8] = SEL_PAUSE; c[8] = 137; st[8] = true; // PolygonTargetDispenserL2
        t[9] = 0x1262136cac6a06A782DC94eb3a3dF0b4d09FF6A6; s[9] = SEL_PAUSE; c[9] = 8453; st[9] = true; // ServiceManagerProxy (Base)
        t[10] = 0x9Ec97Be9FF55ff11606ce7c589956f7Bf3D0b241; s[10] = SEL_PAUSE; c[10] = 8453; st[10] = true; // BaseTargetDispenserL2
        t[11] = 0xcDdD9D9ABaB36fFa882530D69c73FeE5D4001C2d; s[11] = SEL_PAUSE; c[11] = 34443; st[11] = true; // ServiceManagerProxy (Mode)
        t[12] = 0xEB5638eefE289691EcE01943f768EDBF96258a80; s[12] = SEL_PAUSE; c[12] = 34443; st[12] = true; // ModeTargetDispenserL2
        t[13] = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE; s[13] = SEL_DRAIN; c[13] = 34443; st[13] = true; // ServiceRegistryL2.drain (Mode)
        t[14] = 0x34C895f302D0b5cf52ec0Edd3945321EB0f83dd5; s[14] = SEL_DRAIN_ADDRESS; c[14] = 34443; st[14] = true; // ServiceRegistryTokenUtility.drain (Mode)
        t[15] = 0xD421f433e36465B3e558B1121F584ac09Fc33DF8; s[15] = SEL_PAUSE; c[15] = 42161; st[15] = true; // ServiceManagerProxy (Arbitrum)
        t[16] = 0x5953f21495BD9aF1D78e87bb42AcCAA55C1e896C; s[16] = SEL_PAUSE; c[16] = 42161; st[16] = true; // ArbitrumTargetDispenserL2
        t[17] = 0x84B4DA67B37B1EA1dea9c7044042C1d2297b80a0; s[17] = SEL_PAUSE; c[17] = 42220; st[17] = true; // ServiceManagerProxy (Celo)
        t[18] = 0x4891f5894634DcD6d11644fe8E56756EF2681582; s[18] = SEL_PAUSE; c[18] = 42220; st[18] = true; // CeloTargetDispenserL2
    }

    // ---------------- helpers ----------------

    /// @dev changeMultisigPermission(adapter, false) — disable the implementation.
    function _changePerm(address adapter) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("changeMultisigPermission(address,bool)", adapter, false);
    }

    /// @dev Olas bridge packing: target(20) | value(uint96=0) | payloadLength(uint32) | payload.
    function _packed(address target, bytes memory inner) internal pure returns (bytes memory) {
        return abi.encodePacked(target, uint96(0), uint32(inner.length), inner);
    }

    /// @dev OP-stack (Optimism/Base/Celo/Mode): sendMessage on the L1CrossDomainMessenger.
    function _opStack(address l2messenger, address registry, address adapter) internal pure returns (bytes memory) {
        bytes memory l2call = abi.encodeWithSignature("processMessageFromSource(bytes)", _packed(registry, _changePerm(adapter)));
        return abi.encodeWithSignature("sendMessage(address,bytes,uint32)", l2messenger, l2call, MIN_GAS);
    }

    /// @dev Gnosis (AMB): requireToPassMessage(HomeMediator, processMessageFromForeign(packed), gas).
    function _gnosis() internal pure returns (bytes memory) {
        bytes memory l2call = abi.encodeWithSignature("processMessageFromForeign(bytes)", _packed(SRL2_GNOSIS, _changePerm(SAME_GNOSIS)));
        return abi.encodeWithSignature("requireToPassMessage(address,bytes,uint256)", HOME_MEDIATOR_L2, l2call, uint256(MIN_GAS));
    }

    /// @dev Polygon (FxRoot): sendMessageToChild(FxGovernorTunnel, packed). Polygon carries TWO same-address
    ///      adapters (GnosisSafeSameAddressMultisig + PolySafeSameAddressMultisig), batched as two concatenated
    ///      tuples in one message (FxGovernorTunnel.processMessageFromRoot loops over them).
    function _polygon() internal pure returns (bytes memory) {
        bytes memory packed = bytes.concat(
            _packed(SRL2_POLYGON, _changePerm(SAME_POLYGON)),
            _packed(SRL2_POLYGON, _changePerm(SAME_POLYGON_POLYSAFE)));
        return abi.encodeWithSignature("sendMessageToChild(address,bytes)", FX_TUNNEL_L2, packed);
    }

    /// @dev Arbitrum (Inbox): direct retryable to the L2 registry; refunds to the aliased L1 Timelock.
    function _arbitrum() internal pure returns (bytes memory) {
        // excessFeeRefund = aliased L1 Timelock (ARB_MEDIATOR_L2); callValueRefund = address(0) (l2CallValue 0).
        return abi.encodeWithSignature(
            "createRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)",
            SRL2_ARBITRUM, uint256(0), ARB_MAX_SUBMISSION_COST,
            ARB_MEDIATOR_L2, address(0), ARB_GAS_LIMIT,
            ARB_MAX_FEE_PER_GAS, _changePerm(SAME_ARBITRUM));
    }
}

/// @notice forge script scripts/proposals/proposal_24_dewhitelist_and_guard/Proposal24DewhitelistAndGuard.s.sol:Proposal24DewhitelistAndGuard
contract Proposal24DewhitelistAndGuard is Script, Proposal24Builder {
    function run() external view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();
        console2.log("=== Proposal 24: de-whitelist same-address multisigs + GuardCM Phase 1 ===");
        console2.log("entries:", targets.length);
        for (uint256 i; i < targets.length; ++i) {
            console2.log("--- index", i, "---");
            console2.log("target  :", targets[i]);
            console2.log("value   :", values[i]);
            console2.logBytes(calldatas[i]);
        }
        console2.log("description:");
        console2.log(description);
        bytes32 id = keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description))));
        console2.log("proposalId:");
        console2.logBytes32(id);
    }
}

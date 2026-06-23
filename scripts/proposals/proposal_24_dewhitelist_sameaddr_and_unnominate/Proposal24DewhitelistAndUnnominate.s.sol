// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

// ============================================================================================
// PRIVATE STAGING COPY — do NOT push to the public autonolas-governance repo.
// Builds a single GovernorOLAS proposal that:
//   (1) DE-WHITELISTS the GnosisSafeSameAddressMultisig implementation from ServiceRegistry (L1) /
//       ServiceRegistryL2 (every L2) via changeMultisigPermission(address,false) — closing the
//       same-address multisig adoption path; and
//   (2) UN-NOMINATES a set of staking contracts from VoteWeighting via removeNominee(bytes32,uint256).
//
// Bridge encodings mirror proposals/proposal_11_sm_update/Proposal11SmUpdate.s.sol verbatim
// (same mediators, same _packed tuple, same OP-stack / AMB / FxRoot / Arbitrum-retryable shapes).
// Only the inner calldata differs: changeMultisigPermission(sameAddr,false) instead of changeImplementation.
//
// OWNERSHIP (verified on-chain): every target registry's owner is the chain's mediator (or the Timelock on
// L1), so all 8 de-whitelist calls are governance-reachable — INCLUDING Mode (its SRL2 owner is the Mode
// OptimismMessenger 0x9338…755fD, unlike the Mode SM proxy which was EOA-owned and excluded from proposal 11).
// VoteWeighting is on L1 and owned by the Timelock; removeNominee is owner-only and reverts NomineeDoesNotExist
// if a target is not a live nominee — all 32 below are currently nominated.
//
// Arbitrum retryable params are placeholders (mirror proposal_11): RECOMPUTE maxSubmissionCost/gasLimit/
// maxFeePerGas and the entry value at submission via the Arbitrum SDK. The msg.value is supplied by the
// executor of execute(); it flows Governor -> Timelock -> Inbox (the Timelock needs no balance).
//
// proposalId = keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))).
// description.txt MUST match the DESCRIPTION string below byte-for-byte before on-chain submission.
// ============================================================================================
abstract contract Proposal24Builder {
    // ---- core ----
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant VOTE_WEIGHTING = 0x95418b46d5566D3d1ea62C12Aea91227E566c5c1;

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

    // ---- GnosisSafeSameAddressMultisig per chain (the implementation being disabled) ----
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

    // ---- chain ids ----
    uint256 internal constant CID_MAINNET  = 1;
    uint256 internal constant CID_OPTIMISM = 10;
    uint256 internal constant CID_GNOSIS   = 100;
    uint256 internal constant CID_POLYGON  = 137;
    uint256 internal constant CID_BASE     = 8453;
    uint256 internal constant CID_CELO     = 42220;
    uint256 internal constant CID_ARBITRUM = 42161;
    uint256 internal constant CID_MODE     = 34443;

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
    // autonolas-registries/scripts/proposals/proposal_15 (default base + maxSubmissionFee/maxFeePerGas
    // +1000% buffers, gasLimit min 2M +30%), then value = deposit * 10. Concrete baked values from
    // scripts/proposals/_estimate_arb_proposal24.js (re-run right before submission to refresh).
    uint256 internal constant ARB_MAX_SUBMISSION_COST = 4_944_601_833_776;     // SDK maxSubmissionCost (already +1000%)
    uint256 internal constant ARB_GAS_LIMIT           = 2_000_000;             // SDK gasLimit (2M min)
    uint256 internal constant ARB_MAX_FEE_PER_GAS     = 220_000_000;           // SDK BUFFERED maxFeePerGas (+1000%), not the raw gas price
    uint256 internal constant ARB_RETRYABLE_VALUE     = 4_449_446_018_337_760; // SDK deposit * 10

    // NOTE: regenerate description.txt to match this byte-for-byte before submission.
    string internal constant DESCRIPTION =
        "Olas protocol security hardening, staking nominee cleanup, and Community Multisig guard whitelist extension. This proposal: (1) de-whitelists the same-address multisig implementations (GnosisSafeSameAddressMultisig on Ethereum and the ServiceRegistryL2 of each supported network: Gnosis, Polygon, Arbitrum, Optimism, Base, Celo, Mode; and additionally the PolySafeSameAddressMultisig on Polygon) by calling changeMultisigPermission(address,false), removing the same-address multisig adoption path from service deployment; (2) removes a set of staking contract nominees from the VoteWeighting contract by calling removeNominee(bytes32,uint256) for the corresponding (account, chainId) pairs across Ethereum, Gnosis, Base, Polygon, Optimism, Celo and Arbitrum; and (3) extends the Community Multisig GuardCM allowlist via setTargetSelectorChainIds with 19 additional (target, selector, chainId) combinations enabling emergency pause actions across Ethereum and all supported L2 networks (Dispenser setPauseState, ServiceManager and RegistriesManager pause, and TargetDispenserL2 pause on each L2) together with the Mode ServiceRegistryL2 and ServiceRegistryTokenUtility drain backfill. In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u";

    function buildProposal()
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        // 8 de-whitelist + 32 un-nominate + 1 GuardCM Phase 1 whitelist = 41
        targets = new address[](41);
        values = new uint256[](41);
        calldatas = new bytes[](41);
        uint256 k;

        // ===================== Part 1: de-whitelist GnosisSafeSameAddressMultisig (8) =====================
        // 1.1 mainnet — direct Timelock call
        targets[k] = SR_MAINNET; calldatas[k++] = _changePerm(SAME_MAINNET);
        // 1.2 Gnosis (AMB)
        targets[k] = AMB_L1; calldatas[k++] = _gnosis();
        // 1.3 Polygon (FxRoot)
        targets[k] = FXROOT_L1; calldatas[k++] = _polygon();
        // 1.4 Arbitrum (Inbox retryable — carries value; recompute at submission)
        targets[k] = INBOX_L1; values[k] = ARB_RETRYABLE_VALUE; calldatas[k++] = _arbitrum();
        // 1.5 Optimism / Base / Celo / Mode (OP-stack)
        targets[k] = OP_L1CDM;   calldatas[k++] = _opStack(OP_MESSENGER_L2,   SRL2_OPTIMISM, SAME_OPTIMISM);
        targets[k] = BASE_L1CDM; calldatas[k++] = _opStack(BASE_MESSENGER_L2, SRL2_BASE,     SAME_BASE);
        targets[k] = CELO_L1CDM; calldatas[k++] = _opStack(CELO_MESSENGER_L2, SRL2_CELO,     SAME_CELO);
        targets[k] = MODE_L1CDM; calldatas[k++] = _opStack(MODE_MESSENGER_L2, SRL2_MODE,     SAME_MODE);

        // ===================== Part 2: un-nominate staking contracts (32) =====================
        // VoteWeighting lives on L1 and tracks nominees for all chains via the chainId arg, so every call is
        // a DIRECT L1 Timelock call regardless of where the staking contract is deployed.

        // -- Gnosis (100): QS Mech MarketPlace Expert 1..13, MarketPlace Demand Alpha 1 & 2, Supply Alpha (16) --
        k = _rm(targets, calldatas, k, 0xdB9E2713c3dA3C403F2eA6E570eB978b00304e9E, CID_GNOSIS); // Expert 1
        k = _rm(targets, calldatas, k, 0x1E90522b45c771DCF5f79645B9e96551d2ECaF62, CID_GNOSIS); // Expert 2
        k = _rm(targets, calldatas, k, 0x75EECA6207be98cAc3fDE8a20eCd7B01e50b3472, CID_GNOSIS); // Expert 3
        k = _rm(targets, calldatas, k, 0x9c7F6103e3a72E4d1805b9C683Ea5B370Ec1a99f, CID_GNOSIS); // Expert 4
        k = _rm(targets, calldatas, k, 0xcdC603e0Ee55Aae92519f9770f214b2Be4967f7d, CID_GNOSIS); // Expert 5
        k = _rm(targets, calldatas, k, 0x22D6cd3d587D8391C3aAE83a783f26c67ab54A85, CID_GNOSIS); // Expert 6
        k = _rm(targets, calldatas, k, 0xaaEcdf4d0CBd6Ca0622892Ac6044472f3912A5f3, CID_GNOSIS); // Expert 7
        k = _rm(targets, calldatas, k, 0x168aED532a0CD8868c22Fc77937Af78b363652B1, CID_GNOSIS); // Expert 8
        k = _rm(targets, calldatas, k, 0xdDa9cD214F12e7C2D58E871404A0A3B1177065C8, CID_GNOSIS); // Expert 9
        k = _rm(targets, calldatas, k, 0x53a38655B4e659eF4C7F88A26fbF5c67932C7156, CID_GNOSIS); // Expert 10
        k = _rm(targets, calldatas, k, 0x1eaDe40561C61fa7AcC5D816b1FC55a8d9B58519, CID_GNOSIS); // Expert 11
        k = _rm(targets, calldatas, k, 0x99Fe6B5C9980Fc3A44b1Dc32A76Db6aDfcf4c75e, CID_GNOSIS); // Expert 12
        k = _rm(targets, calldatas, k, 0x1F81cF353051dAA8919d1777c58b667025794dDc, CID_GNOSIS); // Expert 13
        k = _rm(targets, calldatas, k, 0x9d6e7aB0B5B48aE5c146936147C639fEf4575231, CID_GNOSIS); // Demand Alpha 1
        k = _rm(targets, calldatas, k, 0x9fb17E549FefcCA630dd92Ea143703CeE4Ea4340, CID_GNOSIS); // Demand Alpha 2
        k = _rm(targets, calldatas, k, 0xCAbD0C941E54147D40644CF7DA7e36d70DF46f44, CID_GNOSIS); // Supply Alpha

        // -- Base (8453): OneSoul x2, Agents.fun 4, Supply Alpha, Contribute Beta I/II/III, Demand Alpha 1/2, 2x n/a (11) --
        k = _rm(targets, calldatas, k, 0x4D804a665097855b1158CD8045A819ee9fD0e540, CID_BASE); // OneSoul (1)
        k = _rm(targets, calldatas, k, 0xc279Cf9Fc8DD0c4A58227ef1189cbb3f0f575F40, CID_BASE); // OneSoul (2)
        k = _rm(targets, calldatas, k, 0xb93607d2173f847a18567809dB51345d4EA38bAd, CID_BASE); // Agents.fun 4
        k = _rm(targets, calldatas, k, 0xB14Cd66c6c601230EA79fa7Cc072E5E0C2F3A756, CID_BASE); // Supply Alpha
        k = _rm(targets, calldatas, k, 0xe2E68dDafbdC0Ae48E39cDd1E778298e9d865cF4, CID_BASE); // Contribute Beta I
        k = _rm(targets, calldatas, k, 0x6Ce93E724606c365Fc882D4D6dfb4A0a35fE2387, CID_BASE); // Contribute Beta II
        k = _rm(targets, calldatas, k, 0x28877FFc6583170a4C9eD0121fc3195d06fd3A26, CID_BASE); // Contribute Beta III
        k = _rm(targets, calldatas, k, 0x38Eb3838Dab06932E7E1E965c6F922aDfE494b88, CID_BASE); // Demand Alpha 1
        k = _rm(targets, calldatas, k, 0xBE6E12364B549622395999dB0dB53f163994D7AF, CID_BASE); // Demand Alpha 2
        k = _rm(targets, calldatas, k, 0x66A92CDa5B319DCCcAC6c1cECbb690CA3Fb59488, CID_BASE); // n/a (id 9)
        k = _rm(targets, calldatas, k, 0x51c5f4982B9b0B3c0482678f5847EA6228Cc8E54, CID_BASE); // n/a (id 2)

        // -- single cross-chain MarketPlace Supply Alpha deployments (5) --
        k = _rm(targets, calldatas, k, 0xBB375C8d8517e6956AF7044Fe676F2100505624f, CID_OPTIMISM); // Supply Alpha
        k = _rm(targets, calldatas, k, 0x3aE11E2dd9a055af3dA61Ae2e36515D1612d7D93, CID_POLYGON);  // Supply Alpha
        k = _rm(targets, calldatas, k, 0x5A40e2661b3eE672e945445f885f975a51a6C461, CID_MAINNET);  // Supply Alpha
        k = _rm(targets, calldatas, k, 0x6cc3A0d25E2AC7D8fF119Ef92d5523259C6DC821, CID_CELO);     // Supply Alpha
        k = _rm(targets, calldatas, k, 0x646EcBE31DF12D17a949d65764187408f6bb095d, CID_ARBITRUM); // Supply Alpha

        // ===================== Part 3: GuardCM Phase 1 whitelist additions (1 call, direct L1) =====================
        targets[k] = GUARD_CM; calldatas[k++] = _phase1Allowlist();

        require(k == 41, "length mismatch");
        description = DESCRIPTION;
    }

    /// @dev GuardCM Phase 1 (Option A0): 19 (target, selector, chainId) triples, all statuses = true (additions).
    ///      Pure pauses across Ethereum + 7 L2s, plus the Mode drain backfill that Phase 0 omitted.
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

    /// @dev removeNominee(bytes32 account, uint256 chainId) on VoteWeighting (direct L1).
    function _rm(address[] memory targets, bytes[] memory calldatas, uint256 k, address account, uint256 chainId)
        internal pure returns (uint256)
    {
        targets[k] = VOTE_WEIGHTING;
        calldatas[k] = abi.encodeWithSignature("removeNominee(bytes32,uint256)", bytes32(uint256(uint160(account))), chainId);
        return k + 1;
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
        // Mirrors proposal_15's createRetryableTicket argument shape.
        return abi.encodeWithSignature(
            "createRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)",
            SRL2_ARBITRUM, uint256(0), ARB_MAX_SUBMISSION_COST,
            ARB_MEDIATOR_L2, address(0), ARB_GAS_LIMIT,
            ARB_MAX_FEE_PER_GAS, _changePerm(SAME_ARBITRUM));
    }
}

/// @notice forge script proposals/proposal_24_dewhitelist_sameaddr_and_unnominate/Proposal24DewhitelistAndUnnominate.s.sol:Proposal24DewhitelistAndUnnominate
contract Proposal24DewhitelistAndUnnominate is Script, Proposal24Builder {
    function run() external view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();
        console2.log("=== Proposal 24: de-whitelist GnosisSafeSameAddressMultisig + un-nominate ===");
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

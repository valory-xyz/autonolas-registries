// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

// ============================================================================================
// PROPOSAL 24b — un-nominate retired staking contracts from VoteWeighting.
//
// This is the SECOND of the two proposals that replace the original single 41-action proposal 24,
// which reverted on-chain (tx 0x540c...20f) because its execute() needed ~19.9M gas while
// EIP-7825 (Fusaka) caps a single transaction at 2^24 = 16,777,216 gas. 24b carries only the 32
// removeNominee calls (~9.55M gas measured on a mainnet fork); the de-whitelists + GuardCM batch
// (~10.3M) are in 24a. Both stay comfortably under the cap.
//
// Action (32): VoteWeighting.removeNominee(bytes32 account, uint256 chainId) for each retired
// (account, chainId) pair. VoteWeighting lives on L1 and tracks nominees for every chain via the
// chainId argument, so ALL 32 calls are DIRECT L1 Timelock calls regardless of where the staking
// contract is deployed — there are NO L2 bridge messages in this proposal.
//
// TIMING: removeNominee routes through Dispenser.removeNominee, which reverts Overflow if called
// within the last week of the ongoing epoch (block.timestamp >= epochEnd - 1 week). This proposal
// MUST be executed with > 7 days left in the epoch (epoch length is 14 days). removeNominee is
// owner-only and reverts NomineeDoesNotExist if a target is not a live nominee — all 32 are
// currently nominated.
//
// proposalId = keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))).
// description.txt MUST match the DESCRIPTION string below byte-for-byte before on-chain submission.
// ============================================================================================
abstract contract Proposal24bBuilder {
    address internal constant VOTE_WEIGHTING = 0x95418b46d5566D3d1ea62C12Aea91227E566c5c1;

    // ---- chain ids ----
    uint256 internal constant CID_MAINNET  = 1;
    uint256 internal constant CID_OPTIMISM = 10;
    uint256 internal constant CID_GNOSIS   = 100;
    uint256 internal constant CID_POLYGON  = 137;
    uint256 internal constant CID_BASE     = 8453;
    uint256 internal constant CID_CELO     = 42220;
    uint256 internal constant CID_ARBITRUM = 42161;

    // NOTE: regenerate description.txt to match this byte-for-byte before submission.
    string internal constant DESCRIPTION =
        "Olas staking nominee cleanup. This proposal removes a set of retired staking contract nominees from the VoteWeighting contract by calling removeNominee(bytes32,uint256) for the corresponding (account, chainId) pairs across Ethereum, Gnosis, Base, Polygon, Optimism, Celo and Arbitrum. In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u";

    function buildProposal()
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](32);
        values = new uint256[](32);
        calldatas = new bytes[](32);
        uint256 k;

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

        require(k == 32, "length mismatch");
        description = DESCRIPTION;
    }

    /// @dev removeNominee(bytes32 account, uint256 chainId) on VoteWeighting (direct L1).
    function _rm(address[] memory targets, bytes[] memory calldatas, uint256 k, address account, uint256 chainId)
        internal pure returns (uint256)
    {
        targets[k] = VOTE_WEIGHTING;
        calldatas[k] = abi.encodeWithSignature("removeNominee(bytes32,uint256)", bytes32(uint256(uint160(account))), chainId);
        return k + 1;
    }
}

/// @notice forge script scripts/proposals/proposal_24b_unnominate/Proposal24bUnnominate.s.sol:Proposal24bUnnominate
contract Proposal24bUnnominate is Script, Proposal24bBuilder {
    function run() external view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();
        console2.log("=== Proposal 24b: un-nominate staking contracts ===");
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

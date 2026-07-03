// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal24bBuilder} from "../scripts/proposals/proposal_24b_unnominate/Proposal24bUnnominate.s.sol";

// Minimal OZ-Governor surface (GovernorOLAS).
interface IGovernor {
    function propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) external returns (uint256);
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);
    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external returns (uint256);
    function execute(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external payable returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
    function votingDelay() external view returns (uint256);
    function votingPeriod() external view returns (uint256);
    function proposalEta(uint256 proposalId) external view returns (uint256);
}

interface ITimelock { function hasRole(bytes32 role, address account) external view returns (bool); }
interface IVoteWeighting { function mapNomineeIds(bytes32 nomineeHash) external view returns (uint256); }

/// @notice Full governance lifecycle (propose -> vote -> queue -> execute) for proposal 24b on a MAINNET fork,
///         through the CURRENTLY-LIVE GovernorOLAS. Asserts every one of the 32 nominees is removed from
///         VoteWeighting. All 32 removeNominee calls are DIRECT L1 calls (VoteWeighting tracks all chains via
///         the chainId arg), so there is NO L2 propagation to simulate for this proposal.
///
///         This proposal exists because the original single 41-action proposal 24 reverted on-chain at the
///         EIP-7825 per-tx gas cap (2^24 = 16,777,216); 24b is the sub-cap nominee-cleanup half.
///         Run: forge test --match-contract Proposal24bForkL1Test -vvv
contract Proposal24bForkL1Test is Test, Proposal24bBuilder {
    address internal constant NEW_GOV = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6; // live GovernorOLAS
    address internal constant WVEOLAS = 0x4039B809E0C0Ad04F6Fc880193366b251dDf4B40;
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant TOKENOMICS = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300; // gitleaks:allow - public TokenomicsProxy address, not a secret
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    uint8 internal constant SUCCEEDED = 4;
    uint8 internal constant EXECUTED = 7;

    /// @dev `Dispenser.removeNominee` reverts Overflow if called within the last week of the ongoing epoch
    ///      (block.timestamp >= epochEnd - 1 week). That is an operational SCHEDULING constraint on when the
    ///      proposal may execute, not a proposal defect. Mock the epoch end so the allowed window is open. In
    ///      production the proposal must simply be executed with > 7 days left in the epoch.
    function _openEpochTimingWindow() internal {
        vm.mockCall(TOKENOMICS, abi.encodeWithSelector(bytes4(keccak256("getEpochEndTime(uint256)"))), abi.encode(block.timestamp));
    }

    function _mockVotes() internal {
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastTotalSupply(uint256)"))), abi.encode(uint256(1e24)));
    }

    /// @dev Assert every removeNominee actually removed its nominee.
    function _assertNomineesRemoved(address[] memory targets, bytes[] memory calldatas) internal view {
        uint256 removed;
        for (uint256 i; i < targets.length; ++i) {
            assertEq(targets[i], VOTE_WEIGHTING, "unexpected target");
            bytes memory cd = calldatas[i];
            bytes32 acct; uint256 cid;
            assembly {
                acct := mload(add(cd, 0x24)) // 0x20 (len) + 0x04 (selector) -> account (bytes32)
                cid := mload(add(cd, 0x44)) // next word -> chainId
            }
            bytes32 h = keccak256(abi.encode(acct, cid));
            assertEq(IVoteWeighting(VOTE_WEIGHTING).mapNomineeIds(h), 0, "nominee not removed");
            removed++;
        }
        assertEq(removed, 32, "expected 32 nominee removals");
    }

    function test_preconditions() public {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        assertTrue(ITimelock(TIMELOCK).hasRole(PROPOSER_ROLE, NEW_GOV), "NEW_GOV not the live proposer");
        // sample: Gnosis Expert 1 is a live nominee
        bytes32 h1 = keccak256(abi.encode(bytes32(uint256(uint160(0xdB9E2713c3dA3C403F2eA6E570eB978b00304e9E))), uint256(100)));
        assertGt(IVoteWeighting(VOTE_WEIGHTING).mapNomineeIds(h1), 0, "Expert 1 not a live nominee");
    }

    function test_L1_fullGovernanceLifecycle() public {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        _mockVotes();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) = buildProposal();
        bytes32 dh = keccak256(bytes(description));
        IGovernor gov = IGovernor(NEW_GOV);

        address proposer = makeAddr("proposer");
        address voter = makeAddr("voter");

        vm.prank(proposer);
        uint256 id = gov.propose(targets, values, calldatas, description);
        console2.log("proposed id:", id);

        vm.roll(block.number + gov.votingDelay() + 1);
        vm.prank(voter);
        gov.castVote(id, 1);

        vm.roll(block.number + gov.votingPeriod() + 1);
        assertEq(gov.state(id), SUCCEEDED, "not Succeeded");

        gov.queue(targets, values, calldatas, dh);
        uint256 eta = gov.proposalEta(id);
        if (eta >= block.timestamp) vm.warp(eta + 1);
        _openEpochTimingWindow(); // mock AFTER warp so it binds to the execution timestamp
        gov.execute(targets, values, calldatas, dh);
        assertEq(gov.state(id), EXECUTED, "not Executed");

        _assertNomineesRemoved(targets, calldatas);
        console2.log("L1 24b effects asserted: 32 nominees removed");
    }

    /// @dev Fast path: execute directly as the Timelock (no governor), same assertions.
    function test_L1_fullProposal_executesAsTimelock() public {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) = buildProposal();

        _openEpochTimingWindow();
        vm.startPrank(TIMELOCK);
        for (uint256 i; i < targets.length; ++i) {
            (bool ok, bytes memory ret) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!ok) {
                console2.log("reverted at index", i, "target", targets[i]);
                if (ret.length > 0) { assembly { revert(add(ret, 0x20), mload(ret)) } }
                revert("call failed");
            }
        }
        vm.stopPrank();

        _assertNomineesRemoved(targets, calldatas);
    }
}

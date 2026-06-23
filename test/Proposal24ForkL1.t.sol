// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal24Builder} from "../scripts/proposals/proposal_24_dewhitelist_sameaddr_and_unnominate/Proposal24DewhitelistAndUnnominate.s.sol";

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
    function hashProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external pure returns (uint256);
}

interface ITimelock { function hasRole(bytes32 role, address account) external view returns (bool); }
interface IServiceRegistry { function mapMultisigs(address multisig) external view returns (bool); }
interface IVoteWeighting { function mapNomineeIds(bytes32 nomineeHash) external view returns (uint256); }
interface IGuardCM { function getTargetSelectorChainId(address target, bytes4 selector, uint256 chainId) external view returns (bool); }

/// @notice Full governance lifecycle (propose -> vote -> queue -> execute) for proposal 24 on a MAINNET fork,
///         through the CURRENTLY-LIVE GovernorOLAS (NEW_GOV; proposal 11 already migrated the Timelock roles).
///         Proves the L1-observable effects all land: the mainnet GnosisSafeSameAddressMultisig is de-whitelisted
///         and every one of the 32 nominees is removed from VoteWeighting. The 7 L2 de-whitelists are bridge
///         ENQUEUES here (their L1 calls must not revert); their L2 effect is verified in the L2 fork tests.
///         The Arbitrum entry's maxSubmissionCost is recomputed to the live Inbox fee and the value is supplied
///         by the EXECUTOR (flows executor -> Governor -> Timelock -> Inbox; the Timelock needs no balance).
///         Run: forge test --match-contract Proposal24ForkL1Test -vvv   (uses ETH_RPC or a public RPC)
contract Proposal24ForkL1Test is Test, Proposal24Builder {
    address internal constant NEW_GOV = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6; // live GovernorOLAS
    address internal constant WVEOLAS = 0x4039B809E0C0Ad04F6Fc880193366b251dDf4B40;
    address internal constant TOKENOMICS = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300; // gitleaks:allow - public TokenomicsProxy address, not a secret
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    uint8 internal constant SUCCEEDED = 4;
    uint8 internal constant EXECUTED = 7;

    /// @dev `Dispenser.removeNominee` reverts Overflow if called within the last week of the ongoing epoch
    ///      (block.timestamp >= epochEnd - 1 week). That is an operational SCHEDULING constraint on when the
    ///      proposal may execute, not a proposal defect. To exercise the removal logic regardless of where the
    ///      fork block sits in the epoch, mock the epoch end so the allowed window is open. In production the
    ///      proposal must simply be executed with > 7 days left in the epoch.
    function _openEpochTimingWindow() internal {
        vm.mockCall(TOKENOMICS, abi.encodeWithSelector(bytes4(keccak256("getEpochEndTime(uint256)"))), abi.encode(block.timestamp));
    }

    /// @dev The proposal is built with concrete, SDK-estimated Arbitrum retryable params already baked in
    ///      (proposal_15 method: +1000% buffers, value = deposit*10), so the fork test uses them verbatim —
    ///      no live recompute, and the staging proposalId is the one that will be submitted. totalValue is the
    ///      sum of entry values (only the Arbitrum entry carries one).
    function _forkProposal()
        internal pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description, uint256 totalValue)
    {
        (targets, values, calldatas, description) = buildProposal();
        for (uint256 i; i < values.length; ++i) totalValue += values[i];
    }

    function _mockVotes() internal {
        // Keep votes under the uint96 weight cap but well above threshold (5000 OLAS) + quorum.
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastTotalSupply(uint256)"))), abi.encode(uint256(1e24)));
    }

    /// @dev Assert every L1-observable effect of the proposal.
    function _assertL1Effects(address[] memory targets, bytes[] memory calldatas) internal view {
        // (1) mainnet adapter de-whitelisted
        assertFalse(IServiceRegistry(SR_MAINNET).mapMultisigs(SAME_MAINNET), "mainnet adapter still whitelisted");
        // (2) every removeNominee (target == VoteWeighting) actually removed the nominee
        uint256 removed;
        for (uint256 i; i < targets.length; ++i) {
            if (targets[i] != VOTE_WEIGHTING) continue;
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

        // (3) all 19 GuardCM Phase 1 triples are now whitelisted
        (address[] memory gt, bytes4[] memory gs, uint256[] memory gc,) = phase1Triples();
        for (uint256 i; i < gt.length; ++i) {
            assertTrue(IGuardCM(GUARD_CM).getTargetSelectorChainId(gt[i], gs[i], gc[i]), "GuardCM triple not set");
        }
    }

    function test_preconditions() public {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        assertTrue(ITimelock(TIMELOCK).hasRole(PROPOSER_ROLE, NEW_GOV), "NEW_GOV not the live proposer");
        assertTrue(IServiceRegistry(SR_MAINNET).mapMultisigs(SAME_MAINNET), "mainnet adapter not whitelisted pre-exec");
        // sample: Gnosis Expert 1 and the two cross-chain L1 supply alpha are live nominees
        bytes32 h1 = keccak256(abi.encode(bytes32(uint256(uint160(0xdB9E2713c3dA3C403F2eA6E570eB978b00304e9E))), uint256(100)));
        assertGt(IVoteWeighting(VOTE_WEIGHTING).mapNomineeIds(h1), 0, "Expert 1 not a live nominee");
        // GuardCM Phase 1 additions are not yet set (mainnet ServiceManagerProxy.pause)
        assertFalse(IGuardCM(GUARD_CM).getTargetSelectorChainId(0x94a1892D91c05D0C61c3f49F42205D2285b914c9, 0x8456cb59, 1), "phase1 triple already set?");
    }

    function test_L1_fullGovernanceLifecycle() public {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        _mockVotes();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description, uint256 totalValue) = _forkProposal();
        bytes32 dh = keccak256(bytes(description));
        IGovernor gov = IGovernor(NEW_GOV);

        address proposer = makeAddr("proposer");
        address voter = makeAddr("voter");
        address executor = makeAddr("executor");

        // propose
        vm.prank(proposer);
        uint256 id = gov.propose(targets, values, calldatas, description);
        console2.log("proposed id:", id);

        // active -> vote For
        vm.roll(block.number + gov.votingDelay() + 1);
        vm.prank(voter);
        gov.castVote(id, 1);

        // end voting -> Succeeded
        vm.roll(block.number + gov.votingPeriod() + 1);
        assertEq(gov.state(id), SUCCEEDED, "not Succeeded");

        // queue, then warp past the timelock eta. Executor funds the Arbitrum retryable; Timelock holds nothing.
        gov.queue(targets, values, calldatas, dh);
        uint256 eta = gov.proposalEta(id);
        if (eta >= block.timestamp) vm.warp(eta + 1);
        _openEpochTimingWindow(); // mock AFTER warp so it binds to the execution timestamp
        vm.deal(TIMELOCK, 0);
        vm.deal(executor, totalValue);
        vm.prank(executor);
        gov.execute{value: totalValue}(targets, values, calldatas, dh);
        assertEq(gov.state(id), EXECUTED, "not Executed");

        _assertL1Effects(targets, calldatas);
        assertEq(TIMELOCK.balance, 0, "Timelock should not retain funds");
        console2.log("L1 effects asserted: mainnet de-whitelisted + 32 nominees removed; 7 L2 messages enqueued");
    }

    /// @dev Fast path: execute the full proposal directly as the Timelock (no governor), same L1 assertions.
    function test_L1_fullProposal_executesAsTimelock() public {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,, uint256 totalValue) = _forkProposal();

        _openEpochTimingWindow();
        vm.deal(TIMELOCK, totalValue);
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

        _assertL1Effects(targets, calldatas);
    }
}

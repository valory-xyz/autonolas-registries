// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal24aBuilder} from "../scripts/proposals/proposal_24a_dewhitelist_and_guard/Proposal24aDewhitelistAndGuard.s.sol";

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
interface IServiceRegistry { function mapMultisigs(address multisig) external view returns (bool); }
interface IGuardCM { function getTargetSelectorChainId(address target, bytes4 selector, uint256 chainId) external view returns (bool); }

/// @notice Full governance lifecycle (propose -> vote -> queue -> execute) for proposal 24a on a MAINNET fork,
///         through the CURRENTLY-LIVE GovernorOLAS (NEW_GOV; proposal 11 already migrated the Timelock roles).
///         Proves the L1-observable effects land: the mainnet same-address adapter is de-whitelisted and all 19
///         GuardCM triples are set. The 7 L2 de-whitelists are bridge ENQUEUES here (their L1 calls must not
///         revert); their L2 effect is verified in the L2 fork tests. The Arbitrum entry's value is supplied by
///         the EXECUTOR (executor -> Governor -> Timelock -> Inbox; the Timelock needs no balance).
///
///         This proposal exists because the original single 41-action proposal 24 reverted on-chain at the
///         EIP-7825 per-tx gas cap (2^24 = 16,777,216); 24a is the sub-cap de-whitelist + GuardCM half.
///         Run: forge test --match-contract Proposal24aForkL1Test -vvv
contract Proposal24aForkL1Test is Test, Proposal24aBuilder {
    address internal constant NEW_GOV = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6; // live GovernorOLAS
    address internal constant WVEOLAS = 0x4039B809E0C0Ad04F6Fc880193366b251dDf4B40;
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    uint8 internal constant SUCCEEDED = 4;
    uint8 internal constant EXECUTED = 7;

    function _forkProposal()
        internal pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description, uint256 totalValue)
    {
        (targets, values, calldatas, description) = buildProposal();
        for (uint256 i; i < values.length; ++i) totalValue += values[i];
    }

    function _mockVotes() internal {
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastTotalSupply(uint256)"))), abi.encode(uint256(1e24)));
    }

    function _assertL1Effects() internal view {
        // (1) mainnet adapter de-whitelisted
        assertFalse(IServiceRegistry(SR_MAINNET).mapMultisigs(SAME_MAINNET), "mainnet adapter still whitelisted");
        // (2) all 19 GuardCM Phase 1 triples now whitelisted
        (address[] memory gt, bytes4[] memory gs, uint256[] memory gc,) = phase1Triples();
        for (uint256 i; i < gt.length; ++i) {
            assertTrue(IGuardCM(GUARD_CM).getTargetSelectorChainId(gt[i], gs[i], gc[i]), "GuardCM triple not set");
        }
    }

    function test_preconditions() public {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        assertTrue(ITimelock(TIMELOCK).hasRole(PROPOSER_ROLE, NEW_GOV), "NEW_GOV not the live proposer");
        assertTrue(IServiceRegistry(SR_MAINNET).mapMultisigs(SAME_MAINNET), "mainnet adapter not whitelisted pre-exec");
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
        vm.deal(TIMELOCK, 0);
        vm.deal(executor, totalValue);
        vm.prank(executor);
        gov.execute{value: totalValue}(targets, values, calldatas, dh);
        assertEq(gov.state(id), EXECUTED, "not Executed");

        _assertL1Effects();
        assertEq(TIMELOCK.balance, 0, "Timelock should not retain funds");
        console2.log("L1 24a effects asserted: mainnet de-whitelisted + 19 GuardCM triples set; 7 L2 messages enqueued");
    }

    /// @dev Fast path: execute the full proposal directly as the Timelock (no governor), same L1 assertions.
    function test_L1_fullProposal_executesAsTimelock() public {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,, uint256 totalValue) = _forkProposal();

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

        _assertL1Effects();
    }
}

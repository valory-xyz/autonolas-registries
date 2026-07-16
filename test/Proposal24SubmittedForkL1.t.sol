// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal24Builder} from "../scripts/proposals/proposal_24_dewhitelist_and_guard/Proposal24DewhitelistAndGuard.s.sol";

interface IGovernor {
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);
    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external returns (uint256);
    function execute(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external payable returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
    function proposalEta(uint256 proposalId) external view returns (uint256);
}
interface IServiceRegistry { function mapMultisigs(address multisig) external view returns (bool); }
interface IGuardCM { function getTargetSelectorChainId(address target, bytes4 selector, uint256 chainId) external view returns (bool); }
interface IMechMarketplace { function mapMechFactories(address factory) external view returns (bool); }

/// @notice Forks the ACTUAL on-chain proposal 24 submission — tx
///   0xd543cd06415529a021ef30be0124af31f318ed61adb604e0aae92647941184ac (block 25,476,048), submitted by the
///   proposer Safe 0x3447...0039 — and drives the ALREADY-CREATED proposal through vote -> queue -> execute on a
///   mainnet fork, WITHOUT re-proposing it. Uses the real on-chain proposalId
///   0x0f66ff0be88382e028474de0c50f59ac0c4bd98579e8f637c2d587aabc6fa62d; buildProposal() only supplies the
///   queue/execute args, which are proven byte-identical to the submitted ProposalCreated event (the require below
///   re-derives the id and must equal the submitted one). Asserts every L1-observable effect lands and that
///   Governor.execute() stays under the EIP-7825 per-tx gas cap.
///   Run: forge test --match-contract Proposal24SubmittedForkL1Test -vv
contract Proposal24SubmittedForkL1Test is Test, Proposal24Builder {
    address internal constant NEW_GOV = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6; // live GovernorOLAS
    address internal constant WVEOLAS = 0x4039B809E0C0Ad04F6Fc880193366b251dDf4B40;
    uint256 internal constant SUBMITTED_ID = 0x0f66ff0be88382e028474de0c50f59ac0c4bd98579e8f637c2d587aabc6fa62d;

    // From the decoded ProposalCreated event of the submission tx (voting window is fixed at proposal creation):
    uint256 internal constant START_BLOCK = 25489139; // proposalSnapshot (voting starts)
    uint256 internal constant END_BLOCK   = 25508775; // proposalDeadline (voting ends)

    uint8 internal constant PENDING = 0;
    uint8 internal constant ACTIVE = 1;
    uint8 internal constant SUCCEEDED = 4;
    uint8 internal constant EXECUTED = 7;

    function _mockVotes() internal {
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastTotalSupply(uint256)"))), abi.encode(uint256(1e24)));
    }

    function test_fork_executeSubmittedProposal() public {
        // Fork at LATEST (public RPCs serve current state free; a pinned block would need archive access). The
        // submission at block 25,476,048 is already in this state, so the proposal exists and is still Pending.
        // This replay reads the real (still-Pending) proposal and simulates its voting window, so it is only valid
        // while on-chain voting has NOT yet started; once it has, skip gracefully (the durable executability proof
        // lives in Proposal24ForkL1Test, which proposes fresh and does not depend on the live proposal's timeline).
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        if (block.number >= START_BLOCK) {
            emit log("on-chain voting already started; skipping submitted-proposal replay (see Proposal24ForkL1Test)");
            vm.skip(true);
            return;
        }
        IGovernor gov = IGovernor(NEW_GOV);

        // (0) The proposal from tx 0xd543... already exists on-chain at this fork block.
        uint8 st0 = gov.state(SUBMITTED_ID);
        assertTrue(st0 == PENDING || st0 == ACTIVE, "submitted proposal 24 not found on fork");
        console2.log("on-chain proposal 24 state at fork block:", st0);

        // Pre-exec sanity: targets are still in their pre-execution state.
        assertTrue(IServiceRegistry(SR_MAINNET).mapMultisigs(SAME_MAINNET), "mainnet adapter not whitelisted pre-exec");
        assertTrue(IMechMarketplace(MM_MAINNET).mapMechFactories(MF_MAINNET), "mainnet OLAS factory not whitelisted pre-exec");

        // Reconstruct the queue/execute args and prove they hash to the SUBMITTED proposalId.
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) = buildProposal();
        bytes32 dh = keccak256(bytes(description));
        require(uint256(keccak256(abi.encode(targets, values, calldatas, dh))) == SUBMITTED_ID, "args != submitted proposalId");
        uint256 totalValue;
        for (uint256 i; i < values.length; ++i) totalValue += values[i];

        // (1) Vote the EXISTING proposal through (mocked winning weight at the real snapshot), advance past voting.
        _mockVotes();
        vm.roll(START_BLOCK + 1);
        assertEq(gov.state(SUBMITTED_ID), ACTIVE, "proposal not Active at snapshot+1");
        address voter = makeAddr("voter");
        vm.prank(voter);
        gov.castVote(SUBMITTED_ID, 1);
        vm.roll(END_BLOCK + 1);
        assertEq(gov.state(SUBMITTED_ID), SUCCEEDED, "proposal not Succeeded after voting");

        // (2) Queue + execute the REAL proposal (no re-propose). Executor funds the Arbitrum retryable value.
        gov.queue(targets, values, calldatas, dh);
        uint256 eta = gov.proposalEta(SUBMITTED_ID);
        if (eta >= block.timestamp) vm.warp(eta + 1);
        address executor = makeAddr("executor");
        vm.deal(TIMELOCK, 0);
        vm.deal(executor, totalValue);
        vm.prank(executor);
        uint256 g = gasleft();
        gov.execute{value: totalValue}(targets, values, calldatas, dh);
        uint256 executeGas = g - gasleft();
        assertEq(gov.state(SUBMITTED_ID), EXECUTED, "proposal not Executed");

        // (3) Every L1-observable effect landed.
        assertFalse(IServiceRegistry(SR_MAINNET).mapMultisigs(SAME_MAINNET), "mainnet adapter still whitelisted");
        assertFalse(IMechMarketplace(MM_MAINNET).mapMechFactories(MF_MAINNET), "mainnet OLAS factory still whitelisted");
        (address[] memory gt, bytes4[] memory gs, uint256[] memory gc,) = phase1Triples();
        for (uint256 i; i < gt.length; ++i) {
            assertTrue(IGuardCM(GUARD_CM).getTargetSelectorChainId(gt[i], gs[i], gc[i]), "GuardCM triple not set");
        }
        assertEq(TIMELOCK.balance, 0, "Timelock should not retain funds");

        console2.log("SUBMITTED proposal 24 executed on fork (mainnet same-address + OLAS factory de-whitelisted; 19 GuardCM triples; 8 L2 messages enqueued)");
        console2.log("Governor.execute() gas used:", executeGas);
        console2.log("EIP-7825 per-tx cap:        ", uint256(16777216));
        assertLt(executeGas, 16777216, "execute exceeds EIP-7825 per-tx gas cap");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/compatibility/GovernorCompatibilityBravo.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

/// @title Governor Bravo OLA - Smart contract for the governance
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract GovernorBravoOLA is Governor, GovernorSettings, GovernorCompatibilityBravo, GovernorVotes, GovernorVotesQuorumFraction, GovernorTimelockControl {
    constructor(
        IVotes governanceToken,
        TimelockController timelock,
        uint256 initialVotingDelay,
        uint256 initialVotingPeriod,
        uint256 initialProposalThreshold,
        uint256 quorumFraction
    )
        Governor("GovernorBravoOLA")
        GovernorSettings(initialVotingDelay, initialVotingPeriod, initialProposalThreshold)
        GovernorVotes(governanceToken)
        GovernorVotesQuorumFraction(quorumFraction)
        GovernorTimelockControl(timelock)
    {}

    /// @dev Gets minimum number of percent from the voting power required for a proposal to be successful.
    /// @param blockNumber The snaphot block used for counting vote. This allows to scale the quroum depending on
    ///                    values such as the totalSupply of an escrow at this block.
    /// @return Quorum factor.
    // solhint-disable-next-line
    function quorum(uint256 blockNumber) public view override(IGovernor, GovernorVotesQuorumFraction) returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    /// @dev Gets voting delay.
    /// @return Voting delay.
    function votingDelay() public view override(IGovernor, GovernorSettings) returns (uint256)
    {
        return super.votingDelay();
    }

    /// @dev Gets voting period.
    /// @return Voting period.
    function votingPeriod() public view override(IGovernor, GovernorSettings) returns (uint256)
    {
        return super.votingPeriod();
    }

    /// @dev Gets the voting power for a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return Voting power.
    function getVotes(address account, uint256 blockNumber) public view override(IGovernor, GovernorVotes)
        returns (uint256)
    {
        return super.getVotes(account, blockNumber);
    }

    /// @dev Current state of a proposal, following Compound’s convention.
    /// @param proposalId Proposal Id.
    function state(uint256 proposalId) public view override(Governor, IGovernor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /// @dev Create a new proposal to change the protocol / contract parameters.
    /// @param targets The ordered list of target addresses for calls to be made during proposal execution.
    /// @param values The ordered list of values to be passed to the calls made during proposal execution.
    /// @param calldatas The ordered list of data to be passed to each individual function call during proposal execution.
    /// @param description A human readable description of the proposal and the changes it will enact.
    /// @return The Id of the newly created proposal.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, GovernorCompatibilityBravo, IGovernor) returns (uint256)
    {
        return super.propose(targets, values, calldatas, description);
    }

    /// @dev Gets the number of votes.
    /// @return The number of votes required in order for a voter to become a proposer.
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256)
    {
        return super.proposalThreshold();
    }

    /// @dev Executes a proposal.
    /// @param proposalId Proposal Id.
    /// @param targets The ordered list of target addresses.
    /// @param values The ordered list of values.
    /// @param calldatas The ordered list of data to be passed to each individual function call.
    /// @param descriptionHash Hashed description of the proposal.
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl)
    {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @dev Cancels a proposal.
    /// @param targets The ordered list of target addresses.
    /// @param values The ordered list of values.
    /// @param calldatas The ordered list of data to be passed to each individual function call.
    /// @param descriptionHash Hashed description of the proposal.
    /// @return The Id of the newly created proposal.
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256)
    {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /// @dev Gets the executor address.
    /// @return Executor address.
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address)
    {
        return super._executor();
    }

    /// @dev Gets information about the interface support.
    /// @param interfaceId A specified interface Id.
    /// @return True if this contract implements the interface defined by interfaceId.
    function supportsInterface(bytes4 interfaceId) public view override(Governor, IERC165, GovernorTimelockControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

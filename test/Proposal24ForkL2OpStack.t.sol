// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Proposal24Builder} from "../scripts/proposals/proposal_24_dewhitelist_sameaddr_and_unnominate/Proposal24DewhitelistAndUnnominate.s.sol";

interface IOptimismMessenger {
    function CDMContractProxyHome() external view returns (address); // L2 CrossDomainMessenger
    function sourceGovernor() external view returns (address);       // L1 source (Timelock)
    function processMessageFromSource(bytes memory data) external payable;
}

interface IServiceRegistry {
    function mapMultisigs(address multisig) external view returns (bool);
    function owner() external view returns (address);
}

/// @notice Simulates the L1->L2 bridge DELIVERY of proposal 24's GnosisSafeSameAddressMultisig de-whitelisting
///         on each OP-stack L2 (Optimism, Base, Celo, Mode): prank the L2 CrossDomainMessenger, spoof the
///         source governor, and feed the OptimismMessenger the EXACT packed tuple the proposal sends. Asserts
///         the adapter is removed from the registry whitelist (mapMultisigs -> false).
///         Unlike the proposal-11 SM upgrade, Mode needs NO ownership pre-step: its ServiceRegistryL2 is
///         already owned by the Mode OptimismMessenger.
///         Run: forge test --match-contract Proposal24ForkL2OpStackTest -vvv
contract Proposal24ForkL2OpStackTest is Test, Proposal24Builder {
    /// @dev Deliver the proposal's exact bridged payload through the mediator and assert the de-whitelist.
    function _deliver(address mediator, address registry, address adapter) internal {
        address cdm = IOptimismMessenger(mediator).CDMContractProxyHome();
        address gov = IOptimismMessenger(mediator).sourceGovernor();

        // EXACT proposal payload: one tuple target=registry, payload=changeMultisigPermission(adapter,false).
        bytes memory packed = _packed(registry, _changePerm(adapter));

        // The mediator authenticates: msg.sender == L2 messenger AND xDomainMessageSender == sourceGovernor.
        vm.mockCall(cdm, abi.encodeWithSelector(bytes4(keccak256("xDomainMessageSender()"))), abi.encode(gov));
        vm.prank(cdm);
        IOptimismMessenger(mediator).processMessageFromSource(packed);

        assertFalse(IServiceRegistry(registry).mapMultisigs(adapter), "adapter still whitelisted after de-whitelist");
    }

    function _simOpStack(string memory rpc, address mediator, address registry, address adapter) internal {
        vm.createSelectFork(rpc);
        assertTrue(IServiceRegistry(registry).mapMultisigs(adapter), "adapter not whitelisted pre-exec?");
        assertEq(IServiceRegistry(registry).owner(), mediator, "registry not owned by the L2 mediator");
        _deliver(mediator, registry, adapter);
    }

    function test_L2_optimism() public {
        _simOpStack(vm.envOr("OP_RPC", string("https://mainnet.optimism.io")), OP_MESSENGER_L2, SRL2_OPTIMISM, SAME_OPTIMISM);
    }

    function test_L2_base() public {
        _simOpStack(vm.envOr("BASE_RPC", string("https://mainnet.base.org")), BASE_MESSENGER_L2, SRL2_BASE, SAME_BASE);
    }

    function test_L2_celo() public {
        _simOpStack(vm.envOr("CELO_RPC", string("https://forno.celo.org")), CELO_MESSENGER_L2, SRL2_CELO, SAME_CELO);
    }

    function test_L2_mode() public {
        _simOpStack(vm.envOr("MODE_RPC", string("https://mainnet.mode.network")), MODE_MESSENGER_L2, SRL2_MODE, SAME_MODE);
    }
}

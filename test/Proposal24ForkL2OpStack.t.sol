// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal24Builder} from "../scripts/proposals/proposal_24_dewhitelist_and_guard/Proposal24DewhitelistAndGuard.s.sol";

interface IOptimismMessenger {
    function CDMContractProxyHome() external view returns (address); // L2 CrossDomainMessenger
    function sourceGovernor() external view returns (address);       // L1 source (Timelock)
    function processMessageFromSource(bytes memory data) external payable;
}

interface IServiceRegistry {
    function mapMultisigs(address multisig) external view returns (bool);
    function owner() external view returns (address);
}

interface IMechMarketplace {
    function mapMechFactories(address factory) external view returns (bool);
    function owner() external view returns (address);
}

/// @notice Simulates the L1->L2 bridge DELIVERY of proposal 24's same-address multisig de-whitelisting on each
///         OP-stack L2 (Optimism, Base, Celo, Mode): prank the L2 CrossDomainMessenger, spoof the source
///         governor, and feed the OptimismMessenger the EXACT packed tuple the proposal sends. Asserts the
///         adapter is removed from the registry whitelist (mapMultisigs -> false). The bridged payload is
///         byte-identical to the original bundle, so this delivery was already proven; only the L1
///         bundling changed. Mode needs NO ownership pre-step (its ServiceRegistryL2 is owned by the mediator).
///         Run: forge test --match-contract Proposal24ForkL2OpStackTest -vvv
contract Proposal24ForkL2OpStackTest is Test, Proposal24Builder {
    function _deliver(address mediator, address registry, address adapter) internal {
        address cdm = IOptimismMessenger(mediator).CDMContractProxyHome();
        address gov = IOptimismMessenger(mediator).sourceGovernor();

        bytes memory packed = _packed(registry, _changePerm(adapter));

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

    /// @dev COMBINED delivery: one processMessageFromSource carrying BOTH tuples (de-whitelist same-address
    ///      multisig + de-whitelist OLAS mech factory). Asserts both effects land and measures the combined L2
    ///      delivery gas (proves the single MIN_GAS-provisioned message covers both actions).
    function _simOpStackCombined(
        string memory rpc, address mediator, address registry, address adapter, address mm, address factory
    ) internal {
        vm.createSelectFork(rpc);
        assertTrue(IServiceRegistry(registry).mapMultisigs(adapter), "adapter not whitelisted pre-exec?");
        assertTrue(IMechMarketplace(mm).mapMechFactories(factory), "OLAS factory not whitelisted pre-exec?");
        assertEq(IServiceRegistry(registry).owner(), mediator, "registry not owned by the L2 mediator");
        assertEq(IMechMarketplace(mm).owner(), mediator, "Mech Marketplace not owned by the L2 mediator");

        address cdm = IOptimismMessenger(mediator).CDMContractProxyHome();
        address gov = IOptimismMessenger(mediator).sourceGovernor();
        bytes memory packed = bytes.concat(_packed(registry, _changePerm(adapter)), _packed(mm, _disableFactory(factory)));

        vm.mockCall(cdm, abi.encodeWithSelector(bytes4(keccak256("xDomainMessageSender()"))), abi.encode(gov));
        vm.prank(cdm);
        uint256 g = gasleft();
        IOptimismMessenger(mediator).processMessageFromSource(packed);
        console2.log("OP-stack COMBINED L2 delivery gas:", g - gasleft(), "(MIN_GAS =", MIN_GAS);

        assertFalse(IServiceRegistry(registry).mapMultisigs(adapter), "adapter still whitelisted after de-whitelist");
        assertFalse(IMechMarketplace(mm).mapMechFactories(factory), "OLAS factory still whitelisted after de-whitelist");
    }

    // ---- Optimism / Base / Celo: ONE combined message per chain (de-whitelist + factory) ----
    function test_L2_optimism() public {
        _simOpStackCombined(vm.envOr("OP_RPC", string("https://mainnet.optimism.io")), OP_MESSENGER_L2, SRL2_OPTIMISM, SAME_OPTIMISM, MM_OPTIMISM, MF_OPTIMISM);
    }

    function test_L2_base() public {
        _simOpStackCombined(vm.envOr("BASE_RPC", string("https://mainnet.base.org")), BASE_MESSENGER_L2, SRL2_BASE, SAME_BASE, MM_BASE, MF_BASE);
    }

    function test_L2_celo() public {
        _simOpStackCombined(vm.envOr("CELO_RPC", string("https://forno.celo.org")), CELO_MESSENGER_L2, SRL2_CELO, SAME_CELO, MM_CELO, MF_CELO);
    }

    // ---- Mode: de-whitelist only (no OLAS mech factory) ----
    function test_L2_mode() public {
        _simOpStack(vm.envOr("MODE_RPC", string("https://mainnet.mode.network")), MODE_MESSENGER_L2, SRL2_MODE, SAME_MODE);
    }
}

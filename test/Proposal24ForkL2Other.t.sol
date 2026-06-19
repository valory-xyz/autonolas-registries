// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Proposal24Builder} from "../scripts/proposals/proposal_24_dewhitelist_sameaddr_and_unnominate/Proposal24DewhitelistAndUnnominate.s.sol";

interface IHomeMediator {
    function AMBContractProxyHome() external view returns (address);
    function foreignGovernor() external view returns (address);
    function processMessageFromForeign(bytes memory data) external;
}

interface IFxGovernorTunnel {
    function fxChild() external view returns (address);
    function rootGovernor() external view returns (address);
    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes memory data) external;
}

interface IServiceRegistry {
    function mapMultisigs(address multisig) external view returns (bool);
    function changeMultisigPermission(address multisig, bool permission) external returns (bool);
    function owner() external view returns (address);
}

/// @notice Bridge-delivery sims for the non-OP-stack L2s: Gnosis (AMB/HomeMediator), Polygon (FxRoot/
///         FxGovernorTunnel) and Arbitrum (retryable executed as the aliased L1 Timelock). Each feeds the
///         mediator the EXACT payload proposal 24 sends and asserts the GnosisSafeSameAddressMultisig adapter
///         is removed from the registry whitelist (mapMultisigs -> false).
///         Run: forge test --match-contract Proposal24ForkL2OtherTest -vvv
contract Proposal24ForkL2OtherTest is Test, Proposal24Builder {
    /// @dev Gnosis: HomeMediator.processMessageFromForeign, caller = AMB, AMB.messageSender() = foreignGovernor.
    function test_L2_gnosis() public {
        vm.createSelectFork(vm.envOr("GNOSIS_RPC", string("https://rpc.gnosischain.com")));
        assertTrue(IServiceRegistry(SRL2_GNOSIS).mapMultisigs(SAME_GNOSIS), "adapter not whitelisted pre-exec?");
        assertEq(IServiceRegistry(SRL2_GNOSIS).owner(), HOME_MEDIATOR_L2, "registry not owned by HomeMediator");

        address amb = IHomeMediator(HOME_MEDIATOR_L2).AMBContractProxyHome();
        address fg = IHomeMediator(HOME_MEDIATOR_L2).foreignGovernor();
        bytes memory packed = _packed(SRL2_GNOSIS, _changePerm(SAME_GNOSIS));

        vm.mockCall(amb, abi.encodeWithSelector(bytes4(keccak256("messageSender()"))), abi.encode(fg));
        vm.prank(amb);
        IHomeMediator(HOME_MEDIATOR_L2).processMessageFromForeign(packed);

        assertFalse(IServiceRegistry(SRL2_GNOSIS).mapMultisigs(SAME_GNOSIS), "gnosis adapter still whitelisted");
    }

    /// @dev Polygon: FxGovernorTunnel.processMessageFromRoot, caller = fxChild, rootMessageSender = rootGovernor.
    function test_L2_polygon() public {
        vm.createSelectFork(vm.envOr("POLYGON_RPC", string("https://polygon.drpc.org")));
        assertTrue(IServiceRegistry(SRL2_POLYGON).mapMultisigs(SAME_POLYGON), "adapter not whitelisted pre-exec?");
        assertEq(IServiceRegistry(SRL2_POLYGON).owner(), FX_TUNNEL_L2, "registry not owned by FxGovernorTunnel");

        address fxChild = IFxGovernorTunnel(FX_TUNNEL_L2).fxChild();
        address rg = IFxGovernorTunnel(FX_TUNNEL_L2).rootGovernor();
        bytes memory packed = _packed(SRL2_POLYGON, _changePerm(SAME_POLYGON));

        vm.prank(fxChild);
        IFxGovernorTunnel(FX_TUNNEL_L2).processMessageFromRoot(0, rg, packed);

        assertFalse(IServiceRegistry(SRL2_POLYGON).mapMultisigs(SAME_POLYGON), "polygon adapter still whitelisted");
    }

    /// @dev Arbitrum: the retryable runs with msg.sender = aliased L1 Timelock (ARB_MEDIATOR_L2), calling
    ///      the registry's changeMultisigPermission directly (no mediator wrap). That alias is the registry owner.
    function test_L2_arbitrum() public {
        vm.createSelectFork(vm.envOr("ARBITRUM_RPC", string("https://arb1.arbitrum.io/rpc")));
        assertTrue(IServiceRegistry(SRL2_ARBITRUM).mapMultisigs(SAME_ARBITRUM), "adapter not whitelisted pre-exec?");
        assertEq(IServiceRegistry(SRL2_ARBITRUM).owner(), ARB_MEDIATOR_L2, "registry not owned by aliased L1 Timelock");

        vm.prank(ARB_MEDIATOR_L2); // == retryable msg.sender (aliased L1 Timelock)
        IServiceRegistry(SRL2_ARBITRUM).changeMultisigPermission(SAME_ARBITRUM, false);

        assertFalse(IServiceRegistry(SRL2_ARBITRUM).mapMultisigs(SAME_ARBITRUM), "arbitrum adapter still whitelisted");
    }
}

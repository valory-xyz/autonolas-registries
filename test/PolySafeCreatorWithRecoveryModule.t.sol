pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {GnosisSafe} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {DefaultCallbackHandler} from "@gnosis.pm/safe-contracts/contracts/handler/DefaultCallbackHandler.sol";
import {PolySafeProxyFactory} from "../contracts/test/MockPolySafeFactory.sol";
import {PolySafeCreatorWithRecoveryModule} from "../contracts/multisigs/PolySafeCreatorWithRecoveryModule.sol";

contract BaseSetup is Test {
    Utils internal utils;
    GnosisSafe internal gnosisSafe;
    DefaultCallbackHandler internal fallbackHandler;
    PolySafeProxyFactory internal polySafeProxyFactory;
    PolySafeCreatorWithRecoveryModule internal polySafeCreatorWithRecoveryModule;

    address payable[] internal users;
    address internal deployer;

    bytes32 internal testPolySafeProxyBytecodeHash = 0xc2ece159be6635c94f47e29adcd7a113dd700a7ab2c08e5fd5e0a3b6903c35bc;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(50);
        deployer = users[0];
        vm.label(deployer, "Deployer");

        // Get contracts
        gnosisSafe = new GnosisSafe();
        fallbackHandler = new DefaultCallbackHandler();
        polySafeProxyFactory = new PolySafeProxyFactory(address(gnosisSafe), address(fallbackHandler));
        // For fork usage: polySafeProxyFactory = PolySafeProxyFactory(0xaacFeEa03eb1561C4e67d661e40682Bd20E3541b);

        // RecoveryModule address is just GnosisSafe as its value is not really relevant for testing
        polySafeCreatorWithRecoveryModule = new PolySafeCreatorWithRecoveryModule(address(polySafeProxyFactory),
            address(gnosisSafe), testPolySafeProxyBytecodeHash);

        // Get funds for deployer and operator
        vm.deal(deployer, 5 ether);
    }
}

contract PolySafeCreator is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Create Poly Safe multisig with recovery module.
    function testCreatePolySafeWithRecoveryModule() public {
        // Get user address and PK
        (address user, uint256 userPk) = makeAddrAndKey("user");
        emit log_address(user);

        // Get multisig owners
        address[] memory owners = new address[](1);
        owners[0] = user;

        // Get Poly Safe factory digest
        bytes32 polySafeDigest = polySafeCreatorWithRecoveryModule.getPolySafeCreateTransactionHash();

        // Get Poly Safe creation signature
        PolySafeProxyFactory.Sig memory safeCreateSig;
        (safeCreateSig.v, safeCreateSig.r, safeCreateSig.s) = vm.sign(userPk, polySafeDigest);

        // Get enable module digest
        bytes32 enableModuleDigest = polySafeCreatorWithRecoveryModule.getEnableModuleTransactionHash(user);

        // Get enable module signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, enableModuleDigest);
        bytes memory enableModuleSignature = abi.encodePacked(r, s, v);

        // Encode signatures
        bytes memory data = abi.encode(safeCreateSig, enableModuleSignature);

        address multisig = polySafeCreatorWithRecoveryModule.create(owners, 1, data);

        assertEq(multisig.codehash, testPolySafeProxyBytecodeHash);
    }
}

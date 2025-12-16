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

    bytes32 internal configHash = keccak256(abi.encode(deployer));
    uint32[] internal agentIds;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(50);
        deployer = users[0];
        vm.label(deployer, "Deployer");

        // Get contracts
        gnosisSafe = new GnosisSafe();
        fallbackHandler = new DefaultCallbackHandler();
        polySafeProxyFactory = new PolySafeProxyFactory(address(gnosisSafe), address(fallbackHandler));
        // RecoveryModule address is just GnosisSafe as its value is not really relevant for testing
        polySafeCreatorWithRecoveryModule = new PolySafeCreatorWithRecoveryModule(address(polySafeProxyFactory),
            address(gnosisSafe));

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
        // Get Poly Safe factory digest
        bytes32 structHash = keccak256(abi.encode(polySafeProxyFactory.CREATE_PROXY_TYPEHASH(), address(0), 0,
            payable(address(0))));
        bytes32 polySafeDigest = keccak256(abi.encodePacked("\x19\x01", polySafeProxyFactory.domainSeparator(), structHash));

        (address user, uint256 userPk) = makeAddrAndKey("user");
        emit log_address(user);

        // Get Poly Safe creation signature
        PolySafeProxyFactory.Sig memory safeCreateSig;
        (safeCreateSig.v, safeCreateSig.r, safeCreateSig.s) = vm.sign(userPk, polySafeDigest);

        // Get enable module signature
        bytes32 enableModuleDigest = polySafeCreatorWithRecoveryModule.getEnableModuleTransactionHash(user);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, enableModuleDigest);
        bytes memory enableModuleSignature = abi.encodePacked(r, s, v);

        // Set multisig owners
        address[] memory owners = new address[](1);
        owners[0] = user;

        // Encode signatures
        bytes memory data = abi.encode(safeCreateSig, enableModuleSignature);

        polySafeCreatorWithRecoveryModule.create(owners, 1, data);


    }
}

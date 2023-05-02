// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISignatureValidator {
    /// @dev Should return whether the signature provided is valid for the provided hash.
    /// @notice MUST return the bytes4 magic value 0x1626ba7e when function passes.
    ///         MUST NOT modify state (using STATICCALL for solc < 0.5, view modifier for solc > 0.5).
    ///         MUST allow external calls.
    /// @param hash Hash of the data to be signed.
    /// @param signature Signature byte array associated with hash.
    /// @return magicValue bytes4 magic value.
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}

/// @title OperatorSignedHashes - Smart contract for managing operator signed hashes
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract OperatorSignedHashes {
    event OperatorHashApproved(address indexed operator, bytes32 hash);

    // Value for the contract signature validation: bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 constant internal MAGIC_VALUE = 0x1626ba7e;
    // Domain separator type hash
    bytes32 public constant DOMAIN_SEPARATOR_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    // Unbond type hash
    bytes32 public constant UNBOND_TYPE_HASH =
        keccak256("Unbond(address operator,address serviceOwner,uint256 serviceId,uint256 nonce)");
    // Register agents type hash
    bytes32 public constant REGISTER_AGENTS_TYPE_HASH =
        keccak256("RegisterAgents(address operator,address serviceOwner,uint256 serviceId,bytes32 agentsData,uint256 nonce)");
    // Original domain separator value
    bytes32 public immutable domainSeparator;
    // Original chain Id
    uint256 public immutable chainId;
    // Name hash
    bytes32 public immutable nameHash;
    // Version hash
    bytes32 public immutable versionHash;

    // Name of a signing domain
    string public name;
    // Version of a signing domain
    string public version;

    // Mapping operator address => unbond nonce
    mapping(address => uint256) public mapOperatorUnbondNonces;
    // Mapping operator address => register agents nonce
    mapping(address => uint256) public mapOperatorRegisterAgentsNonces;
    // Mapping operator address => approved hashes status
    mapping(address => mapping(bytes32 => bool)) public mapOperatorApprovedHashes;

    constructor(string memory _name, string memory _version) {
        name = _name;
        version = _version;
        nameHash = keccak256(bytes(_name));
        versionHash = keccak256(bytes(_version));
        chainId = block.chainid;
        domainSeparator = _computeDomainSeparator();
    }

    function _verifySignedHash(
        address operator,
        bytes32 txHash,
        bytes memory signature
    ) internal view returns (bool)
    {
        // Decode the signature
        uint8 v = uint8(signature[64]);
        // Check if v is zero because it was signed by the ledger
        if (v == 0 && operator.code.length == 0) {
            // In case of a non-contract, adjust v to follow the standard ecrecover case
            v = 27;
        }
        bytes32 r;
        bytes32 s;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
        }

        address recOperator;
        // Go through signature cases based on the value of v
        if (v == 0) {
            // Contract signature case, where the address of the contract is encoded into r
            recOperator = address(uint160(uint256(r)));

            // Check for the signature validity in the contract
            if (ISignatureValidator(recOperator).isValidSignature(txHash, signature) != MAGIC_VALUE) {
                return false;
            }
        } else if (v == 1) {
            // Case of an approved hash, where the address of the operator is encoded into r
            recOperator = address(uint160(uint256(r)));
            // Hashes have been pre-approved by the operator via a separate transaction, see operatorApproveHash() function
            if (!mapOperatorApprovedHashes[recOperator][txHash]) {
                return false;
            }
        } else {
            // Case of ecrecover with the transaction hash for EOA signatures
            recOperator = ecrecover(txHash, v, r, s);
        }

        // Final check is fo the operator address itself
        if (recOperator != operator || recOperator == address(0)) {
            return false;
        }
        return true;
    }

    function operatorApproveHash(bytes32 hash) external {
        mapOperatorApprovedHashes[msg.sender][hash] = true;
        emit OperatorHashApproved(msg.sender, hash);
    }

    function _computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_SEPARATOR_TYPE_HASH,
                nameHash,
                versionHash,
                block.chainid,
                address(this)
            )
        );
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == chainId ? domainSeparator : _computeDomainSeparator();
    }

    function getUnbondHash(
        address operator,
        address serviceOwner,
        uint256 serviceId,
        uint256 nonce
    ) public view returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        UNBOND_TYPE_HASH,
                        operator,
                        serviceOwner,
                        serviceId,
                        nonce
                    )
                )
            )
        );
    }

    function getRegisterAgentsHash(
        address operator,
        address serviceOwner,
        uint256 serviceId,
        address[] memory agentInstances,
        uint32[] memory agentIds,
        uint256 nonce
    ) public view returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        REGISTER_AGENTS_TYPE_HASH,
                        operator,
                        serviceOwner,
                        serviceId,
                        keccak256(abi.encode(agentInstances, agentIds)),
                        nonce
                    )
                )
            )
        );
    }

    function isOperatorHashApproved(address operator, bytes32 hash) external view returns (bool) {
        return mapOperatorApprovedHashes[operator][hash];
    }
}

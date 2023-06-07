// SPDX-License-Identifier: Apache-2.0

import "SplToken.sol";

contract SimpleCollectible {
    event OwnerUpdated(address indexed metadataAuthority);
    event ManagerUpdated(address indexed manager);
    event BaseURIChanged(string baseURI);
    // These events log on the blockchain transactions made with this NFT
    event NFTMinted(address owner, address mintAccount);
    event NFTSold(address from, address to);

    // On Solana, the mintAccount represents the type of token created. It saves how many tokens exist in circulation.
    address public mintAccount;
    // The public key for the authority that should sign every change to the NFT's URI
    address public metadataAuthority;
    // Unit manager
    address public manager;
    // Base URI
    string public baseURI;
    // Unit counter
    uint64 public totalSupply;
    // Reentrancy lock
    uint64 internal _locked = 1;
    // To better understand the CID anatomy, please refer to: https://proto.school/anatomy-of-a-cid/05
    // CID = <multibase_encoding>multibase_encoding(<cid-version><multicodec><multihash-algorithm><multihash-length><multihash-hash>)
    // CID prefix = <multibase_encoding>multibase_encoding(<cid-version><multicodec><multihash-algorithm><multihash-length>)
    // to complement the multibase_encoding(<multihash-hash>)
    // multibase_encoding = base16 = "f"
    // cid-version = version 1 = "0x01"
    // multicodec = dag-pb = "0x70"
    // multihash-algorithm = sha2-256 = "0x12"
    // multihash-length = 256 bits = "0x20"
    string public constant CID_PREFIX = "f01701220";

    // The mint account will identify the NFT in this example
    constructor (address _mintAccount, address _metadataAuthority, string memory _baseURI) {
        mintAccount = _mintAccount;
        metadataAuthority = _metadataAuthority;
        baseURI = _baseURI;
    }

    /// Create a new NFT and associate it to an URI
    ///
    /// @param mintAuthority an account that signs each new mint
    /// @param ownerTokenAccount the owner associated token account
    function createCollectible(address mintAuthority, address ownerTokenAccount) public {
        SplToken.TokenAccountData token_data = SplToken.get_token_account_data(ownerTokenAccount);

        // The mint will only work if the associated token account points to the mint account in this contract
        // This assert is not necessary. The transaction will fail if this does not hold true.
        assert(mintAccount == token_data.mintAccount);
        SplToken.MintAccountData mint_data = SplToken.get_mint_account_data(token_data.mintAccount);
        // Ensure the supply is zero. Otherwise, this is not an NFT.
        assert(mint_data.supply == 0);

        // An NFT on Solana is a SPL-Token with only one minted token.
        // The token account saves the owner of the tokens minted with the mint account, the respective mint account and the number
        // of tokens the owner account owns
        SplToken.mint_to(token_data.mintAccount, ownerTokenAccount, mintAuthority, 1);

        // Set the mint authority to null. This prevents that any other new tokens be minted, ensuring we have an NFT.
        SplToken.remove_mint_authority(mintAccount, mintAuthority);

        // Log on blockchain records information about the created token
        emit NFTMinted(token_data.owner, token_data.mintAccount);
    }

    /// Transfer ownership of this NFT from one account to another
    /// This function only wraps the innate SPL transfer, which can be used outside this contract.
    /// However, the difference here is the event 'NFTSold' exclusive to this function
    ///
    /// @param oldTokenAccount the token account for the current owner
    /// @param newTokenAccount the token account for the new owner
    function transferOwnership(address oldTokenAccount, address newTokenAccount) public {
        // The current owner does not need to be the caller of this functions, but they need to sign the transaction
        // with their private key.
        SplToken.TokenAccountData old_data = SplToken.get_token_account_data(oldTokenAccount);
        SplToken.TokenAccountData new_data = SplToken.get_token_account_data(newTokenAccount);

        // To transfer the ownership of a token, we need the current owner and the new owner. The payer account is the account used to derive
        // the correspondent token account in TypeScript.
        SplToken.transfer(oldTokenAccount, newTokenAccount, old_data.owner, 1);
        emit NFTSold(old_data.owner, new_data.owner);
    }

    /// Check if an NFT is owned by @param owner
    ///
    /// @param owner the account whose ownership we want to verify
    /// @param tokenAccount the owner's associated token account
    function isOwner(address owner, address tokenAccount) public view returns (bool) {
        SplToken.TokenAccountData data = SplToken.get_token_account_data(tokenAccount);

        return owner == data.owner && mintAccount == data.mintAccount && data.balance == 1;
    }

    /// Requires the signature of the metadata authority.
    function requireMetadataSigner() internal {
        for(uint32 i=0; i < tx.accounts.length; i++) {
            if (tx.accounts[i].key == metadataAuthority) {
                require(tx.accounts[i].is_signer, "the metadata authority must sign the transaction");
                return;
            }
        }

        revert("The metadata authority is missing");
    }

    /// @dev Changes the metadataAuthority address.
    /// @param newOwner Address of a new metadataAuthority.
    function changeOwner(address newOwner) external {
        // Check for the metadata authority
        requireMetadataSigner();

        // Check for the zero address
        if (newOwner == address(0)) {
            revert("Zero Address");
        }

        metadataAuthority = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes the unit manager.
    /// @param newManager Address of a new unit manager.
    function changeManager(address newManager) external {
        // Check for the metadata authority
        requireMetadataSigner();

        // Check for the zero address
        if (newManager == address(0)) {
            revert("Zero Address");
        }

        manager = newManager;
        emit ManagerUpdated(newManager);
    }

    /// @dev Checks for the unit existence.
    /// @notice Unit counter starts from 1.
    /// @param unitId Unit Id.
    /// @return true if the unit exists, false otherwise.
    function exists(uint64 unitId) external view returns (bool) {
        return unitId > 0 && unitId < (totalSupply + 1);
    }

    /// @dev Sets unit base URI.
    /// @param bURI Base URI string.
    function setBaseURI(string memory bURI) external {
        requireMetadataSigner();

        // Check for the zero value
        if (bytes(bURI).length == 0) {
            revert("Zero Value");
        }

        baseURI = bURI;
        emit BaseURIChanged(bURI);
    }

    /// @dev Gets the valid unit Id from the provided index.
    /// @notice Unit counter starts from 1.
    /// @param id Unit counter.
    /// @return unitId Unit Id.
    function tokenByIndex(uint64 id) external view returns (uint64 unitId) {
        unitId = id + 1;
        if (unitId > totalSupply) {
            revert("Overflow");
        }
    }

    // Open sourced from: https://stackoverflow.com/questions/67893318/solidity-how-to-represent-bytes32-as-string
    /// @dev Converts bytes16 input data to hex16.
    /// @notice This method converts bytes into the same bytes-character hex16 representation.
    /// @param data bytes16 input data.
    /// @return result hex16 conversion from the input bytes16 data.
    function _toHex16(bytes16 data) internal pure returns (bytes32 result) {
        result = bytes32 (data) & 0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000000 |
        (bytes32 (data) & 0x0000000000000000FFFFFFFFFFFFFFFF00000000000000000000000000000000) >> 64;
        result = result & 0xFFFFFFFF000000000000000000000000FFFFFFFF000000000000000000000000 |
        (result & 0x00000000FFFFFFFF000000000000000000000000FFFFFFFF0000000000000000) >> 32;
        result = result & 0xFFFF000000000000FFFF000000000000FFFF000000000000FFFF000000000000 |
        (result & 0x0000FFFF000000000000FFFF000000000000FFFF000000000000FFFF00000000) >> 16;
        result = result & 0xFF000000FF000000FF000000FF000000FF000000FF000000FF000000FF000000 |
        (result & 0x00FF000000FF000000FF000000FF000000FF000000FF000000FF000000FF0000) >> 8;
        result = (result & 0xF000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000) >> 4 |
        (result & 0x0F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F00) >> 8;
        result = bytes32 (0x3030303030303030303030303030303030303030303030303030303030303030 +
        uint256 (result) +
            (uint256 (result) + 0x0606060606060606060606060606060606060606060606060606060606060606 >> 4 &
            0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F) * 39);
    }

    /// @dev Gets the hash of the unit.
    /// @param unitId Unit Id.
    /// @return Unit hash.
    function _getUnitHash(uint64 unitId) internal view returns (bytes32) {
        return bytes32(uint256(1));
    }

    /// @dev Returns unit token URI.
    /// @notice Expected multicodec: dag-pb; hashing function: sha2-256, with base16 encoding and leading CID_PREFIX removed.
    /// @param unitId Unit Id.
    /// @return Unit token URI string.
    function tokenURI(uint64 unitId) public view returns (string memory) {
        bytes32 unitHash = _getUnitHash(unitId);
        // Parse 2 parts of bytes32 into left and right hex16 representation, and concatenate into string
        // adding the base URI and a cid prefix for the full base16 multibase prefix IPFS hash representation
        return string(abi.encodePacked(baseURI, CID_PREFIX, _toHex16(bytes16(unitHash)),
            _toHex16(bytes16(unitHash << 128))));
    }
}

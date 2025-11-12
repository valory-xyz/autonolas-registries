# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `tag: v1.3.0-internal-audit` or e011812c7b0f1a1181f2414c3bb989b245609f65 <br> 

## Objectives
The audit focused on ERC-8004 bridge.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal11/analysis/contracts) 

### ERC20/ERC721 checks
N/A

### Coverage
```
-------------------------------------|----------|----------|----------|----------|----------------|
File                                 |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-------------------------------------|----------|----------|----------|----------|----------------|
ERC8004Operator.sol                  |     5.26 |        5 |    16.67 |    13.16 |... 194,201,202 |
IdentityRegistryBridger.sol          |    21.21 |    14.52 |    42.86 |     24.8 |... 512,515,517 |
```
- npx hardhat test: N/A
- Needed e2e test via fork.
[]  

### Security issues. Updated 11-11-25
#### Problems found instrumentally
No issue
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal10/analysis/slither_full.txt)

### Issue
### High/Critical. Typo in reentracy protection
```
contract ERC8004Operator
_locked - 1;

grep -r _locked ./ | grep "-"
./ERC8004Operator.sol:        _locked - 1;
./ERC8004Operator.sol:        _locked - 1;
```
[x] Fixed

### High/Medium. No proxy pattern in ERC8004Operator 
```
1. https://eips.ethereum.org/EIPS/eip-8004 https://github.com/erc-8004/erc-8004-contracts/commit/dcbb2d189338c655918e61e91c424c1da6e5e8a1
IIdentityRegistry(identityRegistry)
IValidationRegistry(validationRegistry).validationRequest
There is no guarantee that the ABI will remain the same.
2. It is risky to leave an unmodifiable implementation that will be used in thousands of agents.
Recommendation: Proxy pattern for the operator.
```
[x] Fixed, transformed into proxy

### Medium. Bug in continue
```
However, the serviceId counter is not incremented until continue is executed (the increment occurs only at the end of the iteration). 
As a result, if the first service in the range is not activated (multisig = 0), the loop will re-check the same serviceId at each iteration, repeatedly executing continue without moving forward.

    linkServiceIdAgentIds
        for (uint256 i = 0; i < numServices; ++i) {
            // Get service multisig
            (,address multisig,,,,,) = IServiceRegistry(serviceRegistry).mapServices(serviceId);
            // Skip services that were never deployed
            if (multisig == address(0)) {
                continue; // missing <-- serviceId++;
            }

```
[x] Fixed


### Medium/Notes. Double-check design
```
IIdentityRegistryBridger(identityRegistryBridger).updateAgentWallet(serviceId, lastMultisig, multisig); <-- It's in normal workflow called in one place. Is that enough for all cases?
ref: ServiceManager
ref: `Double-check in manager controlled function`

I mean, can such a desynchronization happen in the future, after the execution `updateOrLinkServiceIdAgentIds`
Keeping in mind that this function is executed only once
                uint256 agentId = agentIds[i];

                // Get agent Id value through multisig
                uint256 checkAgent = mapMultisigAgentIds[multisig];

                // Check for agent Id difference
                if (checkAgent != agentId) {
                    // Check agentWallet metadata
                    bytes memory agentWallet =
                        IIdentityRegistry(identityRegistry).getMetadata(agentId, AGENT_WALLET_METADATA_KEY);
                    // Decode multisig value
                    address oldMultisig = abi.decode(agentWallet, (address));

                    // Update agentWallet metadata and mapping
                    _updateAgentWallet(serviceId, agentId, oldMultisig, multisig);
                }

                // Get tokenUri
                string memory checkTokenUri = IERC721(identityRegistry).tokenURI(agentId);

                // Check for tokenUri difference
                if (keccak256(bytes(checkTokenUri)) != keccak256(bytes(tokenUri))) {
                    // Updated tokenUri in 8004 Identity Registry
                    _updateAgentUri(serviceId, agentId, tokenUri);
                }
```
[x] Noted, checked in several iterations

### Low/Notes. Double-check in manager controlled function.
```
function updateAgentWallet
The code does not check that the provided oldMultisig actually matches the current stored address for the given serviceId
like:
(,address multisig,,,,,) = IServiceRegistry(serviceRegistry).mapServices(serviceId);
if multisig != oldMultisig then revert()
This could overwrite data for the old multisig (not for this serviceId) by mistake. 
mapMultisigAgentIds[oldMultisig] = 0;

Always checked in ServiceManager (manager)? 
Ref: updateOrLinkServiceIdAgentIds - contradicts the hypothesis that the old multisig should be valid.
oldMultisig != IServiceRegistry(serviceRegistry).mapServices(serviceId) by design updateOrLinkServiceIdAgentIds
```
[x] Noted, verified

### Medium/Low. No Reentrancy protection
```
Missing in function:
linkServiceIdAgentIds
updateOrLinkServiceIdAgentIds
```
[x] Fixed 

### Low. Implementation 1271 more standard way. To discussion
```
mapSignedHashes[digest] = true; => mapSignedHashes[digest] = address;

Example:
function isValidSignature(bytes32 hash, bytes memory signature)
        external
        view
        returns (bytes4)
    {
        address expected = mapSignedHashes[hash];
        if (expected == address(0)) return FAILVALUE;

        if (signature.length == 0) {
            // no signature, just by hash? To discussion
            return MAGICVALUE;
        }

        // signer from signature (just example)
        if (signature.length == 65) {
            bytes32 r; bytes32 s; uint8 v;
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            if (uint256(s) == 0 && v == 27) { // needed v?
                address signer = address(uint160(uint256(r)));
                return signer == expected ? MAGICVALUE : FAILVALUE;
            }
        }

        return FAILVALUE;
    }
```
[x] Fixed

### Low. Optional: return 0xffffffff
```
https://eips.ethereum.org/EIPS/eip-1271

  function isValidSignature(
    bytes32 _hash,
    bytes calldata _signature
  ) external override view returns (bytes4) {
    // Validate signatures
    if (recoverSigner(_hash, _signature) == owner) {
      return 0x1626ba7e;
    } else {
      return 0xffffffff;
    }
  }

Historically, Gnosis Safe and other wallets returned 0xffffffff as a "magic value failure" for library convenience (easy comparison with MAGICVALUE).
OZ also uses this value in its IERC1271 interface:
bytes4 internal constant _INTERFACE_ID_INVALID = 0xffffffff;
Therefore, many SDKs/validators expect either 0x1626ba7e or 0xffffffff, but the standard doesn't require it.
Not MUST by standard!!!
```
[x] Fixed



# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `v1.3.3-pre-internal-audit` or 15f4acc50cec660b7ecfaf3856c39a6b3ee6313d <br> 

## Objectives
The audit focused on ERC-8004 bridge update.

### ERC20/ERC721 checks
N/A

### Storage
```
sol2uml storage contracts/ -f png -c ServiceManager -o audits/internal14/ServiceManager.png
```
[ServiceManager](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal14/ServiceManager.png)

### Coverage
```
-------------------------------------|----------|----------|----------|----------|----------------|
File                                 |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-------------------------------------|----------|----------|----------|----------|----------------|
IdentityRegistryBridger.sol           |    44.78 |    18.92 |     62.5 |    39.55 |... 537,540,542 |
```
[]   

### Issue
Question to auditor:
```
In this function

    function getAgentWallet(uint256 agentId) external view returns (address) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        bytes memory walletData = $._metadata[agentId]["agentWallet"];
        return address(bytes20(walletData));
    }

What happens if walletData does not exit and returns 0x? Is return still valid or need to check that if walletData == 0x?
```
#### Critical? Investigation convertion. Test please!!
```
Issue: getAgentWallet() decodes bytes → address incorrectly (format ambiguity)
Code under review
function getAgentWallet(uint256 agentId) external view returns (address) {
    IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
    bytes memory walletData = $._metadata[agentId]["agentWallet"];
    return address(bytes20(walletData));
}

A) What happens if walletData does not exist (returns 0x)?

If the metadata entry is missing, the mapping returns an empty byte array: walletData.length == 0, i.e. walletData == 0x.

In Solidity, the explicit conversion bytes → bytes20 does not revert when the source is shorter than 20 bytes. Missing bytes are zero-padded.

So:

bytes20(hex"") becomes 0x0000000000000000000000000000000000000000

address(bytes20(hex"")) becomes address(0)

OK - Result: the function returns address(0) and does not revert.

Conclusion: If the intended semantics are “missing metadata ⇒ wallet is zero address,” then no additional check is required for the 0x case specifically.

B) The real risk: the stored format may be 32 bytes (abi.encode(address)), but you read the first 20 bytes

The critical risk is not the empty case; it’s format mismatch.

Many systems store an address in bytes form using:

bytes memory data = abi.encode(someAddress);


This produces a 32-byte ABI word with the address right-aligned (left padded with zeros):

Layout: 0x000000000000000000000000 <20-byte-address>

Total length: 32 bytes

If your code does:

address(bytes20(walletData))


it takes the first 20 bytes of the 32-byte payload, which are (almost always) zero:

First 12 bytes are definitely zero

Next 8 bytes are the start of the word padding, still zero

You do not take the last 20 bytes where the real address sits

OK - So it will decode to address(0) (or some wrong value) even though the metadata is present and correct.

Why this is severe

This creates a “silent failure”:

the storage contains a valid address,

reads return address(0),

downstream logic may interpret that as “no wallet set” and may overwrite, mis-route, or skip checks.

This is not a revert; it is a semantic decoding bug that can pass reviews unless tested against a realistic registry implementation.

Where the same bug appears again

You mentioned:

metadata = IIdentityRegistry(identityRegistry).getMetadata(agentId, AGENT_WALLET_METADATA_KEY);
address oldMultisig = address(bytes20(metadata));


This is the same risk. If the upstream identityRegistry returns a 32-byte ABI encoding, oldMultisig will decode incorrectly.

Correct decoding requires defining the storage format
Option 1 (recommended): store as ABI encoding (32 bytes), decode with abi.decode

Store:

_metadata[agentId]["agentWallet"] = abi.encode(wallet);


Read:

function _bytesToAddressAbi(bytes memory b) internal pure returns (address a) {
    if (b.length == 0) return address(0);
    if (b.length != 32) revert InvalidAddressEncoding(b.length);
    a = abi.decode(b, (address));
}

Option 2: store as raw 20 bytes, decode with bytes20

Store:

_metadata[agentId]["agentWallet"] = abi.encodePacked(wallet); // 20 bytes


Read:

function _bytesToAddress20(bytes memory b) internal pure returns (address a) {
    if (b.length == 0) return address(0);
    if (b.length != 20) revert InvalidAddressEncoding(b.length);
    a = address(bytes20(b));
}

Option 3: be tolerant (support both 20 and 32)

If you must accept multiple formats (common in migrations), do:

function _bytesToAddressFlexible(bytes memory b) internal pure returns (address a) {
    if (b.length == 0) return address(0);

    if (b.length == 20) {
        return address(bytes20(b));
    }
    if (b.length == 32) {
        return abi.decode(b, (address));
    }

    revert InvalidAddressEncoding(b.length);
}


This prevents silent mis-decoding and makes migrations safer.

Test pattern that reproduces the bug (Foundry)

The goal: prove that if upstream returns abi.encode(address), then address(bytes20(metadata)) returns the wrong address (typically zero).

Minimal unit test (pure decoding demonstration)
function test_AddressDecodeMismatch() public {
    address expected = address(0x1234567890123456789012345678901234567890);

    bytes memory encoded32 = abi.encode(expected);         // 32 bytes ABI word
    bytes memory encoded20 = abi.encodePacked(expected);   // 20 bytes raw

    // The buggy decode pattern:
    address buggyFrom32 = address(bytes20(encoded32));
    address buggyFrom20 = address(bytes20(encoded20));

    // Correct decode:
    address correctFrom32 = abi.decode(encoded32, (address));
    address correctFrom20 = address(bytes20(encoded20));

    // This should fail (bug): buggyFrom32 != expected, usually equals address(0)
    assertTrue(buggyFrom32 != expected);
    assertEq(correctFrom32, expected);

    // This one "works by accident" if storage uses 20-byte packed format
    assertEq(buggyFrom20, expected);
    assertEq(correctFrom20, expected);
}

Integration-style test: mock registry returns 32 bytes

If your contract calls an external IIdentityRegistry.getMetadata(agentId, key), create a mock that returns abi.encode(addr) and ensure your contract misreads it.

Mock:

contract MockIdentityRegistry {
    mapping(uint256 => mapping(string => bytes)) public meta;

    function setMetadata(uint256 agentId, string calldata key, bytes calldata value) external {
        meta[agentId][key] = value;
    }

    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory) {
        return meta[agentId][key];
    }
}


Test:

function test_getAgentWallet_MisdecodesAbiEncodedAddress() public {
    MockIdentityRegistry mock = new MockIdentityRegistry();

    uint256 agentId = 1;
    string memory key = "agentWallet";
    address wallet = address(0x1111111111111111111111111111111111111111);

    // Store as 32-byte ABI encoding (common pattern)
    mock.setMetadata(agentId, key, abi.encode(wallet));

    // Simulate what your code does:
    bytes memory walletData = mock.getMetadata(agentId, key);
    address decoded = address(bytes20(walletData)); // BUGGY

    // This assertion demonstrates the issue:
    assertTrue(decoded != wallet);
    // Often it is exactly zero:
    assertEq(decoded, address(0));
}

“Red flag” invariant test

If the system claims the wallet is set, it must not read as zero:

function test_walletSetMustNotReadAsZero() public {
    address wallet = address(0x2222222222222222222222222222222222222222);
    bytes memory stored = abi.encode(wallet);

    // Your decode
    address decoded = address(bytes20(stored));

    // Fails if registry uses abi.encode
    assertTrue(decoded != address(0), "Wallet unexpectedly reads as zero");
}


This catches the failure without caring about exact expected address.

Recommended audit wording (you can paste into your report)

Finding: Address decoding from metadata may be incorrect due to format mismatch.
The contract reads the agent wallet as address(bytes20(walletData)). If the metadata is absent (walletData == 0x), Solidity’s conversion zero-pads and returns address(0) without reverting, which may be acceptable. However, if the metadata is stored as a standard ABI-encoded address (abi.encode(address)), the payload is 32 bytes with the address in the last 20 bytes. Casting to bytes20 takes the first 20 bytes, resulting in address(0) (or an incorrect value) even when the wallet is properly set. This is a silent semantic bug that can lead to incorrect wallet reads, improper updates, and broken bridging logic. The contract should define and enforce a single storage format and decode using abi.decode for 32-byte ABI encoding or enforce a 20-byte packed format (or implement a strict flexible decoder supporting both 20 and 32 bytes and reverting otherwise).
```
[]

#### Medium. numServices in linkServiceIdAgentIds
```
numServices can become 0—this is a real edge-case UX/DoS vulnerability for gas.

Even with the correct invariant, a "no work" situation is possible.

Currently, this results in an "empty" call with no progress, which can be spammed.

Recommendation (after adjustment):

if (numServices == 0) revert ZeroValue(); // or NoServicesToLink()
```
[]

#### Medium. incorrect lastServiceID with linkedAll = true;
```
If you're deliberately using linkedAll=true to mean "we've encountered the first already-linked record ⇒ legacy has ended," then the lastServiceId in the event doesn't necessarily mean "last processed." It currently means "planned upper bound of the batch/next start," while linkedAll means "the feature is disabled."

However, for log usability, it's better to:

emit the actual cutoff (where the break occurred) to avoid confusion for analytics/monitoring.

Mini-patch (without changing the logic):

uint256 cutoffServiceId = lastServiceId; // default

...
} else {
linkedAll = true;
cutoffServiceId = startServiceId + i; // serviceId
break;
}

...
emit StartLinkServiceIdUpdated(cutoffServiceId, linkedAll);
```
[]

#### Medium. Document the invariant directly in the code
```
Add a NatSpec comment above the function:

Legacy services are the range [1 .. L] without any gaps.

startLinkServiceId always points to the next unbound legacy serviceId.

If mapServiceIdAgentIds[startLinkServiceId] != 0, then the migration is complete and startLinkServiceId will be reset.

This is important for auditing.
```
[]

#### Notes. baseURI must contain a trailing /
```
    function _getAgentURI(uint256 serviceId) internal view returns (string memory) {
        return string(abi.encodePacked(baseURI, LibString.toString(serviceId)));
    }
    The function does not care about the correctness of the baseURI. This is not a mistake. Perhaps this should be explicitly added in NatSpec. 
```
[]


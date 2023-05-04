# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `v1.1.1.pre-internal-audit` <br> 

## Objectives
The audit focused on `one-shot upgrade and operating services with signatures` contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal3/analysis/contracts) 

### ERC20/ERC721 checks
N/A

### Security issues. Updated 04-05-23
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal3/analysis/slither_full.txt)

No issue.

#### ServiceManagerToken needs attention
```
        // Decode the signature
        uint8 v = uint8(signature[64]);
        // For the correct ecrecover() function execution, the v value must be set to {0,1} + 27
        // If v is set to just 0 or 1 when signing  by the EOA, it is most likely signed by the ledger and must be adjusted
        if (v < 2 && operator.code.length == 0) {
            // In case of a non-contract, adjust v to follow the standard ecrecover case
            v += 27;
        }
Theoretical part:
https://en.bitcoin.it/wiki/Secp256k1
field size p = FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFE FFFFFC2F ~= 2^256 - 2^32
curve order n = FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFE BAAEDCE6 AF48A03B BFD25E8C D0364141 ~= 2^256 - 2^128 < p
ref: ECDSA sign R = k * G and take its x-coordinate: r = R.x
When R.x is between n and p, r is reduced to R.x % n. Thus, if you have an r value below 2^128-2^32,
there may be 2 valid R.x values corresponding to it.
In result mathematically v (http://www.secg.org/sec1-v2.pdf):
0 y-parity 0, magnitude of x lower than the curve order
1 y-parity 1, magnitude of x lower than the curve order
2 y-parity 0, magnitude of x greater than the curve order
3 y-parity 1, magnitude of x greater than the curve order
v with 2,3 is very rare (0.000000000000000000000000000000000000373% to happen randomly)
In "bitcoin-like" library v defined as:
27 uncompressed public key, y-parity 0, magnitude of x lower than the curve order
28 uncompressed public key, y-parity 1, magnitude of x lower than the curve order
29 uncompressed public key, y-parity 0, magnitude of x greater than the curve order
30 uncompressed public key, y-parity 1, magnitude of x greater than the curve order
31 compressed public key, y-parity 0, magnitude of x lower than the curve order
32 compressed public key, y-parity 1, magnitude of x lower than the curve order
33 compressed public key, y-parity 0, magnitude of x greater than the curve order
34 compressed public key, y-parity 1, magnitude of x greater than the curve order
So, because in ETH-like network we don't use compressed public key v = 27-30
Practical part:
reserved v = 0..3 for ECDSA
v = 4 for EIP-1271 (isValidSignature)
v = 5 for pre-approved hash
```
[x] fixed

Small fixing:
```
        // Check for the signature length
        if (signature.length < 65) {
            revert IncorrectSignatureLength(signature, signature.length, 65);
        }
        to
        // Check for the signature length (> 65 or < 65 incorrect) 65 = 32+32+1
        if (signature.length != 65) {
            revert IncorrectSignatureLength(signature, signature.length, 65);
        }
```
[x] fixed

#### Design question
```
Assume the following setup:
const addressA = '0x067024faa81ACBF984EEA0E4E75Fcc3F44558AfD';
const addressAPrvtKey = 'xxx';

const {v,r,s} = sign(msg, addressAPrvtKey);

> v: 27
> r: 0x79855f28bdc327adbcbf85d32cb76b9aeef67dc5b9c4dafbd0a94ad3757ec501
> s: 0x3a51556f88edc2e218c5b6c540662bf289a09f16e3a0f505fcfe435dfb490a22

// When Recovering
const addressRecovered = ecrecover(msg, v, r, s);
> addressRecovered: 0x067024faa81ACBF984EEA0E4E75Fcc3F44558AfD

If v, r, s were changed to: 
> v: 27
> r: 0x1212121212121212121212121212121212121212121212121212121212121212 // Random
> s: 0x0000000000000000000000000000000001000000000000000000000000000000 // Random

// When Recovering
const addressRecovered = ecrecover(msg, v, r, s);
// Return a random ethereum address
> addressRecovered: 0xe2140bdbe71cdf1d1df3a6b5d85939d1ad313722
We can't predict what address we'll get. Can we somehow harm the protocol by using a random address that we have no control over?

via:
function unbondWithSignature(
        address operator,
        uint256 serviceId,
        bytes memory signature
    ) external returns (bool success, uint256 refund)
    {}

function registerAgentsWithSignature(
        address operator,
        uint256 serviceId,
        address[] memory agentInstances,
        uint32[] memory agentIds,
        bytes memory signature
    ) external payable returns (bool success) {}
```
[x] fixed by design: the ServiceRegistry contract has a check for the unbonded number of agent instances of the operator in the service:
https://github.com/valory-xyz/autonolas-registries/blob/784d312b0eb34ff7dcb4a7d4639d51a7eb76d77e/contracts/ServiceRegistry.sol#L687-L697
Also, the unbond and register agents with signature can be only called by the service owner that provides the dedicated
operator address as well, meaning that the service owner is responsible to verify the data before calling these functions.
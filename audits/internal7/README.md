# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `v1.2.5-pre-internal-audit` <br> 

## Objectives
The audit focused on recovery modules contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal7/analysis/contracts) 

### ERC20/ERC721 checks
N/A

### Coverage
```
 contracts/multisigs/                |    98.63 |     62.5 |      100 |    86.72 |                |
  RecoveryModule.sol                 |      100 |       50 |      100 |    81.43 |... 359,362,369 |
  SafeMultisigWithRecoveryModule.sol |     87.5 |       20 |      100 |    73.33 |    50,74,75,79 |
```
[]

### Security issues. Updated 30-04-25
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal7/analysis/slither_full.txt)
```
INFO:Detectors:
RecoveryModule.recoverAccess(uint256).owners (RecoveryModule-flatten.sol#1815) shadows:
```
[]

### Issue
#### Reentrancy issue. Low issue
```
function recoverAccess(uint256 serviceId) {}
function create(address[] memory owners, uint256 threshold, bytes memory data) external returns (address multisig) {}
```
[]

#### Remove import "hardhat/console.sol";
```
Remove console.sol in product mode.
```
[]

#### Notes/Question 1
```
Should I check `threshold` before first use?
function create(address[] memory owners, uint256 threshold, bytes memory data) external returns (address multisig) {
...
payload = abi.encodeCall(IMultisig.removeOwner, (owners[0], serviceOwner, threshold));
}
```
[]

#### Notes/Question 2
```
Is it possible that this is the case with `else` and what should be done then?
if (checkOwners.length == 1 && checkOwners[0] == serviceOwner) { } else {??}
```
[]



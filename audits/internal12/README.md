# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `tag: v1.3.1-internal-audit` or 3e81be24297bc80a8dee1e8112a80b3671b8f883 <br> 

## Objectives
The audit focused on ApplicationClassifier.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal12/analysis/contracts) 

### ERC20/ERC721 checks
N/A

### Coverage
```
-------------------------------------|----------|----------|----------|----------|----------------|
File                                 |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-------------------------------------|----------|----------|----------|----------|----------------|
  ApplicationClassifier.sol          |        0 |        0 |        0 |        0 |... 116,120,122 |
  ApplicationClassifierProxy.sol     |        0 |        0 |        0 |        0 |... 51,52,59,76 |
```
- Needed test for ApplicationClassifier
[]  

### Security issues.
#### Problems found instrumentally
No issue
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal12/analysis/slither_full.txt)

### Issue
#### Notes. payable proxy?
```
If you ever need payable logic, extend the proxy (fallback() external payable).
I don't see why this would be necessary based on the current logic.
```
[] 
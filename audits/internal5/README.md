# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `v1.2.0-internal-audit` <br> 

## Objectives
The audit focused on `PooA Staking` contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal5/analysis/contracts) 

### ERC20/ERC721 checks
N/A

### Security issues. Updated 14-05-24
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal5/analysis/slither_full.txt)


# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `tag: v1.2.6-pre-internal-audit` <br> 

## Objectives
The audit focused on metadate hash updater contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal8/analysis/contracts) 

### ERC20/ERC721 checks
N/A

### Coverage
```
ComplementaryServiceMetadata.sol   |        0 |        0 |        0 |        0 |... 103,105,107
```
No tests
[x] Fixed

### Security issues. Updated 22-05-25
#### Problems found instrumentally
No issue
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal8/analysis/slither_full.txt)

### Issue
### Notes/Question
```
        // Check for multisig access when the service is deployed
        if (state == IServiceRegistry.ServiceState.Deployed) {
            if (msg.sender != multisig) {
                revert UnauthorizedAccount(msg.sender);
            }
        } else {
            // Get service owner
            address serviceOwner = IServiceRegistry(serviceRegistry).ownerOf(serviceId);

            // Check for service owner
            if (msg.sender != serviceOwner) {
                revert UnauthorizedAccount(msg.sender);
            }
        }
        Can there be a service state in which changing the hash is prohibited?
```
[x] There is no such state


# Re-audit 23.05.2025
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `tag: v1.2.7-pre-internal-audit` <br>

## Objectives
The audit focused on metadate hash updater contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal8/analysis/contracts) 

### Valid coverage
```
ComplementaryServiceMetadata.sol   |      100 |    91.67 |      100 |    94.74 |             79 |
```

### Security issues. Updated 23-05-25
#### Problems found instrumentally
No issue
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal8/analysis/slither_full.txt)

### Issue
No issue


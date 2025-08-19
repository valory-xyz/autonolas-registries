# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `tag: v1.2.8-pre-internal-audit` <br> 

## Objectives
The audit focused on update StakingBase.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal9/analysis/contracts) 

### ERC20/ERC721 checks
N/A

### Coverage
```
-------------------------------------|----------|----------|----------|----------|----------------|
File                                 |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-------------------------------------|----------|----------|----------|----------|----------------|
 contracts/                          |      100 |    98.93 |      100 |      100 |                |
  StakingBase.sol                    |     97.3 |    94.53 |      100 |    94.22 |... 697,698,709 |
```
No full coverage
[] 

### Security issues. Updated 19-08-25
#### Problems found instrumentally
No issue
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal9/analysis/slither_full.txt)

### Issue
### Notes/Question . Probably incorrect comments
```
function _getRewardReceiversAndAmounts()
...
if (rewardDistributionType == RewardDistributionType.Proportional) {
..
}
What the code does now:
Takes a list of agent instances, counts the total number of recipients: numInstances + 1 (service owner).
Divides the reward equally between all recipients: operatorReward = reward / totalNumReceivers.
Pays each operator operatorReward.
Pays the owner the remainder: reward - (numInstances * operatorReward).
Important: this formula is equivalent to `ownerReward = operatorReward + (reward % totalNumReceivers)`.
That is, the owner gets his equal share + the remainder (if any). 
The comment "Service owner gets a division remainder" is slightly misleading: the owner gets not only remainder, but an equal share plus remainder.
The total payment is always exactly reward.

Edge cases and behavior:
numInstances = 0: everything goes to the owner - expectedly correct.
reward < totalNumReceivers: operatorReward == 0, all operators will get 0, the owner will get the whole reward. This may be normal, because practical impossible.
Operator duplicates: if the same operator is found in multiple instances, it will get multiple shares - this may be the intended behavior. This is not a question of optimization, but of the correctness of the calculation of shares.
```
[x] Noted and intended behavior





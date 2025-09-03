# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `tag: v1.2.8-pre-internal-audit` or 105f48e774df454a6d8fcc95551b723862928622 <br> 

## Objectives
The audit focused on next update StakingBase.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal10/analysis/contracts) 

### ERC20/ERC721 checks
N/A

### Coverage
```
-------------------------------------|----------|----------|----------|----------|----------------|
File                                 |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-------------------------------------|----------|----------|----------|----------|----------------|
 contracts/                          |      100 |    98.93 |      100 |      100 |                |
  StakingBase.sol                    |     98.7 |    93.75 |      100 |    96.99 |... 704,798,799 |
```
- No full coverage
- Non tested critical bug!
[] 

### Security issues. Updated 03-09-25
#### Problems found instrumentally
No issue
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal10/analysis/slither_full.txt)

### Issue
### Critical issue. Incorrect operation with enum.
```
RewardDistributionType rewardDistributionType = RewardDistributionType(rewardDistributionInfo);
not meaning rewardDistributionType = (uint8(rewardDistributionInfo))
if rewardDistributionInfo > 2^8 
=>
VM Exception while processing transaction: reverted with panic code 0x21 (Tried to convert a value into an enum, but the value was too big or negative)

correct 
RewardDistributionType rewardDistributionType = RewardDistributionType(uint8(rewardDistributionInfo));

dirty proof:
console.log("rewardDistributionInfo", rewardDistributionInfo);
if(rewardDistributionInfo < 256) {
    rewardDistributionInfo += 2**100; // test rewardDistributionInfo = address + type
}
RewardDistributionType rewardDistributionType = RewardDistributionType(rewardDistributionInfo);
=> panic 0x21
```
[]

### Notes. Aviod non-custom and dirty high bits.
```
better:
if
    (rewardDistributionType != RewardDistributionType.Custom) 
    and
    address(uint160(rewardDistributionInfo >> 8) != address(0)
then
    revert

```
[]




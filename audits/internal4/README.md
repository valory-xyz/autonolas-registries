# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `v1.1.7.pre-internal-audit` <br> 

## Objectives
The audit focused on `staking a service` contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal4/analysis/contracts) 

### ERC20/ERC721 checks
N/A

### Security issues. Updated 04-10-23
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full-04-10-23](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal4/analysis/slither_full_04_10_23.txt)

Bad pattern (ref: reentrancy): <br>
```solidity
unstake:
Doesn't match the pattern Checks, Effects, and Interactions (CEI):
_withdraw(sInfo.multisig, sInfo.reward); in middle
```
[x] fixed

Reentrancy critical issue: <br>
```solidity
ServiceStaking.unstake -> _withdraw -> to.call{value: amount}("") -> ServiceStaking.unstake (sInfo.reward > 0 ??) -> _withdraw -> to.call{value: amount}("")
```
[x] fixed, protected by the unstake() function as the service data will be deleted

Reentrancy medium issue: <br>
```solidity
ServiceStakingToken.unstake -> _withdraw -> SafeTransferLib.safeTransfer(stakingToken, to, amount); -> ServiceStaking.unstake
via custom stakingToken
```
[x] fixed, protected by the unstake() function as the service data will be deleted

Reentrancy low issue: <br>
```solidity
ServiceStakingToken.deposit -> SafeTransferLib.safeTransfer(stakingToken, to, amount); -> ServiceStaking.deposit
via custom stakingToken
```
[x] fixed

Pointer bug (thanks Aleksandr Kuperman) <br>
```
ServiceInfo memory sInfo = mapServiceInfo[serviceId];
(uint256[] memory serviceIds, , , , , ) = checkpoint(); // mapServiceInfo[curServiceId].reward += updatedReward;
sInfo.reward;
Incorrect state when updating in checkpoint()
```

Low problem: <br>
```solidity
function checkpoint() public returns ()
uint256 curServiceId; 
vs
// Get the current service Id
uint256 curServiceId = serviceIds[i];
Details: https://github.com/crytic/slither/wiki/Detector-Documentation#variable-names-too-similar
Reusing a same variable name in different scopes.
```
[x] fixed

```solidity
    if (state != 4) {
        revert WrongServiceState(state, serviceId);
    }
It's better to use the original type enum.
Details: https://github.com/pessimistic-io/slitherin/blob/master/docs/magic_number.md
```
[x] fixed

### Low optimization
```
if (size > 0) {
            for (uint256 i = 0; i < size; ++i) {
                // Agent Ids must be unique and in ascending order
                if (_stakingParams.agentIds[i] <= agentId) {
                    revert WrongAgentId(_stakingParams.agentIds[i]);
                }
                agentId = _stakingParams.agentIds[i];
                agentIds.push(agentId);
            }
        }
if size == 0 then for(i = 0; i < 0; i++) -> no loop
```
[x] fixed
```
        // Transfer the service for staking
        IService(serviceRegistry).safeTransferFrom(msg.sender, address(this), serviceId);
        Last operation?
```
[x] verified, this reentrancy cannot take place as the ERC721 implementation calls ERC721TokenReceiver(to), where to is
a staking contract

### General considerations
Measuring the number of live transactions through a smart contract has fundamental limitations: <br>
Ethereum smart contracts only have access to the current state - not to historical states at previous blocks. <br>
Also, there's currently no EVM opcode (hence no Solidity function) to look up the amount of transactions by an address. <br>
Therefore, we have to rely on the internal counter "nonce" to measure tps (tx per sec). <br>
https://github.com/safe-global/safe-contracts/blob/1cfa95710057e33832600e6b9ad5ececca8f7839/contracts/Safe.sol#L167 <br>

In this contract, we assume that the services  are mostly honest and are not trying to tamper with this counter. <br>
ref: IService(serviceRegistry).safeTransferFrom(msg.sender, address(this), serviceId); <br>

There are two ways to fake it: <br>
1. Fake multisig. Open question
```solidity
        (uint96 stakingDeposit, address multisig, bytes32 hash, uint256 agentThreshold, uint256 maxNumInstances, , uint8 state) =
            IService(serviceRegistry).mapServices(serviceId);
sInfo.multisig = multisig;
sInfo.owner = msg.sender;
uint256 nonce = IMultisig(multisig).nonce();
Thus, it is trivial to tweak nonce it now if there is some trivial contract with the method setNonce(uint256);

If you wish, you can fight, for example, using this method
hash(multisig.code) vs well-know hash
```
Is it possible to replace the multisig with some kind of fake one without losing the opportunity to receive rewards? <br>
Notes: re-checking logic in contracts\multisigs\GnosisSafeSameAddressMultisig.sol (!) and update logic if necessary.
[x] fixed, but the GnosisSafeSameAddressMultisig contract needs to be addressed as well at some point

2. "Normal" multisig. Open question
```
https://github.com/safe-global/safe-contracts/blob/main/contracts/Safe.sol#L139
We can call execTransaction from another contract as owner in loop.
            txHash = getTransactionHash( // Transaction info
                ...
                nonce++
            );
            checkSignatures(txHash, "", signatures);

I don't see a way to deal with this. Moreover, it is practically indistinguishable from normal use.
Estimating gas consumption will not give us anything either. Only by off-chain measurement can we understand what is happening.
```
Suggestion: Do nothing. <br> 
Updated (10.10.2023): add custom blacklist <br>

### Found during fuzzing. Updated 10-10-23
#### Library that changes the value of nonce for legitimate multisig
It turned out that if you know the architecture of Saf1 1.3.x it is not difficult to write a library for changing nonce. <br>
Two conclusions follow from this: <br>
1. The initial assumption that `nonce` can only increase is wrong. So, serviceNonces[i] - curInfo.nonce must be checked by > 0. <br>
Else without it: ratio = ((serviceNonces[i] - curInfo.nonce) * 1e18) / ts; => DOS (revert) in _calculateStakingRewards() with any serviceNonces[i] - curInfo.nonce < 0 <br>
2. ref: General considerations #2. We cannot guarantee the absence of manipulation nonce through any checks within the contract. <br>
A reasonable proposal in this case is to provide the opportunity to add a blacklist of services when deploying a staking contract. <br>
This will make it possible to blacklist services with a bad reputation (which is not part of the protocol, but determined by the community). <br>
[x] discussed

#### Simple function needed `isServiceStaked`
[x] fixed

#### _stakingParams.minStakingDeposit
minStakingDeposit must be greater than 1 otherwise it causes confusion with the predefined value of 1.

[x] fixed

### Security issues. Updated 17-10-23
#### Latest CEI fix
```solidity
latest CEI fixup:
IService(serviceRegistry).safeTransferFrom(msg.sender, address(this), serviceId);
to
 // Add the service Id to the set of staked services
        setServiceIds.push(serviceId);
--->
        emit ServiceStaked(serviceId, msg.sender, service.multisig, nonces[0]);
This is not a real problem, but will avoid discussions with external auditors.
```
[x] fixed

##### Nonces should now be an array, including events.
```solidity
uint256[] memory nonces = _getMultisigNonces(service.multisig);
icorrect for ServiceStaking*MechUsage
emit ServiceStaked(serviceId, msg.sender, service.multisig, nonces[0]);
->
event ServiceStaked(uint256 indexed serviceId, address indexed owner, address indexed multisig, uint256[] nonce);
emit ServiceStaked(serviceId, msg.sender, service.multisig, nonces);
```
[x] fixed

##### Missing checks on MechAgentMod
```solidity
        // If the checkpoint was called in the exact same block, the ratio is zero
        if (ts > 0 && curNonces[0] > lastNonces[0]) {
            uint256 ratio = ((curNonces[0] - lastNonces[0]) * 1e18) / ts;
            ratioPass = (ratio >= livenessRatio);
        }

        vs
        
        uint256 diffNonces = curNonces[0] - lastNonces[0];
        uint256 diffRequestsCounts = curNonces[1] - lastNonces[1];
        // Sanity checks for requests counts difference to be at least half of the nonces difference
        if (diffRequestsCounts <= diffNonces / 2) {
            uint256 ratio = (diffRequestsCounts * 1e18) / ts;
            ratioPass = (ratio >= _getLivenessRatio() / 2);
        }
```
[x] fixed

### Security issues. Updated 25-10-23
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `v1.1.7.pre-internal-audit` or `387ba93deeb36849c1c205711b97a2c6da0f2745`<br> 
Re-audit after extract Mech contracts into a separate repo. <br>
[slither-full-25-10-23](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal4/analysis/slither_full_25_10_23.txt)
I don't see any new problems after optimization. <br>


### Security issues. Updated 29-11-23
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `tag: v1.1.8-pre-internal-audit` or `99eef0ffd2450311b2770faceac37191a13af5cb`<br>
Re-audit after changes ServiceStakingBase. <br>
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal4/analysis/slither_full.txt)

#### Notes (critical improvements)
Due to the impossibility of manually assessing the correctness of the logic at the boundaries of ```_evict``` 
"evict" must be part of ServiceStaking.t.sol (fuzzing) <br>
or equivalent in js tests <br>
Clarification required on the source code of the tests: <br>
```solidity
We need cases:
numEvictServices == 1
numEvictServices > 1
numEvictServices == setServiceIds
numEvictServices < setServiceIds
```
[x] tests are in place

```solidity
is it possible to exclude a special case
        // Deal with the very first element
        // Get the evicted service index
        idx = serviceIndexes[0];
        // Assign last service Id to the index that points to the evicted service Id
        setServiceIds[idx] = setServiceIds[totalNumServices - 1];
        // Pop the last element
        setServiceIds.pop();
        and move it under for()
```
[x] fixed


#### Notes (unstake scenario)
```solidity
        // Check that the service has staked long enough, or if there are no rewards left
        uint256 ts = block.timestamp - tsStart;
        if (ts <= maxAllowedInactivity && availableRewards > 0) {
            revert NotEnoughTimeStaked(serviceId, ts, maxAllowedInactivity);
        }

        1.  Service staking
        2.  Service inactive all time // if (serviceInactivity[i] > maxAllowedInactivity)
        2a. Service evict    // _evict(evictServiceIds, serviceInactivity, numServices);
        3.  Service try unstake in 1s after 2a. // => tsStart = sInfo.tsStart; ts = block.timestamp - tsStart;
        ??? What will happen?

        What is the expected scenario for this barrier?
        // Check that the service has staked long enough, or if there are no rewards left
        uint256 ts = block.timestamp - tsStart;
        if (ts <= maxAllowedInactivity && availableRewards > 0) {
            revert NotEnoughTimeStaked(serviceId, ts, maxAllowedInactivity);
        } 
```
[x] behaves as expected

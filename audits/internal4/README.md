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
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal4/analysis/slither_full.txt)

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

# Low optimization
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
[x] fixed

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




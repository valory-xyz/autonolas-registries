# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `v1.2.0-internal-audit` <br> 

## Objectives
The audit focused on `PoAA Staking` contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal5/analysis/contracts) 

### ERC20/ERC721 checks
N/A

### Security issues. Updated 14-05-24
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal5/analysis/slither_full.txt)

#### Issue
1. It is better to add protection against reentrancy explicitly. StakingBase.
```sh
function unstake(uint256 serviceId) external returns (uint256 reward) {
// Transfer the service back to the owner
        IService(serviceRegistry).safeTransferFrom(address(this), msg.sender, serviceId);

        // Transfer accumulated rewards to the service multisig
        if (reward > 0) {
            _withdraw(multisig, reward);
        }
        ->
        function safeTransferFrom(
        address from,
        address to,
        uint256 id)
        ->
        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
}
Possible solution (?):
ServiceInfo storage sInfo = mapServiceInfo[serviceId];
if(sInfo.multisig == address(0)) {
    revert()
}
function stake(uint256 serviceId) external { - CEI
    IService(serviceRegistry).safeTransferFrom(msg.sender, address(this), serviceId);
    ->
    function safeTransferFrom(
        address from,
        address to,
        uint256 id)
    ->
    if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
}
```
[x] the function is re-entrance proof due to the struct being deleted

2. It is better to add protection against reentrancy explicitly. StakingFactor
```
function createStakingInstance() {
    reentrancy via implementation. 
}
```
[x] fixed

#### Low priority isssue
1. No events:
```sh
StakingVerifier.changeStakingLimits should emit an event for: 
	- rewardsPerSecondLimit = _rewardsPerSecondLimit 
```
[x] fixed

2. abi.encodeWithSelector vs abi.encodeCall()
```sh
Example of more safe way:
        bytes memory data = abi.encodeCall(
            MyContract(target).foo.selector,
            abi.encode((uint256(10), uint256(20)))
        );
        (bool success, bytes memory result) = target.call(data);
ref: https://detectors.auditbase.com/abiencodecall-over-signature-solidity
for
(bool success, bytes memory returnData) = activityChecker.staticcall(abi.encodeWithSelector(
            IActivityChecker.getMultisigNonces.selector, multisig));
(success, returnData) = activityChecker.staticcall(abi.encodeWithSelector(
                IActivityChecker.isRatioPass.selector, currentNonces, lastNonces, ts));
```
[x] fixed

3. Shadow variable. Check it, please.
```
StakingToken._checkTokenStakingDeposit(uint256,uint256,uint32[]).agentIds (StakingToken-flatten.sol#1329) shadows:
	- StakingBase.agentIds (StakingToken-flatten.sol#495) (state variable)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#local-variable-shadowing
```
[x] fixed

#### best practices
1. magic numbers: 63, 32 
```
if (success && returnData.length > 63 && (returnData.length % 32 == 0)) {
    rewrite magic numbers: 63, 32 as constant.
```
[x] noted

2. Upgrade solidity 0.8.23 to 0.8.25
```
Only for those L2 evm-chains where this is applicable (EVM version is cancun).
``` 
[x] fixed

#### Notes && question
1. StakingVerifier -> verifyInstance ->  IStaking(instance).stakingToken()
```sh
How will this work for StakingNativeToken? Bug?
```
[x] fixed

2. Will it work correctly StakingNativeToken with proxy pattern? Test it, please.
```sh
StakingFactory -> Proxy -> StakingNativeToken -> receive()
```
[x] tested with all the implementations, not an issue

3. What happens if you send ETH to StakingToken by mistake? Locked? Issue?
```sh
StakingToken locked ETH.
```
[x] tested, not an issue

# Re-audit 20.05.24

## Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `v1.2.1-internal-audit` <br>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal5/analysis2/contracts) 

### ERC20/ERC721 checks
N/A

### Security issues. Updated 20-05-24
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal5/analysis2/slither_full.txt)

#### Issue
1. Missing change numServicesLimit
```
function changeStakingLimits(
        uint256 _rewardsPerSecondLimit,
        uint256 _timeForEmissionsLimit,
        uint256 _numServicesLimit
        not changed numServicesLimit
```
[x] fixed

2. emissionsLimit missing in constructor
```
emissionsLimit = _rewardsPerSecondLimit * _timeForEmissionsLimit * _numServicesLimit; // missing in constructor
```
[x] fixed

#### Medium/low issue
1. Emit missing.
```
emissionsLimit not in StakingLimitsUpdated(_rewardsPerSecondLimit, _timeForEmissionsLimit, _numServicesLimit);
```
[x] fixed

2. Emit missing.
```
contract StakingFactory
function setInstanceStatus(address instance, bool isEnabled) external {
    // no emit
}
```
[x] fixed

3. Check for isContract() and zero-address for params? I guarantee this will raise questions at the external audit.
```
contract StakingVerifier:
function verifyInstance(address instance, address implementation) {
...
}
```
[x] fixed

4. Wrong comments. Return bool by code, return min(?!) by comments
```
function verifyInstance(address instance, address implementation) external view returns (bool) {
    // Return min(maxTime * numServices * rewardsPerSecond, maxRewards)
```
[x] fixed

5. StakingVerifier.numServicesLimit immutable?
[x] this is a tunable parameter

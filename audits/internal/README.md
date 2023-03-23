# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `f87881be5a0521a62225f785f02775af7199bbe2` <br> 

## Objectives
The audit focused on contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal/analysis/contracts) 

### ERC721 checks
```
slither-check-erc --erc ERC721 AgentRegistry.sol AgentRegistry
# Check AgentRegistry

## Check functions
[✓] balanceOf(address) is present
        [✓] balanceOf(address) -> (uint256) (correct return type)
        [✓] balanceOf(address) is view
[✓] ownerOf(uint256) is present
        [✓] ownerOf(uint256) -> (address) (correct return type)
        [✓] ownerOf(uint256) is view
[✓] safeTransferFrom(address,address,uint256,bytes) is present
        [✓] safeTransferFrom(address,address,uint256,bytes) -> () (correct return type)
        [✓] Transfer(address,address,uint256) is emitted
[✓] safeTransferFrom(address,address,uint256) is present
        [✓] safeTransferFrom(address,address,uint256) -> () (correct return type)
        [✓] Transfer(address,address,uint256) is emitted
[✓] transferFrom(address,address,uint256) is present
        [✓] transferFrom(address,address,uint256) -> () (correct return type)
        [✓] Transfer(address,address,uint256) is emitted
[✓] approve(address,uint256) is present
        [✓] approve(address,uint256) -> () (correct return type)
        [✓] Approval(address,address,uint256) is emitted
[✓] setApprovalForAll(address,bool) is present
        [✓] setApprovalForAll(address,bool) -> () (correct return type)
        [✓] ApprovalForAll(address,address,bool) is emitted
[✓] getApproved(uint256) is present
        [✓] getApproved(uint256) -> (address) (correct return type)
        [✓] getApproved(uint256) is view
[✓] isApprovedForAll(address,address) is present
        [✓] isApprovedForAll(address,address) -> (bool) (correct return type)
        [✓] isApprovedForAll(address,address) is view
[✓] supportsInterface(bytes4) is present
        [✓] supportsInterface(bytes4) -> (bool) (correct return type)
        [✓] supportsInterface(bytes4) is view
[✓] name() is present
        [✓] name() -> (string) (correct return type)
        [✓] name() is view
[✓] symbol() is present
        [✓] symbol() -> (string) (correct return type)
[✓] tokenURI(uint256) is present
        [✓] tokenURI(uint256) -> (string) (correct return type)

## Check events
[✓] Transfer(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed
        [✓] parameter 2 is indexed
[✓] Approval(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed
        [✓] parameter 2 is indexed
[✓] ApprovalForAll(address,address,bool) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed
```

```
slither-check-erc --erc ERC721 ComponentRegistry.sol ComponentRegistry
# Check ComponentRegistry

## Check functions
[✓] balanceOf(address) is present
        [✓] balanceOf(address) -> (uint256) (correct return type)
        [✓] balanceOf(address) is view
[✓] ownerOf(uint256) is present
        [✓] ownerOf(uint256) -> (address) (correct return type)
        [✓] ownerOf(uint256) is view
[✓] safeTransferFrom(address,address,uint256,bytes) is present
        [✓] safeTransferFrom(address,address,uint256,bytes) -> () (correct return type)
        [✓] Transfer(address,address,uint256) is emitted
[✓] safeTransferFrom(address,address,uint256) is present
        [✓] safeTransferFrom(address,address,uint256) -> () (correct return type)
        [✓] Transfer(address,address,uint256) is emitted
[✓] transferFrom(address,address,uint256) is present
        [✓] transferFrom(address,address,uint256) -> () (correct return type)
        [✓] Transfer(address,address,uint256) is emitted
[✓] approve(address,uint256) is present
        [✓] approve(address,uint256) -> () (correct return type)
        [✓] Approval(address,address,uint256) is emitted
[✓] setApprovalForAll(address,bool) is present
        [✓] setApprovalForAll(address,bool) -> () (correct return type)
        [✓] ApprovalForAll(address,address,bool) is emitted
[✓] getApproved(uint256) is present
        [✓] getApproved(uint256) -> (address) (correct return type)
        [✓] getApproved(uint256) is view
[✓] isApprovedForAll(address,address) is present
        [✓] isApprovedForAll(address,address) -> (bool) (correct return type)
        [✓] isApprovedForAll(address,address) is view
[✓] supportsInterface(bytes4) is present
        [✓] supportsInterface(bytes4) -> (bool) (correct return type)
        [✓] supportsInterface(bytes4) is view
[✓] name() is present
        [✓] name() -> (string) (correct return type)
        [✓] name() is view
[✓] symbol() is present
        [✓] symbol() -> (string) (correct return type)
[✓] tokenURI(uint256) is present
        [✓] tokenURI(uint256) -> (string) (correct return type)

## Check events
[✓] Transfer(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed
        [✓] parameter 2 is indexed
[✓] Approval(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed
        [✓] parameter 2 is indexed
[✓] ApprovalForAll(address,address,bool) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed

```
```
slither-check-erc --erc ERC721 ServiceRegistry.sol ServiceRegistry
# Check ServiceRegistry

## Check functions
[✓] balanceOf(address) is present
        [✓] balanceOf(address) -> (uint256) (correct return type)
        [✓] balanceOf(address) is view
[✓] ownerOf(uint256) is present
        [✓] ownerOf(uint256) -> (address) (correct return type)
        [✓] ownerOf(uint256) is view
[✓] safeTransferFrom(address,address,uint256,bytes) is present
        [✓] safeTransferFrom(address,address,uint256,bytes) -> () (correct return type)
        [✓] Transfer(address,address,uint256) is emitted
[✓] safeTransferFrom(address,address,uint256) is present
        [✓] safeTransferFrom(address,address,uint256) -> () (correct return type)
        [✓] Transfer(address,address,uint256) is emitted
[✓] transferFrom(address,address,uint256) is present
        [✓] transferFrom(address,address,uint256) -> () (correct return type)
        [✓] Transfer(address,address,uint256) is emitted
[✓] approve(address,uint256) is present
        [✓] approve(address,uint256) -> () (correct return type)
        [✓] Approval(address,address,uint256) is emitted
[✓] setApprovalForAll(address,bool) is present
        [✓] setApprovalForAll(address,bool) -> () (correct return type)
        [✓] ApprovalForAll(address,address,bool) is emitted
[✓] getApproved(uint256) is present
        [✓] getApproved(uint256) -> (address) (correct return type)
        [✓] getApproved(uint256) is view
[✓] isApprovedForAll(address,address) is present
        [✓] isApprovedForAll(address,address) -> (bool) (correct return type)
        [✓] isApprovedForAll(address,address) is view
[✓] supportsInterface(bytes4) is present
        [✓] supportsInterface(bytes4) -> (bool) (correct return type)
        [✓] supportsInterface(bytes4) is view
[✓] name() is present
        [✓] name() -> (string) (correct return type)
        [✓] name() is view
[✓] symbol() is present
        [✓] symbol() -> (string) (correct return type)
[✓] tokenURI(uint256) is present
        [✓] tokenURI(uint256) -> (string) (correct return type)

## Check events
[✓] Transfer(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed
        [✓] parameter 2 is indexed
[✓] Approval(address,address,uint256) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed
        [✓] parameter 2 is indexed
[✓] ApprovalForAll(address,address,bool) is present
        [✓] parameter 0 is indexed
        [✓] parameter 1 is indexed
```

### Fuzzing check, Update 06-07-22

Candidates to [fuzzing](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal/analysis/fuzzer): <br>
```
./echidna-test analysis/ServiceRegistry-flatten.sol --contract ServiceRegistryFuzzing --config echidna.yaml
-- no problems with negative overflow detected

./echidna-test analysis/UnitRegistry-flatten.sol --contract UnitRegistryFuzzing --config echidna.yaml
-- no problems with overflow (uint, array index) 
```

### Security issues. Updated 06-07-22
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal/analysis/slither_full.txt)

- Reentrancy in ServiceRegistry.create(): [fixed];
- ServiceManager.serviceUpdate(): [no return value](https://github.com/crytic/slither/wiki/Detector-Documentation#unused-return) [fixed];
- Shadowing of ERC721: [`name` variable](https://github.com/crytic/slither/wiki/Detector-Documentation#local-variable-shadowing) [fixed];
- ServiceRegistry.unbond(): no check for the [zero address](https://github.com/crytic/slither/wiki/Detector-Documentation#missing-zero-address-validation) [fixed];
- AgentRegistry._getSubComponents(): is called in a loop with [external calls](https://github.com/crytic/slither/wiki/Detector-Documentation/#calls-inside-a-loop) [not an issue by design];
- Reentrancy in ServiceRegistry.deploy(): [fixed];
- Different versions of Solidity are used: [fixed].

PoC reentrancy attack to ServiceRegistry.create <br>
[README.md](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal/analysis/reentrancyPoC/README.md) <br>
[ReentrancyAttacker.sol](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal/analysis/reentrancyPoC/ReentrancyAttacker.sol) <br>
[ServiceRegistry.js](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal/analysis/reentrancyPoC/ServiceRegistry.js) <br>
[ServiceRegistry.sol](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal/analysis/reentrancyPoC/ServiceRegistry.sol) <br>


#### ServiceRegistry needs attention
Since we do not destroy and burn services in latest PR, we need to clean up all the data when the service is terminated. <br>
Pay attention to `ServiceState.PreRegistration` after `unbond` <br>
```
function unbond(address operator, uint256 serviceId) external returns (bool success, uint256 refund) {
mapAgentParams[serviceAgent].bond;
```
[fixed]

### Needed improvements && bug fixing
Remove extra shift in key calculation:
```
Fix example.
uint256 serviceAgent = serviceId;
// serviceId occupies first 32 bits, agentId gets the next 32 bits
// serviceAgent |= serviceId << 32;
// serviceAgent |= uint256(agentInstances[i].agentId) << 64;
serviceAgent |= uint256(agentInstances[i].agentId) << 32;
```
```
AgentRegistry.sol
function _checkDependencies(uint32[] memory dependencies, uint256) internal virtual override {
unsed uint256
       

if (dependencies.length == 0) {
            revert ZeroValue();
        } - missed tests

```
[fixed]

```
GenericManager.sol
function changeOwner(address newOwner) external virtual - missed test

```
[fixed]

```
GenericRegistry.sol
function changeOwner(address newOwner) external virtual - missed test
function tokenURI - missed test

function setBaseURI(string memory bURI) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }
 
        // Check for the zero value
        if (bytes(bURI).length == 0) {
            revert ZeroValue();
        
- missed test
```
[fixed]

```
 ServiceRegistry.sol
function _initialChecks(
    // Check for the non-zero hash value
    if (configHash == "0x") {
        revert ZeroValue();
    } - probably missed test, pay attention

function update(
    // Check for the manager privilege for a service management
    if (manager != msg.sender) {
        revert ManagerOnly(msg.sender, manager);
    } - probably missed test, pay attention

activateRegistration
    // Check for the manager privilege for a service management
    if (manager != msg.sender) {
        revert ManagerOnly(msg.sender, manager);
    } - probably missed test

function deploy(
    if (manager != msg.sender) {
        revert ManagerOnly(msg.sender, manager);
    } - probably missed test
        
function terminate
    // Check for the manager privilege for a service management
    if (manager != msg.sender) {
        revert ManagerOnly(msg.sender, manager);
    } - probably missed test

function changeMultisigPermission(address multisig, bool permission) external returns (bool success) {
    // Check for the contract ownership
    if (msg.sender != owner) {
        revert OwnerOnly(msg.sender, owner);
    } - probably missed test
```
[fixed]

```
ServiceManager - not called in tests.

grep ServiceManager ./test/*
/autonolas-registries$ 

We need to study the reason for this.
```
[fixed]

#### Update 06-07-22
```
function getSubComponents(uint32[] memory unitIds) public  returns (uint32[] memory subComponentIds) {

        uint256 numUnits = unitIds.length;
        // Array of numbers of components per each unit Id
        uint256[] memory numComponents = new uint256[](numUnits);
        // 2D array of all the sets of components per each unit Id
        uint32[][] memory components = new uint32[][](numUnits);

        // Get total possible number of components and lists of components
        uint maxNumComponents; 
It is necessary to unify the type of variables to uint32.

``` 
[fixed]

```
No tests included ERC721 *transferFrom. No understanding of side effects (for all contracts based on ERC721) after such operation.
```
[fixed]


#### Update 22-04-23
More fuzzing using Echidna, including preconditioned contracts at a specific deployment stage, are introduced here: [more_fuzzing](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal/analysis/more_fuzzing).

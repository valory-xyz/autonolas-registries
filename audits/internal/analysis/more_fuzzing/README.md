# Preconditioned Fuzzing
In order to precondition fuzzing to a specific state of contracts, the following workflow has been executed:
- Install [Etheno](https://github.com/crytic/etheno) tool (`pip3 install --user etheno`);
- Read the [E2E testing guide](https://github.com/crytic/building-secure-contracts/blob/master/program-analysis/echidna/advanced/end-to-end-testing.md);
- Run the etheno node with setup JSON writing option (`etheno --ganache -x output_file.json`);
- In a separate terminal, run the hardhat script test that gets all the contracts in the desired state connected to the node (`npx hardhat test test_file.js --network local`);
- Add `initialize` field into the `echidna.yaml` file with the JSON produced after the script run;
- Now echidna can start with the state of contracts from the point where the script run has terminated.



```sh
cat echidna.yaml      
# assertion, overflow, property
testMode: overflow
corpusDir: echidna-corp
stopOnFail: false
# 0x6000 by default
codeSize: 0xaaaa
# only for ServiceRegistry
# initialize: audits/internal/analysis/more_fuzzing/init.json
coverage: true

rm -rf crytic-export       
rm -rf echidna-corp 
echidna contracts/flatten/AgentRegistry-flatten.sol --contract AgentRegistryProxy --config echidna.yaml
Analyzing contract: /home/andrey/valory/autonolas-registries/contracts/flatten/AgentRegistry-flatten.sol:AgentRegistryProxy
                                                          ┌─────────────────────────────────────────────────────Echidna 2.1.0────────────────────────────────────────────────────┐                                                          
                                                          │ Tests found: 1                                            │ Fetched contracts: 0/0                                   │                                                          
                                                          │ Seed: 91746721545298545                                   │ Fetched slots: 0/0                                       │                                                          
                                                          │ Unique instructions: 1947                                 │                                                          │                                                          
                                                          │ Unique codehashes: 2                                      │                                                          │                                                          
                                                          │ Corpus size: 2                                            │                                                          │                                                          
                                                          ├─────────────────────────────────────────────────────────Tests────────────────────────────────────────────────────────┤                                                          
                                                          │ Integer (over/under)flow: PASSED!                                                                                   ^│                                                          
                                                          ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤                                                          
                                                          │                                        Campaign complete, C-c or esc to exit                                         │                                                          
                                                          └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘                                                                                                                                                                                                                                              
                                                                                                                                                                                                                                            
--
cat echidna.yaml      
# assertion, overflow, property
testMode: assertion
corpusDir: echidna-corp
stopOnFail: false
# 0x6000 by default
codeSize: 0xaaaa
# only for ServiceRegistry
# initialize: audits/internal/analysis/more_fuzzing/init.json
coverage: true

rm -rf crytic-export
rm -rf echidna-corp
echidna contracts/flatten/AgentRegistry-flatten.sol --contract AgentRegistryProxy --config echidna.yaml     
Analyzing contract: /home/andrey/valory/autonolas-registries/contracts/flatten/AgentRegistry-flatten.sol:AgentRegistryProxy
                                                          ┌─────────────────────────────────────────────────────Echidna 2.1.0────────────────────────────────────────────────────┐                                                          
                                                          │ Tests found: 4                                            │ Fetched contracts: 0/0                                   │                                                          
                                                          │ Seed: 1097601396562511153                                 │ Fetched slots: 0/0                                       │                                                          
                                                          │ Unique instructions: 1947                                 │                                                          │                                                          
                                                          │ Unique codehashes: 2                                      │                                                          │                                                          
                                                          │ Corpus size: 2                                            │                                                          │                                                          
                                                          ├─────────────────────────────────────────────────────────Tests────────────────────────────────────────────────────────┤                                                          
                                                          │ AssertionFailed(..): PASSED!                                                                                        ^│                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in iComponentRegistryFF(): PASSED!                                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in iAgentRegistryF(): PASSED!                                                                              │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in calculateSubComponents(uint32[]): PASSED!                                                               │                                                          
                                                          │                                                                                                                      │                                                                                                                    ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤                                                          
                                                          │                                        Campaign complete, C-c or esc to exit                                         │                                                       
                                                          └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘      

--
cat echidna.yaml 
# assertion, overflow, property
testMode: overflow
corpusDir: echidna-corp
stopOnFail: false
# 0x6000 by default
codeSize: 0xaaaa
initialize: audits/internal/analysis/more_fuzzing/init.json
coverage: true

echidna contracts/flatten/ServiceRegistry-flatten.sol --contract ServiceRegistryProxy --config echidna.yaml     
Analyzing contract: /home/andrey/valory/autonolas-registries/contracts/flatten/ServiceRegistry-flatten.sol:ServiceRegistryProxy
                                                          ┌─────────────────────────────────────────────────────Echidna 2.1.0────────────────────────────────────────────────────┐                                                          
                                                          │ Tests found: 1                                            │ Fetched contracts: 0/0                                   │                                                          
                                                          │ Seed: 7278998091794675560                                 │ Fetched slots: 0/0                                       │                                                          
                                                          │ Unique instructions: 19332                                │                                                          │                                                          
                                                          │ Unique codehashes: 9                                      │                                                          │                                                          
                                                          │ Corpus size: 22                                           │                                                          │                                                          
                                                          ├─────────────────────────────────────────────────────────Tests────────────────────────────────────────────────────────┤                                                          
                                                          │ Integer (over/under)flow: PASSED!                                                                                   ^│                                                          
                                                          │                                                                                                                      │                                                          
                                                          ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤                                                          
                                                          │                                        Campaign complete, C-c or esc to exit                                         │                                                          
                                                          └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘                                                                                                                                                                                                       

--
cat echidna.yaml 
# assertion, overflow, property
testMode: assertion
corpusDir: echidna-corp
stopOnFail: false
# 0x6000 by default
codeSize: 0xaaaa
# only for ServiceRegistry
initialize: audits/internal/analysis/more_fuzzing/init.json
coverage: true

echidna contracts/flatten/ServiceRegistry-flatten.sol --contract ServiceRegistryProxy --config echidna.yaml
Analyzing contract: /home/andrey/valory/autonolas-registries/contracts/flatten/ServiceRegistry-flatten.sol:ServiceRegistryProxy
                                                          ┌─────────────────────────────────────────────────────Echidna 2.1.0────────────────────────────────────────────────────┐                                                          
                                                          │ Tests found: 24                                           │ Fetched contracts: 0/0                                   │                                                          
                                                          │ Seed: 7497953648602028681                                 │ Fetched slots: 0/0                                       │                                                          
                                                          │ Unique instructions: 19332                                │                                                          │                                                          
                                                          │ Unique codehashes: 9                                      │                                                          │                                                          
                                                          │ Corpus size: 22                                           │                                                          │                                                          
                                                          ├─────────────────────────────────────────────────────────Tests────────────────────────────────────────────────────────┤                                                          
                                                          │ AssertionFailed(..): PASSED!                                                                                        ^│                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in deploy(address,uint256,address,bytes): PASSED!                                                          │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getService(uint256): PASSED!                                                                            │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in activateRegistration(address,uint256): PASSED!                                                          │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in registerAgents(address,uint256,address[],uint32[]): PASSED!                                             │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in terminate(address,uint256): PASSED!                                                                     │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in create(address,bytes32,uint32[],(uint32,uint96)[],uint32): PASSED!                                      │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeOwner(address): PASSED!                                                                           │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getPreviousHashes(uint256): PASSED!                                                                     │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in unbond(address,uint256): PASSED!                                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeManager(address): PASSED!                                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in drain(): PASSED!                                                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getUnitIdsOfService(uint8,uint256): PASSED!                                                             │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getOperatorBalance(address,uint256): PASSED!                                                            │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeMultisigPermission(address,bool): PASSED!                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in slash(address[],uint96[],uint256): PASSED!                                                              │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getAgentInstances(uint256): PASSED!                                                                     │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in iServiceRegistryF(): PASSED!                                                                            │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in iComponentRegistryFF(): PASSED!                                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getInstancesForAgentId(uint256,uint256): PASSED!                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getAgentParams(uint256): PASSED!                                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in iAgentRegistryF(): PASSED!                                                                              │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeDrainer(address): PASSED!                                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in update(address,bytes32,uint32[],(uint32,uint96)[],uint32,uint256): PASSED!                              │                                                          
                                                          ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤                                                          
                                                          │                                        Campaign complete, C-c or esc to exit                                         │                                                          
                                                          └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘   
```

## In-place testing with Scribble
Add required rules as comments and run:
```
./scripts/scribble.sh scribble/ServiceRegistryAnnotated.sol
```

## Generic ServiceRegistry testing
Consult the coverage at: [coverage](generic_coverage.txt).

```
cat echidna.yaml 
# assertion, overflow, property
testMode: assertion
corpusDir: echidna-corp
stopOnFail: false
# 0x6000 by default
codeSize: 0xaaaa
coverage: true
rm -rf echidna-corp crytic-export
echidna contracts/flatten/ServiceRegistry-flatten-generic.sol --contract ServiceRegistryProxyGeneric --config echidna.yaml

                                                          ┌─────────────────────────────────────────────────────Echidna 2.1.0────────────────────────────────────────────────────┐                                                          
                                                          │ Tests found: 24                                           │ Fetched contracts: 0/0                                   │                                                          
                                                          │ Seed: 4133985180233142722                                 │ Fetched slots: 0/0                                       │                                                          
                                                          │ Unique instructions: 12824                                │                                                          │                                                          
                                                          │ Unique codehashes: 2                                      │                                                          │                                                          
                                                          │ Corpus size: 25                                           │                                                          │                                                          
                                                          ├─────────────────────────────────────────────────────────Tests────────────────────────────────────────────────────────┤                                                          
                                                          │ AssertionFailed(..): PASSED!                                                                                        ^│                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in deploy(address,uint256,address,bytes): PASSED!                                                          │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getService(uint256): PASSED!                                                                            │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in activateRegistration(address,uint256): PASSED!                                                          │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in registerAgents(address,uint256,address[],uint32[]): PASSED!                                             │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in terminate(address,uint256): PASSED!                                                                     │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in create(address,bytes32,uint32[],(uint32,uint96)[],uint32): PASSED!                                      │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeOwner(address): PASSED!                                                                           │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getPreviousHashes(uint256): PASSED!                                                                     │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in unbond(address,uint256): PASSED!                                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeManager(address): PASSED!                                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in drain(): PASSED!                                                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getUnitIdsOfService(uint8,uint256): PASSED!                                                             │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getOperatorBalance(address,uint256): PASSED!                                                            │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeMultisigPermission(address,bool): PASSED!                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in slash(address[],uint96[],uint256): PASSED!                                                              │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getAgentInstances(uint256): PASSED!                                                                     │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in iServiceRegistryF(): PASSED!                                                                            │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in iComponentRegistryFF(): PASSED!                                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getInstancesForAgentId(uint256,uint256): PASSED!                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getAgentParams(uint256): PASSED!                                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in iAgentRegistryF(): PASSED!                                                                              │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeDrainer(address): PASSED!                                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in update(address,bytes32,uint32[],(uint32,uint96)[],uint32,uint256): PASSED!                              │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                     v│                                                          
                                                          ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤                                                          
                                                          │                                        Campaign complete, C-c or esc to exit                                         │                                                          
                                                          └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘                                                          
```


## Scribble plus Echidna
### Test 1: State of deployed service
Here is the setup of testing:
- Add scribble annotations to ServiceRegistry.sol;
- Instrument the contract: `scribble contracts/scribble/ServiceRegistryAnnotated.sol --output-mode files --arm`;
- Run etheno in a different terminal window: `etheno --ganache -x instrumental.json`;
- Run a predefined hardhat test on ehteno: `npx hardhat test --network local`
  - Use `.only` in `audits/internal/analysis/more_fuzzing/ServiceRegistry.js` for the first test;
  - The test runs until the service is deployed;
- Run echidna based on `instrumental.json`.

```
cat echidna.yaml 
# assertion, overflow, property
testMode: assertion
corpusDir: echidna-corp
stopOnFail: false
# 0x6000 by default
codeSize: 0xaaaa
# only for ServiceRegistry
initialize: audits/internal/analysis/more_fuzzing/instrumental.json
coverage: true

rm -rf echidna-corp
rm -rf crytic-export/
echidna contracts/flatten/ServiceRegistry-flatten.sol --contract ServiceRegistryProxy --config echidna.yaml
Analyzing contract: /home/andrey/valory/autonolas-registries/contracts/flatten/ServiceRegistry-flatten.sol:ServiceRegistryProxy
                                                          ┌─────────────────────────────────────────────────────Echidna 2.1.0────────────────────────────────────────────────────┐                                                          
                                                          │ Tests found: 24                                           │ Fetched contracts: 0/0                                   │                                                          
                                                          │ Seed: 960472355853764652                                  │ Fetched slots: 0/0                                       │                                                          
                                                          │ Unique instructions: 19541                                │                                                          │                                                          
                                                          │ Unique codehashes: 9                                      │                                                          │                                                          
                                                          │ Corpus size: 22                                           │                                                          │                                                          
                                                          ├─────────────────────────────────────────────────────────Tests────────────────────────────────────────────────────────┤                                                          
                                                          │ AssertionFailed(..): PASSED!                                                                                        ^│                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in deploy(address,uint256,address,bytes): PASSED!                                                          │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getService(uint256): PASSED!                                                                            │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in activateRegistration(address,uint256): PASSED!                                                          │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in registerAgents(address,uint256,address[],uint32[]): PASSED!                                             │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in terminate(address,uint256): PASSED!                                                                     │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in create(address,bytes32,uint32[],(uint32,uint96)[],uint32): PASSED!                                      │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeOwner(address): PASSED!                                                                           │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getPreviousHashes(uint256): PASSED!                                                                     │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in unbond(address,uint256): PASSED!                                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeManager(address): PASSED!                                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in drain(): PASSED!                                                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getUnitIdsOfService(uint8,uint256): PASSED!                                                             │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getOperatorBalance(address,uint256): PASSED!                                                            │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeMultisigPermission(address,bool): PASSED!                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in slash(address[],uint96[],uint256): PASSED!                                                              │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getAgentInstances(uint256): PASSED!                                                                     │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in iServiceRegistryF(): PASSED!                                                                            │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in iComponentRegistryFF(): PASSED!                                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getInstancesForAgentId(uint256,uint256): PASSED!                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in getAgentParams(uint256): PASSED!                                                                        │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in iAgentRegistryF(): PASSED!                                                                              │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in changeDrainer(address): PASSED!                                                                         │                                                          
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │                                                          
                                                          │ assertion in update(address,bytes32,uint32[],(uint32,uint96)[],uint32,uint256): PASSED!                              │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                                                                                                      │                                                          
                                                          │                                        Campaign complete, C-c or esc to exit                                         │                                                          
                                                          └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘     
```


### Test 2: State of deployed, terminated and unbonded service
Here is the setup of testing:
- Add scribble annotations to ServiceRegistry.sol;
- Instrument the contract: `scribble contracts/scribble/ServiceRegistryAnnotated.sol --output-mode files --arm`;
- Run etheno in a different terminal window: `etheno --ganache -x instrumental2.json`;
- Run a predefined hardhat test on ehteno: `npx hardhat test --network local`
    - Use `.only` in `audits/internal/analysis/more_fuzzing/ServiceRegistry.js` for the second test;
    - The test runs until the service is deployed, terminated and unbonded;
- Run echidna based on `instrumental2.json`.

```
cat echidna.yaml
# assertion, overflow, property
testMode: assertion
corpusDir: echidna-corp
stopOnFail: false
# 0x6000 by default
codeSize: 0xaaaa
# only for ServiceRegistry
initialize: audits/internal/analysis/more_fuzzing/instrumental2.json
coverage: true
rm -rf echidna-corp
rm -rf crytic-export
echidna contracts/flatten/ServiceRegistry-flatten.sol --contract ServiceRegistryProxy --config echidna.yaml
Analyzing contract: /home/andrey/valory/autonolas-registries/contracts/flatten/ServiceRegistry-flatten.sol:ServiceRegistryProxy
                                                          ┌─────────────────────────────────────────────────────Echidna 2.1.0────────────────────────────────────────────────────┐
                                                          │ Tests found: 24                                           │ Fetched contracts: 0/0                                   │
                                                          │ Seed: 9032281228957739964                                 │ Fetched slots: 0/0                                       │
                                                          │ Unique instructions: 16168                                │                                                          │
                                                          │ Unique codehashes: 6                                      │                                                          │
                                                          │ Corpus size: 20                                           │                                                          │
                                                          ├─────────────────────────────────────────────────────────Tests────────────────────────────────────────────────────────┤
                                                          │ AssertionFailed(..): PASSED!                                                                                        ^│
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in deploy(address,uint256,address,bytes): PASSED!                                                          │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in getService(uint256): PASSED!                                                                            │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in activateRegistration(address,uint256): PASSED!                                                          │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in registerAgents(address,uint256,address[],uint32[]): PASSED!                                             │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in terminate(address,uint256): PASSED!                                                                     │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in create(address,bytes32,uint32[],(uint32,uint96)[],uint32): PASSED!                                      │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in changeOwner(address): PASSED!                                                                           │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in getPreviousHashes(uint256): PASSED!                                                                     │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in unbond(address,uint256): PASSED!                                                                        │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in changeManager(address): PASSED!                                                                         │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in drain(): PASSED!                                                                                        │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in getUnitIdsOfService(uint8,uint256): PASSED!                                                             │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in getOperatorBalance(address,uint256): PASSED!                                                            │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in changeMultisigPermission(address,bool): PASSED!                                                         │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in slash(address[],uint96[],uint256): PASSED!                                                              │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in getAgentInstances(uint256): PASSED!                                                                     │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in iServiceRegistryF(): PASSED!                                                                            │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in iComponentRegistryFF(): PASSED!                                                                         │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in getInstancesForAgentId(uint256,uint256): PASSED!                                                        │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in getAgentParams(uint256): PASSED!                                                                        │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in iAgentRegistryF(): PASSED!                                                                              │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in changeDrainer(address): PASSED!                                                                         │
                                                          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────── │
                                                          │ assertion in update(address,bytes32,uint32[],(uint32,uint96)[],uint32,uint256): PASSED!                              │
                                                          │                                                                                                                      │
                                                          ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
                                                          │                                        Campaign complete, C-c or esc to exit                                         │
                                                          └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```
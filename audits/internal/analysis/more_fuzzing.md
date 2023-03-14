```sh
echidna-test contracts/flatten/AgentRegistry-flatten.sol --contract AgentRegistryProxy --config echidna.yaml                                                                                                                                                                                   
                                                         
                                                          ┌─────────────────────────────────────────────────────Echidna 2.0.5────────────────────────────────────────────────────┐                                                          
                                                          │ Tests found: 1                                                                                                       │                                                          
                                                          │ Seed: -1325617478790951267                                                                                           │                                                          
                                                          │ Unique instructions: 1947                                                                                            │                                                          
                                                          │ Unique codehashes: 2                                                                                                 │                                                          
                                                          │ Corpus size: 2                                                                                                       │                                                          
                                                          │─────────────────────────────────────────────────────────Tests────────────────────────────────────────────────────────│                                                          
                                                          │ Integer (over/under)flow: PASSED!                                                                                    │                                                          
                                                          └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  

echidna-test contracts/flatten/AgentRegistry-flatten.sol --contract AgentRegistryProxy --config echidna.yaml 
                                                          ┌─────────────────────────────────────────────────────Echidna 2.0.5────────────────────────────────────────────────────┐                                                          
                                                          │ Tests found: 4                                                                                                       │                                                          
                                                          │ Seed: 2056738752459694098                                                                                            │                                                          
                                                          │ Unique instructions: 1947                                                                                            │                                                          
                                                          │ Unique codehashes: 2                                                                                                 │                                                          
                                                          │ Corpus size: 1                                                                                                       │                                                          
                                                          │─────────────────────────────────────────────────────────Tests────────────────────────────────────────────────────────│                                                          
                                                          │ AssertionFailed(..): PASSED!                                                                                         │                                                          
                                                          │──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────│                                                          
                                                          │ assertion in iComponentRegistryFF(): PASSED!                                                                         │                                                          
                                                          │──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────│                                                          
                                                          │ assertion in iAgentRegistryF(): PASSED!                                                                              │                                                          
                                                          │──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────│                                                          
                                                          │ assertion in calculateSubComponents(uint32[]): PASSED!                                                               │                                                          
                                                          └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘                                                          
                                                                                                   Campaign complete, C-c or esc to exit                                                                                                    

                                                                                                                                                                                    
```

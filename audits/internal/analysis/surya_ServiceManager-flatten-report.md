## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| ServiceManager-flatten.sol | 3e6bf46b728b243fe094ebf2bf7466ca0ec2345a |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **IErrorsRegistries** | Interface |  |||
||||||
| **GenericManager** | Implementation | IErrorsRegistries |||
| └ | changeOwner | External ❗️ | 🛑  |NO❗️ |
| └ | pause | External ❗️ | 🛑  |NO❗️ |
| └ | unpause | External ❗️ | 🛑  |NO❗️ |
||||||
| **IService** | Interface |  |||
| └ | create | External ❗️ | 🛑  |NO❗️ |
| └ | update | External ❗️ | 🛑  |NO❗️ |
| └ | activateRegistration | External ❗️ |  💵 |NO❗️ |
| └ | registerAgents | External ❗️ |  💵 |NO❗️ |
| └ | deploy | External ❗️ | 🛑  |NO❗️ |
| └ | terminate | External ❗️ | 🛑  |NO❗️ |
| └ | unbond | External ❗️ | 🛑  |NO❗️ |
| └ | destroy | External ❗️ | 🛑  |NO❗️ |
| └ | exists | External ❗️ |   |NO❗️ |
| └ | getServiceIdsCreatedWithAgentId | External ❗️ |   |NO❗️ |
| └ | getServiceIdsCreatedWithComponentId | External ❗️ |   |NO❗️ |
| └ | getAgentIdsOfServiceId | External ❗️ |   |NO❗️ |
| └ | getComponentIdsOfServiceId | External ❗️ |   |NO❗️ |
||||||
| **IReward** | Interface |  |||
| └ | depositETHFromServices | External ❗️ |  💵 |NO❗️ |
||||||
| **ServiceManager** | Implementation | GenericManager |||
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | <Fallback> | External ❗️ |  💵 |NO❗️ |
| └ | <Receive Ether> | External ❗️ |  💵 |NO❗️ |
| └ | changeTreasury | External ❗️ | 🛑  |NO❗️ |
| └ | serviceCreate | External ❗️ | 🛑  |NO❗️ |
| └ | serviceUpdate | External ❗️ | 🛑  |NO❗️ |
| └ | serviceActivateRegistration | External ❗️ |  💵 |NO❗️ |
| └ | serviceRegisterAgents | External ❗️ |  💵 |NO❗️ |
| └ | serviceDeploy | External ❗️ | 🛑  |NO❗️ |
| └ | serviceTerminate | External ❗️ | 🛑  |NO❗️ |
| └ | serviceUnbond | External ❗️ | 🛑  |NO❗️ |
| └ | serviceDestroy | External ❗️ | 🛑  |NO❗️ |
| └ | serviceReward | External ❗️ |  💵 |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |

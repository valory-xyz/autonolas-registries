## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| RegistriesManager-flatten.sol | f6c0e3b066972f24dabdd906ef5d2be908010761 |


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
| **IRegistry** | Interface |  |||
| └ | create | External ❗️ | 🛑  |NO❗️ |
| └ | updateHash | External ❗️ | 🛑  |NO❗️ |
| └ | exists | External ❗️ |   |NO❗️ |
| └ | getInfo | External ❗️ |   |NO❗️ |
| └ | getDependencies | External ❗️ |   |NO❗️ |
| └ | getLocalSubComponents | External ❗️ |   |NO❗️ |
| └ | getSubComponents | External ❗️ |   |NO❗️ |
| └ | getUpdatedHashes | External ❗️ |   |NO❗️ |
| └ | totalSupply | External ❗️ |   |NO❗️ |
| └ | tokenByIndex | External ❗️ |   |NO❗️ |
||||||
| **RegistriesManager** | Implementation | GenericManager |||
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | createAgent | External ❗️ | 🛑  |NO❗️ |
| └ | updateAgentHash | External ❗️ | 🛑  |NO❗️ |
| └ | createComponent | External ❗️ | 🛑  |NO❗️ |
| └ | updateComponentHash | External ❗️ | 🛑  |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |

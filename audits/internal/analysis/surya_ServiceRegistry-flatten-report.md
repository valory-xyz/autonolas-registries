## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| ServiceRegistry-flatten.sol | 7908f8fc03bf9ae4632f37d408eb31102ca6dad5 |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **ERC721** | Implementation |  |||
| └ | tokenURI | Public ❗️ |   |NO❗️ |
| └ | ownerOf | Public ❗️ |   |NO❗️ |
| └ | balanceOf | Public ❗️ |   |NO❗️ |
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | approve | Public ❗️ | 🛑  |NO❗️ |
| └ | setApprovalForAll | Public ❗️ | 🛑  |NO❗️ |
| └ | transferFrom | Public ❗️ | 🛑  |NO❗️ |
| └ | safeTransferFrom | Public ❗️ | 🛑  |NO❗️ |
| └ | safeTransferFrom | Public ❗️ | 🛑  |NO❗️ |
| └ | supportsInterface | Public ❗️ |   |NO❗️ |
| └ | _mint | Internal 🔒 | 🛑  | |
| └ | _burn | Internal 🔒 | 🛑  | |
| └ | _safeMint | Internal 🔒 | 🛑  | |
| └ | _safeMint | Internal 🔒 | 🛑  | |
||||||
| **ERC721TokenReceiver** | Implementation |  |||
| └ | onERC721Received | External ❗️ | 🛑  |NO❗️ |
||||||
| **LibString** | Library |  |||
| └ | toString | Internal 🔒 |   | |
||||||
| **IErrorsRegistries** | Interface |  |||
||||||
| **GenericRegistry** | Implementation | IErrorsRegistries, ERC721 |||
| └ | changeOwner | External ❗️ | 🛑  |NO❗️ |
| └ | changeManager | External ❗️ | 🛑  |NO❗️ |
| └ | exists | External ❗️ |   |NO❗️ |
| └ | tokenURI | Public ❗️ |   |NO❗️ |
| └ | setBaseURI | External ❗️ | 🛑  |NO❗️ |
| └ | tokenByIndex | External ❗️ |   |NO❗️ |
||||||
| **IMultisig** | Interface |  |||
| └ | create | External ❗️ | 🛑  |NO❗️ |
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
| **ServiceRegistry** | Implementation | GenericRegistry |||
| └ | <Constructor> | Public ❗️ | 🛑  | ERC721 |
| └ | <Fallback> | External ❗️ |  💵 |NO❗️ |
| └ | <Receive Ether> | External ❗️ |  💵 |NO❗️ |
| └ | _initialChecks | Private 🔐 |   | |
| └ | _setServiceData | Private 🔐 | 🛑  | |
| └ | create | External ❗️ | 🛑  |NO❗️ |
| └ | update | External ❗️ | 🛑  | onlyServiceOwner |
| └ | activateRegistration | External ❗️ |  💵 | onlyServiceOwner |
| └ | registerAgents | External ❗️ |  💵 |NO❗️ |
| └ | deploy | External ❗️ | 🛑  | onlyServiceOwner |
| └ | slash | External ❗️ | 🛑  | serviceExists |
| └ | terminate | External ❗️ | 🛑  | onlyServiceOwner |
| └ | unbond | External ❗️ | 🛑  |NO❗️ |
| └ | _getAgentInstances | Private 🔐 |   | |
| └ | getServiceInfo | External ❗️ |   | serviceExists |
| └ | getInstancesForAgentId | External ❗️ |   | serviceExists |
| └ | getPreviousHashes | External ❗️ |   | serviceExists |
| └ | getAgentIdsOfServiceId | External ❗️ |   |NO❗️ |
| └ | getComponentIdsOfServiceId | External ❗️ |   |NO❗️ |
| └ | getServiceState | External ❗️ |   |NO❗️ |
| └ | getOperatorBalance | External ❗️ |   | serviceExists |
| └ | changeMultisigPermission | External ❗️ | 🛑  |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |

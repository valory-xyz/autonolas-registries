## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| AgentRegistry-flatten.sol | 4d3dac41d68ad97a3ba03d8d7aeea6f0a9e7ca9e |


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
| **UnitRegistry** | Implementation | GenericRegistry |||
| └ | _checkDependencies | Internal 🔒 | 🛑  | |
| └ | create | External ❗️ | 🛑  |NO❗️ |
| └ | updateHash | External ❗️ | 🛑  |NO❗️ |
| └ | getInfo | External ❗️ |   |NO❗️ |
| └ | getDependencies | External ❗️ |   |NO❗️ |
| └ | getUpdatedHashes | External ❗️ |   |NO❗️ |
| └ | _getSubComponents | Internal 🔒 |   | |
| └ | getSubComponents | Public ❗️ |   |NO❗️ |
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
| **AgentRegistry** | Implementation | UnitRegistry |||
| └ | <Constructor> | Public ❗️ | 🛑  | ERC721 |
| └ | _checkDependencies | Internal 🔒 | 🛑  | |
| └ | _getSubComponents | Internal 🔒 |   | |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |

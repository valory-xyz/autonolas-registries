## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| UnitRegistry-flatten.sol | 9be39477019812c049107eb9ca20a04981cd9b2f |


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


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |

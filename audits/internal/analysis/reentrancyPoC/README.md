PoC reentrancy attack
ref: Reentrancy in ServiceRegistry.create(address,bytes32,bytes32,bytes32,uint32[],AgentParams[],uint32) (contracts/ServiceRegistry.sol#236-291):

```
npx hardhat test

Compiled 17 Solidity files successfully

  ServiceRegistry
    Service creation
ReentrancyAttacker before create()
ServiceRegistry [create] serviceOwner 0x0165878a594ca255338adfa4d48449f69242eb8f
ServiceRegistry [create] serviceId 1
ReentrancyAttacker call onERC721Received()
serviceOwner: 0x0165878a594ca255338adfa4d48449f69242eb8f
ServiceRegistry [create] serviceOwner 0x0165878a594ca255338adfa4d48449f69242eb8f
ServiceRegistry [create] serviceId 1

      1) Catching Reentrancy attack to create a service

·---------------------------------------|---------------------------|--------------|-----------------------------·
|         Solc version: 0.8.15          ·  Optimizer enabled: true  ·  Runs: 1000  ·  Block limit: 30000000 gas  │
········································|···························|··············|······························
|  Methods                                                                                                       │
······················|·················|·············|·············|··············|···············|··············
|  Contract           ·  Method         ·  Min        ·  Max        ·  Avg         ·  # calls      ·  eur (avg)  │
······················|·················|·············|·············|··············|···············|··············
|  AgentRegistry      ·  changeManager  ·          -  ·          -  ·       47262  ·            1  ·          -  │
······················|·················|·············|·············|··············|···············|··············
|  AgentRegistry      ·  create         ·     245745  ·     279945  ·      262845  ·            2  ·          -  │
······················|·················|·············|·············|··············|···············|··············
|  ComponentRegistry  ·  changeManager  ·          -  ·          -  ·       47284  ·            1  ·          -  │
······················|·················|·············|·············|··············|···············|··············
|  ComponentRegistry  ·  create         ·          -  ·          -  ·      218785  ·            1  ·          -  │
······················|·················|·············|·············|··············|···············|··············
|  ServiceRegistry    ·  changeManager  ·          -  ·          -  ·       47322  ·            1  ·          -  │
······················|·················|·············|·············|··············|···············|··············
|  Deployments                          ·                                          ·  % of limit   ·             │
········································|·············|·············|··············|···············|··············
|  AgentRegistry                        ·          -  ·          -  ·     2622495  ·        8.7 %  ·          -  │
········································|·············|·············|··············|···············|··············
|  ComponentRegistry                    ·          -  ·          -  ·     2549522  ·        8.5 %  ·          -  │
········································|·············|·············|··············|···············|··············
|  GnosisSafeL2                         ·          -  ·          -  ·     3042865  ·       10.1 %  ·          -  │
········································|·············|·············|··············|···············|··············
|  GnosisSafeMultisig                   ·          -  ·          -  ·      385244  ·        1.3 %  ·          -  │
········································|·············|·············|··············|···············|··············
|  GnosisSafeProxyFactory               ·          -  ·          -  ·      641133  ·        2.1 %  ·          -  │
········································|·············|·············|··············|···············|··············
|  ReentrancyAttacker                   ·          -  ·          -  ·      842758  ·        2.8 %  ·          -  │
········································|·············|·············|··············|···············|··············
|  ServiceRegistry                      ·          -  ·          -  ·     5484184  ·       18.3 %  ·          -  │
·---------------------------------------|-------------|-------------|--------------|---------------|-------------·

  0 passing (2s)
  1 failing

  1) ServiceRegistry
       Service creation
         Catching Reentrancy attack to create a service:
     Error: VM Exception while processing transaction: reverted with reason string 'ALREADY_MINTED'
      at ServiceRegistry.approve (lib/solmate/src/tokens/ERC721.sol:69)
      at ServiceRegistry._safeMint (lib/solmate/src/tokens/ERC721.sol:194)
      at ServiceRegistry.create (contracts/ServiceRegistry.sol:281)
      at ReentrancyAttacker.onERC721Received (contracts/test/ReentrancyAttacker.sol:83)
      at ServiceRegistry._safeMint (lib/solmate/src/tokens/ERC721.sol:198)
      at ServiceRegistry.create (contracts/ServiceRegistry.sol:281)
      at ReentrancyAttacker.create (contracts/test/ReentrancyAttacker.sol:75)
      at HardhatNode._mineBlockWithPendingTxs (node_modules/hardhat/src/internal/hardhat-network/provider/node.ts:1773:23)
      at HardhatNode.mineBlock (node_modules/hardhat/src/internal/hardhat-network/provider/node.ts:466:16)
      at EthModule._sendTransactionAndReturnHash (node_modules/hardhat/src/internal/hardhat-network/provider/modules/eth.ts:1504:18)
      at HardhatNetworkProvider.request (node_modules/hardhat/src/internal/hardhat-network/provider/provider.ts:118:18)
      at EthersProviderWrapper.send (node_modules/@nomiclabs/hardhat-ethers/src/internal/ethers-provider-wrapper.ts:13:20)

```

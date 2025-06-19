graph TD
  %% Agent/Component/Service
  ServiceRegistry[Service Registry]
  ServiceManagerToken[Service Manager Token]
  OperatorSignedHashes[Operator Signed Hashes]
  OperatorWhitelist[Operator Whitelist]
  GenericManager[Generic Manager]
  AgentRegistry[Agent Registry]
  ComponentRegistry[Component Registry]
  UnitRegistry[Unit Registry]
  GenericRegistry[Generic Registry]
  GenericAgentMultisig[Generic Agent Multisig]
  RegistriesManager[Registries Manager]
  Operator[Operator]
  Owner[Owner]
  ServiceOwner[Service Owner]
  ServiceStaking[Service Staking Native Token]
  ServiceStakingToken[Service Registry Token Utility]
  Timelock[Timelock]

  Owner -->|create, UpdateHash| RegistriesManager
  RegistriesManager -->|create, UpdateHash| AgentRegistry
  RegistriesManager -->|create, UpdateHash| ComponentRegistry
  ComponentRegistry -.->|create, UpdateHash| UnitRegistry
  UnitRegistry -.->|_safeMint, create, UpdateHash| GenericRegistry
  GenericRegistry -.->|_safeMint|ERC721
  ServiceOwner -->|setOperatorsCheck|OperatorWhitelist
  OperatorWhitelist-->|ownerOf|ServiceRegistry
  GenericAgentMultisig-->|slash|ServiceRegistry
  ServiceRegistry-->|create|GenericAgentMultisig
  ServiceStaking-->|mapServiceIdTokenDeposit|ServiceStakingToken
  ServiceStaking-->|getService|ServiceRegistry
  ServiceRegistry-.->|_safeMint,burn|ERC721
  ServiceManagerToken-->|createWithToken|ServiceStakingToken
  ServiceManagerToken-->|activateRegistration, registerAgents|ServiceRegistry
  ServiceManagerToken-->|create, update, terminate, deploy, unbond|ServiceRegistry
  ServiceManagerToken-->|isOperatorWhitelisted|OperatorWhitelist
  ServiceManagerToken-.->|verifySignedHash|OperatorSignedHashes
  Owner-->|create, update, deploy, terminate, unbond|ServiceManagerToken
  Owner-->|activateRegistration|ServiceManagerToken
  Operator-->|registerAgents|ServiceManagerToken
  Operator-->|getRegisterAgentsHash|OperatorSignedHashes
  Timelock-->|ownership|GenericManager
  ServiceManagerToken-->GenericManager


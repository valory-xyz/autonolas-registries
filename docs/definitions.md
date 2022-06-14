## Definitions and data structures
- [`Multihash`](https://multiformats.io/multihash/): a self-describing hash, a protocol for differentiating outputs
from various well-established hash functions. Multihash is a hashing standard for [`IPFS`](https://docs.ipfs.io/concepts/what-is-ipfs/),
a distributed system for storing and accessing files, websites, applications, and data. Please note that IPSF uses the
`sha2-256 - 256 bits` as their hashing function. From the definition, `sha2-256` has a `0x12` code in hex, and its
length is 32, or `0x20` in hex. This means that each IPFS link starts with `1220` value in hash, and the link itself
can perfectly fit the `bytes32` data structure. Note that if the IPFS hashing changes, the size of Multihash data
structure needs to be updated, although old links would still work (as per IPFS standard).
- `Agent Component`: a piece of code + configuration in the agent. In the context of the [`open-aea`](https://github.com/valory-xyz/open-aea)
framework, it is a skill, connection, protocol or contract. Each component is identified by its IPFS hash.
- `Canonical Agent`: a configuration and optionally code making up the agent. In the context of the [`open-aea`](https://github.com/valory-xyz/open-aea)
framework, this is the agent config file which points to various agent components. The agent code and config are
identified by its IPFS hash.
- `Agent Instance`: an instance of a canonical agent. Each agent instance must have, at a minimum, a single
cryptographic key-pair, whose address identifies the agent.
- `Operator`: an individual operating an agent instance (or multiple). The operator must have, at a minimum, a single 
cryptographic key-pair whose address identifies the operator. This key-pair MUST be different from the ones used
by the agent.
- `Service`: defines a set (or singleton) of canonical agents (and therefore components), a set of service extension
contracts, a number of agents instances per canonical agents.

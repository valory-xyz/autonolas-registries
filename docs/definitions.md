## Definitions and data structures
- [`Multihash`](https://multiformats.io/multihash/): a self-describing hash, a protocol for differentiating outputs
from various well-established hash functions. Multihash is a hashing standard for [`IPFS`](https://docs.ipfs.io/concepts/what-is-ipfs/),
a distributed system for storing and accessing files, websites, applications, and data. As stated in the original IPFS [`documentation`](https://docs.ipfs.io/concepts/content-addressing/),
the CID v1 is the preferred multibase encoding. 

To better understand the CID anatomy, please refer to the [CID Anatomy](https://proto.school/anatomy-of-a-cid).

Please note that the default CID v1 of is built with the `sha2-256 - 256 bits` as their hashing function and a `base32` multibase prefix. Also, the default multicodec for the CID v1 is `raw`.

In order to supply `autonolas-registries` with the multihash content address part of the IPFS hash and support backward compatibility with CID v0 IPFS hashes,
please create your hashes with a `dag-pb` multicodec and a `base16` multibase prefix.
One can easily convert already existent v1 (or v0) CID of matching codec into the `base16` variant with the following command:
```ipfs cid format -v 1 -b base16 your_ipfs_hash```

The hash then would look like this:
```f01701220c4cd970d30af2ca0257ef8e4c613a399368ba13eb0a3ee4b4c15c105cd2c9a35```,
where `f` corresponds to the `base16` multibase prefix. The rest of the hash is read as bytes in the following manner:
`0x01` corresponds to the CID v1, `0x70` corresponds to the `dag-pb` multicodec, `0x12` is `sha2-256` hashing function, and `0x20` (32 in decimal or 256 bits) is the length of the content address.
Since auotonolas-registries assumes its users follow the requirements of using the CID v1 IPFS hash creation with a `dag-pb` multicodec and a `base16` multibase prefix,
it consumes only the multihash content address of 32 bytes in a `bytes32` variable. In the example above, this value would be as follows:
```0xc4cd970d30af2ca0257ef8e4c613a399368ba13eb0a3ee4b4c15c105cd2c9a35```.

A hash passed during the unit creation contains a link to the `JSON` metadata with all the relevant unit information.
In order to support the optimistic design of component / agent / service hash updates, all the units have the functionality of updating a hash.
Previously used hashes are then moved to the correspondent historical set of hashes. Note that updated hashes are not checked for duplicates, since
it would be relatively easy to simulate a different hash by a single character of metadata modification. Thus, this verification is somewhat redundant
and allows to save on gas cost.

- `Agent Component` or simply `Component`: a piece of code + configuration in the agent. In the context of the [`open-aea`](https://github.com/valory-xyz/open-aea)
framework, it is a skill, connection, protocol or contract. Each component is identified by its IPFS hash.
- `Canonical Agent` or simply `Agent`: a configuration and optionally code making up the agent. In the context of the [`open-aea`](https://github.com/valory-xyz/open-aea)
framework, this is the agent config file which points to various agent components. The agent code and config are
identified by its IPFS hash.
- `Agent Instance`: an instance of a canonical agent. Each agent instance must have, at a minimum, a single
cryptographic key-pair, whose address identifies the agent.
- `Operator`: an individual operating an agent instance (or multiple). The operator must have, at a minimum, a single 
cryptographic key-pair whose address identifies the operator. This key-pair MUST be different from the ones used
by the agent.
- `Service`: defines a set (or singleton) of canonical agents (and therefore components), a set of service extension
contracts, a number of agents instances per canonical agents, and a number of operator slots.

# Blockscout browser verification — Robinhood Chain (4663)

For each contract open:

    https://robinhoodchain.blockscout.com/address/<ADDRESS>/contract-verification

and choose **Solidity (Standard JSON input)**. Then:

| field | value |
|---|---|
| Compiler | see per-contract table below (they are not all the same) |
| Standard JSON | upload `<Name>.standard-input.json` from this directory |
| License | MIT |
| Constructor args | paste from `<Name>.constructor-args.txt`, or tick auto-detect |

Contracts with an empty `constructor-args.txt` take no constructor arguments.

| # | contract | address | compiler | ctor args |
|---|---|---|---|---|
| 1 | `ServiceRegistryL2` | `0xE3607b00E75f6405248323A9417ff6b39B244b50` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 2 | `OperatorWhitelist` | `0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 3 | `ServiceRegistryTokenUtility` | `0x3d77596beb0f130a4415df3D2D8232B3d3D31e44` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 4 | `ServiceManager` | `0x34C895f302D0b5cf52ec0Edd3945321EB0f83dd5` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 5 | `ServiceManagerProxy` | `0x63e66d7ad413C01A7b49C7FF4e3Bb765C4E4bd1b` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 6 | `GnosisSafeMultisig` | `0xBb7e1D6Cb6F243D6bdE81CE92a9f2aFF7Fbe7eac` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 7 | `GnosisSafeSameAddressMultisig` | `0xFbBEc0C8b13B38a9aC0499694A69a10204c5E2aB` | `v0.8.30+commit.73712a01` | 0xb89c1b3bdf2cf8827818… |
| 8 | `RecoveryModule` | `0xE43d4F4103b623B61E095E8bEA34e1bc8979e168` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 9 | `SafeMultisigWithRecoveryModule` | `0xb09CcF0Dbf0C178806Aaee28956c74bd66d21f73` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 10 | `ComplementaryServiceMetadata` | `0xD1155408D58293BE0743225bcDe28b9FD0C12378` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 11 | `IdentityRegistryBridger` | `0x397125902ED2cA2d42104F621f448A2cE1bC8Fb7` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 12 | `IdentityRegistryBridgerProxy` | `0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 13 | `StakingToken` | `0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c` | `v0.8.28+commit.7893614a` | none |
| 14 | `StakingVerifier` | `0x75D529FAe220bC8db714F0202193726b46881B76` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |
| 15 | `StakingFactory` | `0x1BD1505B711Fb58C54ca3712e6BEf47A133892d9` | `v0.8.30+commit.73712a01` | 0x00000000000000000000… |

## Note on StakingToken

`StakingToken` is the only contract on **v0.8.28** — it is pinned to 0.2.0 to match the rest of the
fleet, while every other contract here is built from `main` on 0.8.30. Selecting 0.8.30 for it will
fail to match. Its `evmVersion` is `cancun`; the others are `prague`. Both are carried inside the
standard-JSON, so the upload is authoritative — but the compiler dropdown is chosen by hand and is
the easy thing to get wrong.


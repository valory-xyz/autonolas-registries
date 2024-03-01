# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org).

[1.1.10]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.9...v1.1.10
[1.1.9]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.8...v1.1.9
[1.1.8]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.7...v1.1.8
[1.1.7]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.6...v1.1.7
[1.1.6]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.4...v1.1.6
[1.1.5]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.4...v1.1.5
[1.1.4]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/valory-xyz/autonolas-registries/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/valory-xyz/autonolas-registries/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/valory-xyz/autonolas-registries/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/valory-xyz/autonolas-registries/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/valory-xyz/autonolas-registries/releases/tag/v1.0.0


## [1.1.10] - 2024-03-01

_No bytecode changes_.

### Changed

- Deployed `SeviceRegistryL2`, `ServiceRegistryTokenUtility`, `ServiceManagerToken`, `OperatorWhitelist`, `GnosisSafeMultisig`, `GnosisSafeSameAddressMultisig` contracts on Optimism, Base, Celo ([#155](https://github.com/valory-xyz/autonolas-registries/pull/155))

## [1.1.9] - 2024-01-29

_No bytecode changes_.

### Changed

- Deployed `SeviceRegistryL2`, `ServiceRegistryTokenUtility`, `ServiceManagerToken`, `OperatorWhitelist`, `GnosisSafeMultisig`, `GnosisSafeSameAddressMultisig` contracts on Arbitrum ([#148](https://github.com/valory-xyz/autonolas-registries/pull/148))
- Deployed `ServiceRegistryTokenUtility`, `ServiceManagerToken` and `OperatorWhitelist` contracts on Polyon ([#145](https://github.com/valory-xyz/autonolas-registries/pull/148))

## [1.1.8] - 2024-01-23

### Changed

- Refactored `ServiceStakingBase.sol` for service staking ([#141](https://github.com/valory-xyz/autonolas-registries/pull/141)) with the subsequent internal audit ([#143](https://github.com/valory-xyz/autonolas-registries/pull/143)) 
- Refactored `ServiceStakingBase.sol` for internal audit reaction ([#146](https://github.com/valory-xyz/autonolas-registries/pull/146)) 
- Updated documentation

## [1.1.7] - 2023-11-24
- Created `ServiceStakingBase.sol` , `ServiceStakingNativeToken.sol`, `ServiceStakingToken.sol` for service staking. The latest internal audits with a focus on the above contracts is located in ([audit4](https://github.com/valory-xyz/autonolas-registries/tree/main/audits/internal4)) 
- Refactored and redeployed `GnosisSafeSameAddressMultisig` contract for checking multisig proxy bytecode hashes ([#126](https://github.com/valory-xyz/autonolas-registries/pull/126))
- Updated documentation
- Added tests

## [1.1.6] - 2023-09-22

_No bytecode changes_.

### Changed

- Deployed `ServiceRegistryTokenUtility`, `ServiceManagerToken` and `OperatorWhitelist` contracts on gnosis ([#117](https://github.com/valory-xyz/autonolas-registries/pull/117))
- Added the chaind audit script to check throughout all the deployed contracts and configuration on corresponding chains ([#109](https://github.com/valory-xyz/autonolas-registries/pull/109))
- Updated documentation
- Added tests

## [1.1.5] - 2023-10-04

_No bytecode changes_.

### Changed

- Latest external audit of registries contracts.

## [1.1.4] - 2023-08-08

_No bytecode changes_.

### Changed

- Updating Solana scripts
- Updating default deployment script for the CLI utilization

## [1.1.3] - 2023-06-30

### Changed

- Created and deployed `ServiceRegistrySolana` program - the implementation of a service registry concept on Solana network ([#101](https://github.com/valory-xyz/autonolas-registries/pull/101))
  with the subsequent internal audit ([audit3](https://github.com/valory-xyz/autonolas-registries/tree/main/audits/internal3))
- Updated documentation
- Added tests

## [1.1.2] - 2023-05-10

_No bytecode changes_.

### Changed

- L2 protocol deployment with `ServiceRegistryL2` contract on Polygon and Gnosis chains ([#95](https://github.com/valory-xyz/autonolas-registries/pull/95))
- Added tests

## [1.1.1] - 2023-05-09

### Changed

- Updated `ServiceManagerToken` contract based on the `OperatorSignedHashes` one such that operators are able to register agent instances and unbond via signatures ([#83](https://github.com/valory-xyz/autonolas-registries/pull/83))
  with the subsequent internal audit ([audit3](https://github.com/valory-xyz/autonolas-registries/tree/main/audits/internal3))
- Deployed `ServiceRegistryTokenUtility`, `ServiceManagerToken` and `OperatorWhitelist` contracts
- Updated documentation
- Added tests

## [1.1.0] - 2023-04-28

### Changed

- Created `ServiceRegistryTokenUtility`, `ServiceManagerToken` and `OperatorWhitelist` contracts ([#73](https://github.com/valory-xyz/autonolas-registries/pull/73))
  that allow register services with an ERC20 token security and whitelist operators that are authorized to register agent instances.
- Performed the internal audit([audit2](https://github.com/valory-xyz/autonolas-registries/tree/main/audits/internal2))
- Updated documentation
- Added tests
- Added known vulnerabilities

## [1.0.3] - 2023-04-21

### Changed

- Updated `ServiceRegistryL2` contract that represents the service functionalities on L2 ([#67](https://github.com/valory-xyz/autonolas-registries/pull/67))
- Updated documentation
- Added tests
- Added known vulnerabilities

## [1.0.2] - 2023-01-24

_No bytecode changes_.

### Changed

- Updated documentation
- Account for deployment of contracts via CLI

## [1.0.1] - 2022-12-09

### Changed

- Updated and deployed `GnosisSafeMultisig` contract ([#37](https://github.com/valory-xyz/autonolas-registries/pull/37))
- Created and deployed `GnosisSafeSameAddressMultisig` contract ([#40](https://github.com/valory-xyz/autonolas-registries/pull/40))
- Created `ServiceRegistryL2` contract that represents the service functionalities on L2 ([#41](https://github.com/valory-xyz/autonolas-registries/pull/41))
- Updated documentation
- Added more tests
- Addressed known vulnerabilities

## [1.0.0] - 2022-07-20

### Added

- Initial release
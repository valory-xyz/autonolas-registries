# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org).

[1.1.4]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/valory-xyz/autonolas-registries/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/valory-xyz/autonolas-registries/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/valory-xyz/autonolas-registries/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/valory-xyz/autonolas-registries/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/valory-xyz/autonolas-registries/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/valory-xyz/autonolas-registries/releases/tag/v1.0.0

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
- Updated and deployed `GnosisSafeSameAddressMultisig` contract ([#40](https://github.com/valory-xyz/autonolas-registries/pull/40))
- Created `ServiceRegistryL2` contract that represents the service functionalities on L2 ([#41](https://github.com/valory-xyz/autonolas-registries/pull/41))
- Updated documentation
- Added more tests
- Addressed known vulnerabilities

## [1.0.0] - 2022-07-20

### Added

- Initial release
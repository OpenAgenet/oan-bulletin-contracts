# OAN Bulletin Contracts

Blockchain bulletin contracts for OpenAgenet (OAN), an open infrastructure
project for the Internet of Agents (IoA).

This repository contains the on-chain governance contract implementations and
related development packages used to publish OAN bulletin state. The bulletin
provides a blockchain-backed governance source for infrastructure
authorization, network participation, and other OAN governance decisions.

OAN is designed to support multiple blockchain environments. Each chain
adapter is kept in its own directory so that chain-specific languages,
deployment tools, package formats, and operational procedures do not leak into
the other implementations.

## Contract Implementations

- `Sui/`: Sui Move bulletin contract package.
- `Ethereum/`: Solidity implementation for Ethereum-compatible networks.
- `Astron/javascript/`: Astron/Xinghuo BIF V8 JavaScript implementation.
- `Astron/solidity/`: Astron Solidity adapter for the shared Solidity
  governance implementation. It must be compiled with the Astron platform
  compiler for production use.
- `chaincode-js/`: Hyperledger Fabric JavaScript chaincode implementation.

The Sui package is the currently used OAN contract. The other projects are
cross-platform implementations of the same governance model and currently
serve as compatibility references. They include basic local tests but no
deployment automation or integration with other OAN modules.

See [`SEMANTIC-PARITY.md`](SEMANTIC-PARITY.md) for the shared behavior and the
intentional platform-specific adaptations.

## Repository Boundaries

This repository owns blockchain contract code and chain-specific deployment
artifacts. It does not own:

- Root, Registrar, Discovery, CDN, or Trust Indexer services;
- SDK or website application code;
- private governance keys or service-node identity material;
- production deployment secrets.

The OAN Trust Indexer and OAN service nodes consume the resulting governance
state through their own integration layers. Contract changes must preserve the
documented bulletin event and governance-state contracts used by those
consumers.

## Sui Development

The current Sui package is located at:

```text
Sui/move-package
```

From that directory, use the Sui toolchain to build and test the package:

```powershell
cd Sui/move-package
sui move build
sui move test
```

Generated Move build output is ignored by the repository-level `.gitignore`.
Network deployment configuration and published package records must be handled
according to the target environment and must not contain private keys.

## Contribution Guidelines

Contract changes should include:

- Move unit tests or equivalent chain-specific tests;
- event and governance-state compatibility review;
- upgrade and migration notes when published package behavior changes;
- updates to the corresponding chain directory documentation.

All contract source files must retain the copyright header used by the Sui
implementation.

Keep chain-specific code inside its chain directory. Shared governance
semantics should be documented explicitly before introducing cross-chain
abstractions.

## License

This repository is licensed under `Apache-2.0`. Brand and official OpenAgenet
(OAN) identity rights are reserved separately.

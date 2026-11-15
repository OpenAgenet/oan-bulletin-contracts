# OAN Bulletin Semantic Parity

`Sui/move-package/sources/bulletin.move` is the behavioral reference for all
other implementations in this repository. Platform documentation is used only
to adapt storage, identity, time, hashing, events, and lifecycle mechanics.

## Shared governance behavior

All implementations provide:

- meta-admin and admin committees with active, disabled, and removed members;
- two-thirds-plus-one meta-admin voting and configurable admin voting;
- proposal-time threshold snapshots;
- bounded pending proposals and bounded retained proposal history;
- passed, expired, rejected, and still-pending proposal outcomes;
- Registrar, Discovery, and VC Issuer authorization lifecycles;
- canonical, sorted, unique authorized-domain validation;
- effective/expiry time checks and point-in-time authorization queries;
- root-authority DID rotation by the meta-admin committee;
- chained governance execution event digests;
- stale approved proposal rejection when its state transition is no longer
  valid.

The numeric committee, action, member, subject, and proposal status values are
kept aligned with the Sui implementation.

## Intentional platform adaptations

| Concern | Sui | Ethereum / Astron Solidity | Astron JSVM | Fabric chaincode |
| --- | --- | --- | --- | --- |
| Identity | Sui address | Solidity `address`; Astron compiler supplies BID address semantics | BID string validated by `Utils.addressCheck` | Fabric client identity string |
| Time | Sui Clock milliseconds | `block.timestamp * 1000` | seconds/ms/microseconds normalized to ms | transaction timestamp converted to ms |
| Event payload | typed Move event | indexed selectors plus ABI payload | `tlog` summary plus stored full event | Fabric event JSON |
| Digest encoding | BCS + SHA3-256 | ABI + Keccak-256 | canonical generated JSON + SHA-256 | canonical generated JSON + SHA3-256 |
| Initialization | package publisher and upgrade capability | constructor | JSVM `init` | one-time world-state initialization |
| Upgrade lifecycle | Sui `UpgradeCap` | selected proxy policy is deployment-specific | platform contract lifecycle | Fabric chaincode lifecycle |

Digest values are deliberately chain-specific; continuity and payload binding
are preserved, but digest bytes are not expected to match across platforms.

## Validation boundary

The repository contains local unit/compile tests only. It does not contain
deployment automation or integration tests with other OAN modules. Astron
Solidity is compiled locally with the official `solc-bif` package, but it must
still be tested against the exact target BIF-Core release before production
use.

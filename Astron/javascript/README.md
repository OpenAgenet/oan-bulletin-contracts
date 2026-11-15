# OAN Bulletin for Astron JSVM

This project ports the governance semantics of `Sui/move-package` to the
Astron/Xinghuo BIF V8 JavaScript contract model. It uses the documented
`init`, `main`, and `query` entry points, `Chain.store/load`,
`Chain.msg.sender`, `Chain.block.timestamp`, `Chain.tlog`, and
`Utils.sha256`.

State is split across metadata keys so proposals and subjects do not force one
ever-growing value toward the platform's per-value storage limit. The event
digest uses SHA-256 over canonical contract-generated JSON and is therefore not
byte-identical to the Sui BCS/SHA3-256 digest.

```powershell
npm test
```

The tests use a local JSVM API harness. No deployment scripts or integrations
with other OAN modules are included. The contract deterministically normalizes
realistic second-, millisecond-, or microsecond-based block timestamps to the
millisecond interface used by the Sui implementation.

# OAN Bulletin for Ethereum

This project ports the governance semantics of `Sui/move-package` to an
Ethereum-compatible contract. It is a source and unit-test project only; it
contains no deployment scripts and no integration with other OAN modules.

The implementation preserves the two committees, proposal threshold snapshot,
member lifecycle, subject authorization lifecycle, canonical domain rules,
proposal expiry, and chained governance execution events. Event digests use
Solidity ABI encoding and therefore are not byte-identical to Sui BCS digests.
The three primary event selectors are indexed; the remaining Sui-equivalent
execution snapshot is ABI-encoded in the event `payload` field.

Run the basic tests with:

```powershell
npm install
npm test
```

The contract is intentionally not coupled to a proxy framework. Production
upgrade policy must be selected and reviewed for the target Ethereum network
before deployment.

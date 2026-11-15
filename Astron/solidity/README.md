# OAN Bulletin for Astron Solidity

Astron/Xinghuo BIF 3.0 supports Solidity 0.8.21 through its platform compiler.
This project subclasses the Ethereum Solidity implementation because both
implement the same Sui-derived governance state machine. Compiling it with the
Astron compiler changes the platform `address` representation and target
opcodes as required by BIF-Core.

The local tests resolve the shared source and compile it with both upstream
Solidity 0.8.21 and the official `@bifproject/solc-bif` 0.8.21 toolchain.
On-network platform conformance testing is still required before production
use.

```powershell
npm install
npm test
```

No deployment scripts or integrations with other OAN modules are included.

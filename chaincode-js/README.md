# OAN Bulletin JavaScript Chaincode

This project implements the governance semantics of the Sui OAN bulletin as
Hyperledger Fabric JavaScript chaincode. Fabric client identities replace Sui
addresses. State-changing timestamps are taken from the Fabric transaction
timestamp so that endorsing peers execute deterministically.

The project includes basic state-machine tests only. It does not include a
Fabric network, packaging/deployment scripts, endorsement-policy setup, or
integration with other OAN modules.

```powershell
npm install
npm test
```

The chaincode stores one JSON bulletin document under `OAN_BULLETIN`. The
production endorsement policy must protect governance invocations in addition
to the committee checks implemented by the chaincode.

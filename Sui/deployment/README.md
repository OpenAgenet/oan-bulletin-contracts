<!-- Copyright (c) 2026 OpenAgenet contributors -->
<!--
Initial author: JINLIANG XU
Email: jlxufly@gmail.com
-->

# Deployment

This directory now contains a usable mainnet deployment toolkit for the
`oan_bulletin` Move package.

## Files

- `mainnet-config.sample.json`
  Sample bootstrap configuration. Copy it to a local file such as
  `mainnet-config.local.json` and replace the placeholder addresses.
- `OanBulletinDeployment.Common.ps1`
  Shared validation, JSON parsing, and output helpers.
- `Publish-OanBulletinMainnet.ps1`
  Runs preflight checks, optional tests, package build, then publishes the Move
  package to Sui mainnet.
- `Initialize-OanBulletinMainnet.ps1`
  Calls `PACKAGE_ID::bulletin::initialize` with the published `UpgradeCap` to
  create the shared `Bulletin` object and the publisher-owned `UpgradeManager`.
- `Deploy-OanBulletinMainnet.ps1`
  Wrapper that performs publish and initialize sequentially, then writes a
  combined deployment record.
- `DEPLOYMENT-HISTORY.md`
  Committed human-readable history of the legacy upgrade lineage and the
  profile-v2 fresh-package release.
- `deployment-history.json`
  Machine-readable release index with package IDs, Bulletin IDs, transaction
  digests, and governance authorization references.
- `runtime/`
  Local-only receipts and deployment records written by the scripts. This
  directory is git-ignored on purpose.

## Preconditions

Before publishing to Sui mainnet, make sure:

- the active Sui CLI environment is `mainnet`
- `sui client chain-identifier` returns `35834a8a`
- the sender address in your keystore has enough SUI for both publish and
  initialize transactions
- the governance committee addresses in the config file are final and reviewed
- the Move package at `../move-package` passes `sui move test`

The scripts enforce the first two checks automatically and warn if the sender
does not appear to have visible gas coins.

## Bootstrap security requirements

The contract now enforces two bootstrap rules on-chain:

- the sender that calls `initialize` must be the same address that published
  the package
- the `UpgradeCap` passed to `initialize` must belong to that exact published
  package

Operationally, this means:

- do not switch wallet/account between publish and initialize
- do not reuse an `UpgradeCap` from any previous rehearsal or other package
- always source `packageId` and `upgradeCapId` from the publish receipt written
  by `Publish-OanBulletinMainnet.ps1`

If these conditions are not met, `initialize` will abort on-chain.

## Recommended operator flow

1. Copy the sample config:

   ```powershell
   Copy-Item .\mainnet-config.sample.json .\mainnet-config.local.json
   ```

2. Fill in:

   - `sender`
   - `rootAuthorityDid`
   - `metaAdmins`
   - `admins`
   - `adminThreshold`
   - gas budgets if you want to override the defaults

3. Run publish only:

   ```powershell
   .\Publish-OanBulletinMainnet.ps1 -ConfigPath .\mainnet-config.local.json
   ```

   The script writes a JSON receipt to `deployment/runtime/mainnet/` and prints
   a summary containing the published `packageId` and `upgradeCapId`.

   Treat that receipt as the source of truth for the next step. Do not manually
   substitute IDs from memory, old notes, or another environment.

4. Initialize the bulletin object:

   ```powershell
   .\Initialize-OanBulletinMainnet.ps1 `
     -ConfigPath .\mainnet-config.local.json `
     -PackageId 0xYOUR_PACKAGE_ID `
     -UpgradeCapId 0xYOUR_UPGRADE_CAP_ID
   ```

   The script writes a second JSON receipt and prints the detected
   `bulletinObjectId` if it can be extracted from transaction effects.

   This step must be submitted by the same sender that performed publish. The
   contract itself now checks that requirement.

5. Or run both in one step:

   ```powershell
   .\Deploy-OanBulletinMainnet.ps1 -ConfigPath .\mainnet-config.local.json
   ```

   This writes a consolidated deployment record in addition to the raw receipts.

## Dry runs

You can dry-run the individual steps:

```powershell
.\Publish-OanBulletinMainnet.ps1 -ConfigPath .\mainnet-config.local.json -DryRun
.\Initialize-OanBulletinMainnet.ps1 -ConfigPath .\mainnet-config.local.json -PackageId 0xYOUR_PACKAGE_ID -UpgradeCapId 0xYOUR_UPGRADE_CAP_ID -DryRun
```

Use dry runs to validate CLI arguments and gas-budget sizing before spending
mainnet funds. Do not use `Deploy-OanBulletinMainnet.ps1` for dry runs because
the initialize step requires a real published package ID.

## What the scripts record

The scripts write:

- full publish transaction JSON
- full initialize transaction JSON
- a merged deployment record with package ID, bulletin object ID, tx digests,
  config-derived Root authority DID, and local receipt paths

Those records are intended to be copied into the long-term operator archive
after the deployment is verified.

The committed release index is `deployment-history.json`. It must be updated
after every successful publish, initialize, or package upgrade. Dry-run receipts
remain useful for audit but must be marked as dry runs and must not be treated
as chain state.

## Post-deployment checks

After a real deployment, verify at least:

- the package ID exists on mainnet
- the shared `Bulletin` object exists and is readable
- the `UpgradeManager` is owned by the intended publisher address
- the configured Meta Admin and Admin addresses match the intended bootstrap set
- a small governance action on a non-production rehearsal environment has
  already validated the operational voting flow

## Security regression coverage

The associated Move unit tests now explicitly verify:

- initialize cannot run twice
- initialize by a non-publisher aborts
- initialize with a mismatched package `UpgradeCap` aborts
- Root authority DID is stored at initialization
- Registrar and VC issuer subjects reject Discovery-style domain payloads
- publisher-only upgrade control still works after initialization

## Roll-forward / rollback note

Move package publish on mainnet is not a reversible filesystem-style rollback.
If an incorrect package is published, the operational response should be:

- stop using the published package ID in governance tooling
- publish the corrected package
- initialize a new bulletin object
- archive the abandoned package/object IDs with a clear incident note

That is why the wrapper keeps raw receipts and why the config should be reviewed
before execution.

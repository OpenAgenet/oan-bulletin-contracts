# Copyright (c) 2026 OpenAgenet contributors
#
# Initial author: JINLIANG XU
# Email: jlxufly@gmail.com

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "mainnet-config.sample.json"),
    [switch]$SkipTests
)

. (Join-Path $PSScriptRoot "OanBulletinDeployment.Common.ps1")

$publishScript = Join-Path $PSScriptRoot "Publish-OanBulletinMainnet.ps1"
$initializeScript = Join-Path $PSScriptRoot "Initialize-OanBulletinMainnet.ps1"

$publishSummary = & $publishScript -ConfigPath $ConfigPath -SkipTests:$SkipTests
if ($LASTEXITCODE -ne 0) {
    throw "Publish script failed."
}

if (-not $publishSummary.packageId) {
    throw "Publish succeeded but packageId was not found in the response."
}
if (-not $publishSummary.upgradeCapId) {
    throw "Publish succeeded but upgradeCapId was not found in the response."
}
if (-not $publishSummary.initStateId) {
    throw "Publish succeeded but initStateId was not found in the response."
}

$initializeSummary = & $initializeScript -ConfigPath $ConfigPath -PackageId $publishSummary.packageId -InitStateId $publishSummary.initStateId -UpgradeCapId $publishSummary.upgradeCapId
if ($LASTEXITCODE -ne 0) {
    throw "Initialize script failed."
}

$runtimeRoot = Join-Path (Get-OanRuntimeRoot) "mainnet"
Ensure-OanDirectory -Path $runtimeRoot
$recordPath = Join-Path $runtimeRoot "$((Get-OanTimestampTag))-deployment-record.json"

$record = [pscustomobject]@{
    publishedAt        = (Get-Date).ToString("o")
    networkAlias       = "mainnet"
    chainId            = "35834a8a"
    sender             = $publishSummary.sender
    packagePath        = $publishSummary.packagePath
    packageId          = $publishSummary.packageId
    initStateId        = $publishSummary.initStateId
    upgradeCapId       = $publishSummary.upgradeCapId
    bulletinObjectId   = $initializeSummary.bulletinObjectId
    rootAuthorityDid   = $initializeSummary.rootAuthorityDid
    adminThreshold     = $initializeSummary.adminThreshold
    publishDigest      = $publishSummary.digest
    initializeDigest   = $initializeSummary.digest
    publishReceiptPath = $publishSummary.publishReceiptPath
    pubfilePath        = $publishSummary.pubfilePath
    initializeReceiptPath = $initializeSummary.initializeReceiptPath
}

Write-OanJsonFile -Path $recordPath -Value $record

$record

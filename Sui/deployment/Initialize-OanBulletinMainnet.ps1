# Copyright (c) 2026 OpenAgenet contributors
#
# Initial author: JINLIANG XU
# Email: jlxufly@gmail.com

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "mainnet-config.sample.json"),
    [Parameter(Mandatory = $true)]
    [string]$PackageId,
    [Parameter(Mandatory = $true)]
    [string]$InitStateId,
    [Parameter(Mandatory = $true)]
    [string]$UpgradeCapId,
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot "OanBulletinDeployment.Common.ps1")

$config = Read-OanDeploymentConfig -ConfigPath $ConfigPath
Assert-OanConfig -Config $config
Assert-OanNetworkContext -ExpectedAlias "mainnet" -ExpectedChainId "35834a8a"

if ($PackageId -notmatch "^0x[0-9a-fA-F]+$") {
    throw "PackageId must be a valid Sui object ID."
}
if ($InitStateId -notmatch "^0x[0-9a-fA-F]+$") {
    throw "InitStateId must be a valid Sui object ID."
}
if ($UpgradeCapId -notmatch "^0x[0-9a-fA-F]+$") {
    throw "UpgradeCapId must be a valid Sui object ID."
}

$sender = Get-OanSender -Config $config
Assert-OanSenderHasGasVisibility -Address $sender
$senderLiteral = ConvertTo-OanObjectLiteral -ObjectId $sender

$runtimeRoot = Join-Path (Get-OanRuntimeRoot) "mainnet"
Ensure-OanDirectory -Path $runtimeRoot
$tag = Get-OanTimestampTag
$initializeReceiptPath = Join-Path $runtimeRoot "$tag-initialize.json"

$rootAuthorityDid = Get-OanRootAuthorityDid -Config $config
$rootAuthorityDidLiteral = ConvertTo-OanStringLiteral -Value $rootAuthorityDid
$initStateLiteral = ConvertTo-OanObjectLiteral -ObjectId $InitStateId
$metaAdminsLiteral = ConvertTo-OanAddressVectorLiteral -Addresses $config.metaAdmins
$adminsLiteral = ConvertTo-OanAddressVectorLiteral -Addresses $config.admins
$upgradeCapLiteral = ConvertTo-OanObjectLiteral -ObjectId $UpgradeCapId
$functionTarget = "$PackageId::bulletin::initialize"

$ptbArgs = @(
    "client", "ptb",
    "--move-call", $functionTarget, $initStateLiteral, $rootAuthorityDidLiteral, $metaAdminsLiteral, $adminsLiteral, ([string]$config.adminThreshold), $upgradeCapLiteral,
    "--gas-budget", ([string]$config.initializeGasBudget),
    "--sender", $senderLiteral,
    "--json"
)

if ($DryRun) {
    $ptbArgs += "--dry-run"
}

Write-Host "Calling $functionTarget ..."
$initializeResponse = Invoke-SuiJson -Arguments $ptbArgs
Write-OanJsonFile -Path $initializeReceiptPath -Value $initializeResponse

$bulletinObjectId = Get-OanCreatedBulletinObjectId -CallResponse $initializeResponse

$summary = [pscustomobject]@{
    networkAlias          = "mainnet"
    chainId               = "35834a8a"
    sender                = $sender
    packageId             = $PackageId
    initStateId           = $InitStateId
    upgradeCapId          = $UpgradeCapId
    rootAuthorityDid      = $rootAuthorityDid
    adminThreshold        = [int64]$config.adminThreshold
    dryRun                = [bool]$DryRun
    initializeReceiptPath = $initializeReceiptPath
    bulletinObjectId      = $bulletinObjectId
    digest                = $initializeResponse.digest
}

$summary

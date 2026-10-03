# Copyright (c) 2026 OpenAgenet contributors
#
# Initial author: JINLIANG XU
# Email: jlxufly@gmail.com

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "mainnet-config.sample.json"),
    [string]$PackagePath = "",
    [switch]$SkipTests,
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot "OanBulletinDeployment.Common.ps1")

if ([string]::IsNullOrWhiteSpace($PackagePath)) {
    $PackagePath = Get-OanMovePackagePath
}

$config = Read-OanDeploymentConfig -ConfigPath $ConfigPath
Assert-OanConfig -Config $config
Assert-OanNetworkContext -ExpectedAlias "mainnet" -ExpectedChainId "35834a8a"

$sender = Get-OanSender -Config $config
Assert-OanSenderHasGasVisibility -Address $sender

if (-not (Test-Path -LiteralPath $PackagePath)) {
    throw "Move package path not found: $PackagePath"
}

if (-not $SkipTests) {
    Write-Host "Running Move tests before publish..."
    Invoke-SuiText -Arguments @("move", "test", "--path", $PackagePath)
}

Write-Host "Building Move package before publish..."
Invoke-SuiText -Arguments @("move", "build", "--path", $PackagePath)

$runtimeRoot = Join-Path (Get-OanRuntimeRoot) "mainnet"
Ensure-OanDirectory -Path $runtimeRoot
$tag = Get-OanTimestampTag
$publishReceiptPath = Join-Path $runtimeRoot "$tag-publish.json"
$pubfilePath = Join-Path $runtimeRoot "$tag-publish.pub"

if ($DryRun) {
    $publishArgs = @(
        "client", "test-publish", $PackagePath,
        "--gas-budget", ([string]$config.publishGasBudget),
        "--sender", $sender,
        "--pubfile-path", $pubfilePath,
        "--build-env", "mainnet",
        "--json"
    )
} else {
    $publishArgs = @(
        "client", "publish", $PackagePath,
        "--gas-budget", ([string]$config.publishGasBudget),
        "--sender", $sender,
        "--json"
    )
}

Write-Host "Publishing package from $PackagePath ..."
$publishResponse = Invoke-SuiJson -Arguments $publishArgs
Write-OanJsonFile -Path $publishReceiptPath -Value $publishResponse

$packageId = Get-OanPublishedPackageId -PublishResponse $publishResponse
$initStateId = Get-OanPublishedInitStateId -PublishResponse $publishResponse
$upgradeCapId = Get-OanPublishedUpgradeCapId -PublishResponse $publishResponse

$summary = [pscustomobject]@{
    networkAlias       = "mainnet"
    chainId            = "35834a8a"
    sender             = $sender
    packagePath        = $PackagePath
    dryRun             = [bool]$DryRun
    publishReceiptPath = $publishReceiptPath
    pubfilePath        = $pubfilePath
    packageId          = $packageId
    initStateId        = $initStateId
    upgradeCapId       = $upgradeCapId
    digest             = $publishResponse.digest
}

$summary

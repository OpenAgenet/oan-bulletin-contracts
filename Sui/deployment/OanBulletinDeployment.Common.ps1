# Copyright (c) 2026 OpenAgenet contributors
#
# Initial author: JINLIANG XU
# Email: jlxufly@gmail.com

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:OanDeploymentRoot = $PSScriptRoot

function Get-OanDeploymentRoot {
    return $script:OanDeploymentRoot
}

function Get-OanMovePackagePath {
    return Join-Path (Split-Path -Parent $script:OanDeploymentRoot) "development\move-package"
}

function Get-OanRuntimeRoot {
    return Join-Path $script:OanDeploymentRoot "runtime"
}

function Ensure-OanDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Invoke-SuiText {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $escapedArgs = $Arguments | ForEach-Object {
        '"' + ([string]$_).Replace('"', '\"') + '"'
    }
    $command = "sui $($escapedArgs -join ' ')"
    $lines = & cmd.exe /c "$command 2>&1"
    if ($LASTEXITCODE -ne 0) {
        throw "sui $($Arguments -join ' ') failed:`n$($lines | Out-String)"
    }

    return (($lines | Out-String).Trim())
}

function Invoke-SuiJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $text = Invoke-SuiText -Arguments $Arguments
    $jsonMatch = [regex]::Match($text, "\{\s*""digest""\s*:")
    if ($jsonMatch.Success) {
        $text = $text.Substring($jsonMatch.Index).TrimStart()
    }
    try {
        return ConvertFrom-Json -InputObject $text
    } catch {
        throw "Expected JSON from 'sui $($Arguments -join ' ')', got:`n$text"
    }
}

function Read-OanDeploymentConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    return Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
}

function Get-OanActiveEnvState {
    $state = Invoke-SuiJson -Arguments @("client", "envs", "--json")
    return [pscustomobject]@{
        Environments = $state[0]
        ActiveAlias  = $state[1]
    }
}

function Assert-OanNetworkContext {
    param(
        [string]$ExpectedAlias = "mainnet",
        [string]$ExpectedChainId = "35834a8a"
    )

    $state = Get-OanActiveEnvState
    if ($state.ActiveAlias -ne $ExpectedAlias) {
        throw "Active Sui environment must be '$ExpectedAlias', current: '$($state.ActiveAlias)'."
    }

    $currentChainId = Invoke-SuiText -Arguments @("client", "chain-identifier")
    if ($currentChainId -ne $ExpectedChainId) {
        throw "Active chain id must be '$ExpectedChainId', current: '$currentChainId'."
    }
}

function Get-OanActiveAddress {
    return Invoke-SuiText -Arguments @("client", "active-address")
}

function Assert-OanAddressList {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Addresses,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Addresses.Count -lt 4) {
        throw "$Name must contain at least 4 addresses."
    }

    $seen = @{}
    foreach ($address in $Addresses) {
        $value = [string]$address
        if ($value -notmatch "^0x[0-9a-fA-F]+$") {
            throw "$Name contains an invalid Sui address: $value"
        }
        if ($seen.ContainsKey($value.ToLowerInvariant())) {
            throw "$Name contains a duplicate address: $value"
        }
        $seen[$value.ToLowerInvariant()] = $true
    }
}

function Assert-OanConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $rootAuthorityDid = Get-OanRootAuthorityDid -Config $Config
    if ([string]::IsNullOrWhiteSpace($rootAuthorityDid)) {
        throw "rootAuthorityDid must be a non-empty string."
    }
    if ($rootAuthorityDid -notmatch '^did:oan:[1-9A-HJ-NP-Za-km-z]{5}:[1-9A-HJ-NP-Za-km-z]{32}$') {
        throw "rootAuthorityDid must be a profile-v2 did:oan identifier."
    }

    Assert-OanAddressList -Addresses $Config.metaAdmins -Name "metaAdmins"
    Assert-OanAddressList -Addresses $Config.admins -Name "admins"

    $threshold = [int64]$Config.adminThreshold
    if ($threshold -lt 1) {
        throw "adminThreshold must be >= 1."
    }

    if ($Config.PSObject.Properties.Name -contains "sender" -and -not [string]::IsNullOrWhiteSpace([string]$Config.sender)) {
        if ([string]$Config.sender -notmatch "^0x[0-9a-fA-F]+$") {
            throw "sender must be a valid Sui address."
        }
    }
}

function Get-OanRootAuthorityDid {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if ($Config.PSObject.Properties.Name -contains "rootAuthorityDid") {
        return [string]$Config.rootAuthorityDid
    }

    if ($Config.PSObject.Properties.Name -contains "rootDomainId") {
        return [string]$Config.rootDomainId
    }

    return ""
}

function Get-OanSender {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if ($Config.PSObject.Properties.Name -contains "sender" -and -not [string]::IsNullOrWhiteSpace([string]$Config.sender)) {
        return [string]$Config.sender
    }

    return Get-OanActiveAddress
}

function Get-OanGasCoins {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Address
    )

    return Invoke-SuiJson -Arguments @("client", "gas", $Address, "--json")
}

function Assert-OanSenderHasGasVisibility {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Address
    )

    $coins = Get-OanGasCoins -Address $Address
    if (-not $coins -or $coins.Count -eq 0) {
        Write-Warning "No visible gas coins were returned for sender $Address. Mainnet publish/initialize will fail until this address is funded."
    }
}

function Get-OanTimestampTag {
    return (Get-Date).ToString("yyyyMMdd-HHmmss")
}

function ConvertTo-OanAddressVectorLiteral {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Addresses
    )

    $items = $Addresses | ForEach-Object { "@$([string]$_)" }
    return "vector[$($items -join ', ')]"
}

function ConvertTo-OanStringLiteral {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function ConvertTo-OanObjectLiteral {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ObjectId
    )

    if ($ObjectId -notmatch "^0x[0-9a-fA-F]+$") {
        throw "ObjectId must be a valid Sui object ID."
    }

    return "@$ObjectId"
}

function Write-OanJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    Ensure-OanDirectory -Path (Split-Path -Parent $Path)
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Get-OanPublishedPackageId {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PublishResponse
    )

    $publishedChange = $PublishResponse.objectChanges | Where-Object { $_.type -eq "published" } | Select-Object -First 1
    if (-not $publishedChange) {
        return $null
    }

    if ($publishedChange.PSObject.Properties.Name -contains "packageId") {
        return [string]$publishedChange.packageId
    }
    if ($publishedChange.PSObject.Properties.Name -contains "package_id") {
        return [string]$publishedChange.package_id
    }

    return $null
}

function Get-OanPublishedUpgradeCapId {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PublishResponse
    )

    $candidate = $PublishResponse.objectChanges | Where-Object {
        $_.type -eq "created" -and
        ($_.PSObject.Properties.Name -contains "objectType") -and
        [string]$_.objectType -eq "0x2::package::UpgradeCap"
    } | Select-Object -First 1

    if (-not $candidate) {
        return $null
    }

    if ($candidate.PSObject.Properties.Name -contains "objectId") {
        return [string]$candidate.objectId
    }
    if ($candidate.PSObject.Properties.Name -contains "object_id") {
        return [string]$candidate.object_id
    }

    return $null
}

function Get-OanPublishedInitStateId {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PublishResponse
    )

    $candidate = $PublishResponse.objectChanges | Where-Object {
        $_.type -eq "created" -and
        ($_.PSObject.Properties.Name -contains "objectType") -and
        [string]$_.objectType -like "*::bulletin::BulletinInitState"
    } | Select-Object -First 1

    if (-not $candidate) {
        return $null
    }

    if ($candidate.PSObject.Properties.Name -contains "objectId") {
        return [string]$candidate.objectId
    }
    if ($candidate.PSObject.Properties.Name -contains "object_id") {
        return [string]$candidate.object_id
    }

    return $null
}

function Get-OanCreatedBulletinObjectId {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$CallResponse
    )

    $candidate = $CallResponse.objectChanges | Where-Object {
        ($_.type -eq "created" -or $_.type -eq "mutated") -and
        ($_.PSObject.Properties.Name -contains "objectType") -and
        [string]$_.objectType -like "*::bulletin::Bulletin"
    } | Select-Object -First 1

    if (-not $candidate) {
        return $null
    }

    if ($candidate.PSObject.Properties.Name -contains "objectId") {
        return [string]$candidate.objectId
    }
    if ($candidate.PSObject.Properties.Name -contains "object_id") {
        return [string]$candidate.object_id
    }

    return $null
}

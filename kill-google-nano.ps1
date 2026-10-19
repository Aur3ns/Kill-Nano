# Kill-Nano: prevent Google Chrome downloading its on-device foundational AI model.
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Status', 'Restore')]
    [string]$Action = 'Install',
    [switch]$DryRun,
    [switch]$SkipCleanup,
    [switch]$DnsAutomatic
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ChromePolicyPath = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
$StatePath = 'HKLM:\SOFTWARE\KillNano'
$ModelPolicyName = 'GenAILocalFoundationalModelSettings'
$DnsPolicyName = 'DnsOverHttpsMode'
$ChromeUserData = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'

function Get-RegistryValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $property = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $property) { return $null }
    return $property.$Name
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-ManagedValue {
    param(
        [string]$Name,
        [object]$Value,
        [string]$PropertyType,
        [string]$Marker
    )
    $current = Get-RegistryValue -Path $ChromePolicyPath -Name $Name
    if ($null -ne $current) {
        if ([string]$current -ne [string]$Value) {
            throw "Refusing to overwrite existing Chrome policy $Name ($current)."
        }
        Write-Host "Already configured: $Name = $current (not claiming ownership)."
        return
    }
    if ($DryRun) {
        Write-Host "[dry-run] Would set $Name = $Value"
        return
    }
    New-Item -Path $ChromePolicyPath -Force | Out-Null
    New-Item -Path $StatePath -Force | Out-Null
    # Ownership marker allows -Action Restore without deleting someone else's policy.
    New-ItemProperty -Path $StatePath -Name $Marker -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $ChromePolicyPath -Name $Name -Value $Value -PropertyType $PropertyType -Force | Out-Null
    Write-Host "Installed: $Name = $Value"
}

function Remove-OwnedValue {
    param([string]$Name, [object]$Expected, [string]$Marker)
    $owned = Get-RegistryValue -Path $StatePath -Name $Marker
    $current = Get-RegistryValue -Path $ChromePolicyPath -Name $Name
    if ($owned -ne 1) {
        Write-Host "Not removing ${Name}: no Kill-Nano ownership record."
        return
    }
    if ($null -ne $current -and [string]$current -ne [string]$Expected) {
        throw "Refusing to remove modified policy $Name ($current)."
    }
    if ($DryRun) {
        Write-Host "[dry-run] Would remove $Name and its ownership record."
        return
    }
    if ($null -ne $current) {
        Remove-ItemProperty -Path $ChromePolicyPath -Name $Name
    }
    Remove-ItemProperty -Path $StatePath -Name $Marker
    Write-Host "Restored: $Name"
}

if ($Action -ne 'Install' -and ($SkipCleanup -or $DnsAutomatic)) {
    throw '-SkipCleanup and -DnsAutomatic are only valid with -Action Install.'
}

if ($Action -eq 'Status') {
    Write-Host "Model policy: $(Get-RegistryValue -Path $ChromePolicyPath -Name $ModelPolicyName)"
    Write-Host "DNS-over-HTTPS policy: $(Get-RegistryValue -Path $ChromePolicyPath -Name $DnsPolicyName)"
    Write-Host 'Check chrome://policy for the effective policy and any other administrators.'
    return
}

if (-not (Test-IsAdministrator)) {
    throw 'Run PowerShell as Administrator to install or restore machine policies.'
}

if ($Action -eq 'Restore') {
    # Preflight all owned policies before making any changes.
    foreach ($entry in @(
        @{ Name = $ModelPolicyName; Expected = '1'; Marker = 'OwnsModelPolicy' },
        @{ Name = $DnsPolicyName; Expected = 'automatic'; Marker = 'OwnsDnsPolicy' }
    )) {
        $owned = Get-RegistryValue -Path $StatePath -Name $entry.Marker
        $current = Get-RegistryValue -Path $ChromePolicyPath -Name $entry.Name
        if ($owned -eq 1 -and $null -ne $current -and [string]$current -ne $entry.Expected) {
            throw "Refusing to remove modified policy $($entry.Name) ($current)."
        }
    }
    Remove-OwnedValue -Name $ModelPolicyName -Expected 1 -Marker 'OwnsModelPolicy'
    Remove-OwnedValue -Name $DnsPolicyName -Expected 'automatic' -Marker 'OwnsDnsPolicy'
    Write-Host 'Restart Chrome and inspect chrome://policy. Other system policies are untouched.'
    return
}

# Check for conflicts before changing anything.
$modelExisting = Get-RegistryValue -Path $ChromePolicyPath -Name $ModelPolicyName
if ($null -ne $modelExisting -and [string]$modelExisting -ne '1') {
    throw "A different managed model policy already exists: $modelExisting"
}
if ($DnsAutomatic) {
    $dnsExisting = Get-RegistryValue -Path $ChromePolicyPath -Name $DnsPolicyName
    if ($null -ne $dnsExisting -and [string]$dnsExisting -ne 'automatic') {
        throw "A different managed DNS-over-HTTPS policy already exists: $dnsExisting"
    }
}

Set-ManagedValue -Name $ModelPolicyName -Value 1 -PropertyType DWord -Marker 'OwnsModelPolicy'
if ($DnsAutomatic) {
    Set-ManagedValue -Name $DnsPolicyName -Value 'automatic' -PropertyType String -Marker 'OwnsDnsPolicy'
} else {
    Write-Host 'DNS-over-HTTPS is unchanged. Managed Chrome may disable Secure DNS by default.'
}

if ($SkipCleanup) {
    Write-Host 'Model-file cleanup skipped by request.'
} elseif (Get-Process -Name chrome -ErrorAction SilentlyContinue) {
    Write-Warning 'Chrome is running. Not deleting live model data; close Chrome and rerun to clean up.'
} elseif (Test-Path -LiteralPath $ChromeUserData -PathType Container) {
    foreach ($folder in @('OptGuideOnDeviceModel')) {
        $target = Join-Path $ChromeUserData $folder
        if (-not (Test-Path -LiteralPath $target)) { continue }
        $item = Get-Item -LiteralPath $target -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Write-Warning "Refusing to remove reparse point: $target"
            continue
        }
        if (-not $item.PSIsContainer) {
            Write-Warning "Expected a directory, leaving file untouched: $target"
            continue
        }
        if ($DryRun) {
            Write-Host "[dry-run] Would remove $target"
        } else {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
            Write-Host "Removed: $target"
        }
    }
}

if (Test-Path -LiteralPath $ChromeUserData -PathType Container) {
    Write-Host 'Remaining weights.bin files (possibly unrelated to the foundational AI model):'
    Get-ChildItem -LiteralPath $ChromeUserData -File -Filter 'weights.bin' -Recurse -Force `
        -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_.FullName }
}
if ($DryRun) {
    Write-Host '[dry-run] No changes were made.'
} else {
    Write-Host 'Done. Restart Chrome and verify GenAILocalFoundationalModelSettings = 1 at chrome://policy.'
}

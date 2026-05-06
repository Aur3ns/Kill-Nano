# kill-google-nano.ps1
# PowerShell script to block Chrome's local AI model
# Removes OptGuideOnDeviceModel / weights.bin and applies a Chrome policy.

$ErrorActionPreference = "Stop"

$PolicyPath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
$PolicyName = "GenAILocalFoundationalModelSettings"
$PolicyValue = 1

$ChromeUserData = "$env:LOCALAPPDATA\Google\Chrome\User Data"

Write-Host "[1/6] Checking administrator rights..."

$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Error: run this script as Administrator."
    exit 1
}

Write-Host "[2/6] Closing Chrome..."

Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "[3/6] Creating Chrome policy..."

if (-not (Test-Path $PolicyPath)) {
    New-Item -Path $PolicyPath -Force | Out-Null
}

New-ItemProperty `
    -Path $PolicyPath `
    -Name $PolicyName `
    -Value $PolicyValue `
    -PropertyType DWord `
    -Force | Out-Null

Write-Host "[4/6] Removing already downloaded models..."

$Targets = @(
    "$ChromeUserData\OptGuideOnDeviceModel",
    "$ChromeUserData\optimization_guide_model_store"
)

foreach ($Target in $Targets) {
    if (Test-Path $Target) {
        Write-Host "Removing: $Target"
        Remove-Item -Path $Target -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[5/6] Searching for remaining weights.bin files..."

if (Test-Path $ChromeUserData) {
    $Found = Get-ChildItem `
        -Path $ChromeUserData `
        -Filter "weights.bin" `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    if ($Found) {
        Write-Host "Warning: some weights.bin files still exist:"
        $Found | ForEach-Object {
            Write-Host $_.FullName
        }
    } else {
        Write-Host "No weights.bin file found in the Chrome user directory."
    }
} else {
    Write-Host "Chrome user data directory not found."
}

Write-Host "[6/6] Done."

Write-Host ""
Write-Host "Now restart Chrome and check:"
Write-Host "  chrome://policy/"
Write-Host ""
Write-Host "You should see:"
Write-Host "  GenAILocalFoundationalModelSettings = 1"
Write-Host ""
Write-Host "You can also verify with PowerShell:"
Write-Host "  Get-ChildItem `"$ChromeUserData`" -Filter weights.bin -Recurse -Force -ErrorAction SilentlyContinue"

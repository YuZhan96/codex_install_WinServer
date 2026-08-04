<#
.SYNOPSIS
    Entry point for the ChatGPT Codex offline installer.
.DESCRIPTION
    Loads the Codex app manifest and runs the modular installer workflow.
#>

#Requires -RunAsAdministrator

param(
    [string] $Manifest = (Join-Path $PSScriptRoot "config\codex.app.psd1"),

    [string] $DownloadDir = (Join-Path $PSScriptRoot "downloads"),

    [ValidateSet("Retail", "RP", "Slow", "Fast", "WIS", "WIF")]
    [string] $Ring = "Retail",

    [int] $DownloadRetries = 3,

    [switch] $Force,

    [switch] $DownloadOnly,

    [switch] $InstallOnly,

    [switch] $PlanOnly,

    [switch] $NoPause
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$modulePath = Join-Path $PSScriptRoot "src\CodexInstaller.psm1"
$manifestPath = $Manifest

if ($DownloadOnly -and $InstallOnly) {
    throw "Use either -DownloadOnly or -InstallOnly, not both."
}

if (!(Test-Path $manifestPath)) {
    throw "Manifest file not found: $manifestPath"
}

Import-Module $modulePath -Force
$appManifest = Import-PowerShellDataFile -Path $manifestPath

try {
    Start-CodexOfflineInstall `
        -AppManifest $appManifest `
        -ManifestPath $manifestPath `
        -DownloadDir $DownloadDir `
        -Ring $Ring `
        -DownloadRetries $DownloadRetries `
        -Force:$Force `
        -DownloadOnly:$DownloadOnly `
        -InstallOnly:$InstallOnly `
        -PlanOnly:$PlanOnly `
        -NoPause:$NoPause
}
catch {
    Write-Host ""
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red

    $activityId = $_.Exception.Data["ActivityId"]
    if ($activityId) {
        Write-Host ""
        Write-Host "Recent package log entries:" -ForegroundColor Yellow
        Get-AppPackageLog -ActivityID $activityId -ErrorAction SilentlyContinue | Select-Object -Last 5
    }

    if (-not $NoPause) {
        Write-Host ""
        Read-Host "Press Enter to exit"
    }

    exit 1
}

if (-not $NoPause) {
    Write-Host ""
    Read-Host "Press Enter to exit"
}

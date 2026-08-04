<#
.SYNOPSIS
    Offline installer for the ChatGPT Codex desktop app.
.DESCRIPTION
    Downloads and installs the ChatGPT Codex MSIX package from Microsoft Store
    package metadata. This is intended for Windows environments where Microsoft
    Store is unavailable, such as Windows Server.
.NOTES
    Version: v1.0
    Date: 2026-08-04
    App: ChatGPT Codex (OpenAI.Codex)
    Store ID: 9PLM9XGG6VKS
#>

#Requires -RunAsAdministrator

# ============================================================
# Configuration
# ============================================================

$DownloadDir = Join-Path $PSScriptRoot "downloads"
$StoreUrl    = "https://apps.microsoft.com/detail/9PLM9XGG6VKS"
$ApiUrl      = "https://store.uihtm.com/api/packages"
$Ring        = "Retail"   # Retail / RP / Slow / Fast / WIS / WIF

# ============================================================
# Initialization
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ChatGPT Codex Offline Installer v1.0" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$Arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { "x64" }
    "x86"   { "x86" }
    "ARM64" { "arm64" }
    default { "x64" }
}

Write-Host "[*] System architecture: $Arch"
Write-Host ""

if (!(Test-Path $DownloadDir)) {
    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
}

# ============================================================
# Helpers
# ============================================================

function Decode-HtmlEntities {
    param([string]$Text)
    return [System.Net.WebUtility]::HtmlDecode($Text)
}

function Get-PackageVersionFromName {
    param([string]$PackageName)

    if ($PackageName -match '_(\d+\.\d+\.\d+\.\d+)_') {
        return $Matches[1]
    }

    return $null
}

function Get-InstalledAppxVersion {
    param([string]$PackageName)

    $package = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue
    if ($package) {
        return $package.Version
    }

    return $null
}

function Download-PackageFile {
    param(
        [Parameter(Mandatory = $true)] $Package,
        [Parameter(Mandatory = $true)] [string] $OutputPath,
        [Parameter(Mandatory = $true)] [string] $Label
    )

    $packageUrl = Decode-HtmlEntities $Package.url

    if ((Test-Path $OutputPath) -and ((Get-Item $OutputPath).Length -eq $Package.size)) {
        Write-Host "    [OK] $Label already exists, skipping download" -ForegroundColor Green
        return
    }

    Write-Host "    Downloading $Label: $([math]::Round($Package.size / 1MB, 2)) MB"
    Write-Host "    Please wait..."

    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($packageUrl, $OutputPath)

        $actualSize = (Get-Item $OutputPath).Length
        if ($actualSize -ne $Package.size) {
            throw "Incomplete download: expected $($Package.size) bytes, got $actualSize bytes"
        }

        Write-Host "    [OK] $Label downloaded" -ForegroundColor Green
    }
    catch {
        Write-Host "    [FAIL] Download failed: $($_.Exception.Message)" -ForegroundColor Red
        if (Test-Path $OutputPath) {
            Remove-Item $OutputPath -Force
        }
        throw
    }
}

# ============================================================
# Step 1: Fetch package metadata
# ============================================================

Write-Host "[1/4] Fetching ChatGPT Codex package metadata from Store..." -ForegroundColor Yellow

try {
    $body = @{
        type  = "url"
        value = $StoreUrl
        ring  = $Ring
    } | ConvertTo-Json

    $response = Invoke-WebRequest -Uri $ApiUrl -Method Post -Body $body `
        -ContentType "application/json" -UseBasicParsing -TimeoutSec 30

    $data = $response.Content | ConvertFrom-Json

    if (!$data.ok -or !$data.packages) {
        throw "Unexpected API response"
    }

    Write-Host "    Found $($data.packages.Count) packages"
    Write-Host ""
}
catch {
    Write-Host "    [FAIL] Metadata request failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "    Possible causes:" -ForegroundColor Yellow
    Write-Host "    - Network connectivity issue"
    Write-Host "    - Package metadata service is unavailable"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ============================================================
# Step 2: Select packages
# ============================================================

Write-Host "[2/4] Selecting matching packages..." -ForegroundColor Yellow

$mainPackage = $null
$dependencyPackages = @()

foreach ($package in $data.packages) {
    if ($package.name -match "^OpenAI\.Codex_" -and $package.name -match "_$Arch`_") {
        $mainPackage = $package
        Write-Host "    Main package: $($package.name) ($([math]::Round($package.size / 1MB, 2)) MB)"
        continue
    }

    if ($package.arch -eq $Arch -or $package.arch -eq "neutral") {
        $dependencyPackages += $package
        Write-Host "    Dependency: $($package.name) ($([math]::Round($package.size / 1MB, 2)) MB)"
    }
}

if (!$mainPackage) {
    Write-Host "    [FAIL] No main package found for $Arch" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""

# ============================================================
# Step 3: Check version and download
# ============================================================

Write-Host "[3/4] Checking version and downloading packages..." -ForegroundColor Yellow

$latestVersion = Get-PackageVersionFromName $mainPackage.name
$installedVersion = Get-InstalledAppxVersion -PackageName "OpenAI.Codex"

if ($installedVersion) {
    Write-Host "    Installed version: $installedVersion"
    Write-Host "    Latest version:    $latestVersion"

    if ($installedVersion -eq $latestVersion) {
        Write-Host ""
        Write-Host "    [OK] Already up to date" -ForegroundColor Green
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 0
    }

    Write-Host "    Update available, continuing..."
}
else {
    Write-Host "    ChatGPT Codex is not installed. Latest version: $latestVersion"
}

Write-Host ""

$mainOutput = Join-Path $DownloadDir $mainPackage.name

try {
    Download-PackageFile -Package $mainPackage -OutputPath $mainOutput -Label "main package"

    foreach ($dependencyPackage in $dependencyPackages) {
        $dependencyOutput = Join-Path $DownloadDir $dependencyPackage.name
        Download-PackageFile -Package $dependencyPackage -OutputPath $dependencyOutput -Label $dependencyPackage.name
    }
}
catch {
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""

# ============================================================
# Step 4: Install
# ============================================================

Write-Host "[4/4] Installing ChatGPT Codex..." -ForegroundColor Yellow
Write-Host ""

$runningProcess = Get-Process -Name "OpenAI.Codex" -ErrorAction SilentlyContinue
if ($runningProcess) {
    Write-Host "    ChatGPT Codex is running. Closing it now..."
    Stop-Process -Name "OpenAI.Codex" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "    [OK] Process closed"
    Write-Host ""
}

if ($installedVersion) {
    Write-Host "    Removing old version..."
    try {
        Get-AppxPackage -Name "OpenAI.Codex" | Remove-AppxPackage -ErrorAction Stop
        Write-Host "    [OK] Old version removed" -ForegroundColor Green
    }
    catch {
        Write-Host "    [WARN] Removal failed. Trying fallback cleanup..." -ForegroundColor Yellow

        $appDir = "C:\Program Files\WindowsApps\OpenAI.Codex_*"
        if (Test-Path $appDir) {
            takeown /f "C:\Program Files\WindowsApps" /r /d y 2>&1 | Out-Null
            icacls "C:\Program Files\WindowsApps" /grant administrators:F /t 2>&1 | Out-Null
            Remove-Item $appDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host ""
}

if ($dependencyPackages.Count -gt 0) {
    Write-Host "    Installing dependencies..."
    foreach ($dependencyPackage in $dependencyPackages) {
        $dependencyOutput = Join-Path $DownloadDir $dependencyPackage.name
        if (Test-Path $dependencyOutput) {
            try {
                Add-AppxPackage -Path $dependencyOutput -ErrorAction Stop
                Write-Host "    [OK] $($dependencyPackage.name)" -ForegroundColor Green
            }
            catch {
                Write-Host "    [SKIP] $($dependencyPackage.name) is already installed or not required" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""
}

Write-Host "    Installing main package..."
try {
    Add-AppxPackage -Path $mainOutput -ErrorAction Stop
    Write-Host "    [OK] Main package installed" -ForegroundColor Green
}
catch {
    Write-Host "    [FAIL] Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "    Recent package log entries:" -ForegroundColor Yellow

    $activityId = $_.Exception.Data["ActivityId"]
    if ($activityId) {
        Get-AppPackageLog -ActivityID $activityId -ErrorAction SilentlyContinue | Select-Object -Last 5
    }

    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""

# ============================================================
# Done
# ============================================================

Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

$finalPackage = Get-AppxPackage -Name "OpenAI.Codex"
if ($finalPackage) {
    Write-Host "  App name:     $($finalPackage.Name)"
    Write-Host "  Version:      $($finalPackage.Version)"
    Write-Host "  Architecture: $($finalPackage.Architecture)"
    Write-Host "  Path:         $($finalPackage.InstallLocation)"

    $installSize = (Get-ChildItem $finalPackage.InstallLocation -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Host "  Size:         $([math]::Round($installSize / 1MB, 2)) MB"
}

Write-Host ""
Write-Host "  Launch options:" -ForegroundColor Cyan
Write-Host "  - Open ChatGPT Codex from the Start menu"
Write-Host "  - Or run: explorer.exe shell:appsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
Write-Host ""
Write-Host "  Download cache: $DownloadDir"
Write-Host ""

Read-Host "Press Enter to exit"

<#
.SYNOPSIS
    Offline installer for the ChatGPT Codex desktop app on Windows Server.
.DESCRIPTION
    Resolves Microsoft Store package metadata, downloads the matching ChatGPT
    Codex MSIX package and dependencies, then installs them with Add-AppxPackage.
.NOTES
    App: ChatGPT Codex (OpenAI.Codex)
    Store ID: 9PLM9XGG6VKS
#>

#Requires -RunAsAdministrator

param(
    [string] $DownloadDir = (Join-Path $PSScriptRoot "downloads"),

    [ValidateSet("Retail", "RP", "Slow", "Fast", "WIS", "WIF")]
    [string] $Ring = "Retail",

    [int] $DownloadRetries = 3,

    [switch] $Force,

    [switch] $DownloadOnly,

    [switch] $NoPause
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Installer = [ordered]@{
    Name                 = "ChatGPT Codex"
    PackageName          = "OpenAI.Codex"
    PackageNamePrefix    = "OpenAI.Codex_"
    ProcessName          = "OpenAI.Codex"
    StoreUrl             = "https://apps.microsoft.com/detail/9PLM9XGG6VKS"
    PackageApiUrl        = "https://store.uihtm.com/api/packages"
    AppUserModelId       = "OpenAI.Codex_2p2nqsd0c76g0!App"
    Version              = "1.0.0"
}

function Write-Section {
    param(
        [int] $Index,
        [int] $Total,
        [string] $Message
    )

    Write-Host ""
    Write-Host "[$Index/$Total] $Message" -ForegroundColor Yellow
}

function Write-Banner {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $($Installer.Name) Offline Installer" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Wait-BeforeExit {
    if (-not $NoPause) {
        Write-Host ""
        Read-Host "Press Enter to exit"
    }
}

function Resolve-StoreArchitecture {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { return "x64" }
        "x86"   { return "x86" }
        "ARM64" { return "arm64" }
        default { return "x64" }
    }
}

function Ensure-Directory {
    param([string] $Path)

    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Decode-HtmlEntities {
    param([string] $Text)

    return [System.Net.WebUtility]::HtmlDecode($Text)
}

function Get-PackageVersionFromName {
    param([string] $PackageName)

    if ($PackageName -match '_(\d+\.\d+\.\d+\.\d+)_') {
        return [version]$Matches[1]
    }

    return $null
}

function Get-InstalledPackage {
    param([string] $PackageName)

    return Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue
}

function Invoke-PackageMetadataRequest {
    param(
        [string] $StoreUrl,
        [string] $PackageApiUrl,
        [string] $Ring
    )

    $body = @{
        type  = "url"
        value = $StoreUrl
        ring  = $Ring
    } | ConvertTo-Json

    $response = Invoke-WebRequest -Uri $PackageApiUrl -Method Post -Body $body `
        -ContentType "application/json" -UseBasicParsing -TimeoutSec 30

    $data = $response.Content | ConvertFrom-Json
    if (!$data.ok -or !$data.packages) {
        throw "The package metadata response did not include a package list."
    }

    return $data.packages
}

function Test-PackageArchitecture {
    param(
        $Package,
        [string] $Architecture
    )

    return ($Package.arch -eq $Architecture -or $Package.arch -eq "neutral")
}

function Test-InstallablePackageName {
    param([string] $PackageName)

    return ($PackageName -match "\.(appx|appxbundle|msix|msixbundle)$")
}

function Select-InstallerPackages {
    param(
        [object[]] $Packages,
        [string] $Architecture
    )

    $mainPackage = $null
    $dependencies = @()

    foreach ($package in $Packages) {
        $isTargetMainPackage = $package.name -like "$($Installer.PackageNamePrefix)*" -and
            $package.name -match "_$Architecture`_" -and
            (Test-InstallablePackageName -PackageName $package.name)

        if ($isTargetMainPackage) {
            $mainPackage = $package
            continue
        }

        if ((Test-InstallablePackageName -PackageName $package.name) -and
            (Test-PackageArchitecture -Package $package -Architecture $Architecture)) {
            $dependencies += $package
        }
    }

    if (!$mainPackage) {
        throw "No $Architecture package was found for $($Installer.PackageName)."
    }

    return [pscustomobject]@{
        MainPackage  = $mainPackage
        Dependencies = $dependencies
    }
}

function Get-PackageOutputPath {
    param($Package)

    return Join-Path $DownloadDir $Package.name
}

function Test-CachedPackage {
    param(
        $Package,
        [string] $OutputPath
    )

    if (!(Test-Path $OutputPath)) {
        return $false
    }

    return ((Get-Item $OutputPath).Length -eq $Package.size)
}

function Save-PackageFile {
    param(
        $Package,
        [string] $OutputPath,
        [int] $Retries
    )

    if (Test-CachedPackage -Package $Package -OutputPath $OutputPath) {
        Write-Host "    [OK] Cached: $($Package.name)" -ForegroundColor Green
        return
    }

    $packageUrl = Decode-HtmlEntities $Package.url

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            Write-Host "    Downloading: $($Package.name)"
            Write-Host "    Size: $([math]::Round($Package.size / 1MB, 2)) MB, attempt $attempt of $Retries"

            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($packageUrl, $OutputPath)

            if (!(Test-CachedPackage -Package $Package -OutputPath $OutputPath)) {
                $actualSize = 0
                if (Test-Path $OutputPath) {
                    $actualSize = (Get-Item $OutputPath).Length
                }
                throw "Downloaded file size mismatch. Expected $($Package.size), got $actualSize."
            }

            Write-Host "    [OK] Downloaded: $($Package.name)" -ForegroundColor Green
            return
        }
        catch {
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -Force
            }

            if ($attempt -eq $Retries) {
                throw
            }

            Write-Host "    [WARN] Download failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds ([math]::Min($attempt * 2, 10))
        }
    }
}

function Save-InstallerPackages {
    param($PackageSelection)

    $orderedPackages = @($PackageSelection.Dependencies) + @($PackageSelection.MainPackage)
    foreach ($package in $orderedPackages) {
        Save-PackageFile -Package $package -OutputPath (Get-PackageOutputPath $package) -Retries $DownloadRetries
    }
}

function Stop-TargetProcess {
    $process = Get-Process -Name $Installer.ProcessName -ErrorAction SilentlyContinue
    if (!$process) {
        return
    }

    Write-Host "    Closing running process: $($Installer.ProcessName)"
    Stop-Process -Name $Installer.ProcessName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "    [OK] Process closed" -ForegroundColor Green
}

function Remove-InstalledPackage {
    param($InstalledPackage)

    if (!$InstalledPackage) {
        return
    }

    Write-Host "    Removing installed version: $($InstalledPackage.Version)"
    Remove-AppxPackage -Package $InstalledPackage.PackageFullName -ErrorAction Stop
    Write-Host "    [OK] Installed version removed" -ForegroundColor Green
}

function Add-PackageFromCache {
    param(
        $Package,
        [switch] $Required
    )

    $packagePath = Get-PackageOutputPath $Package
    if (!(Test-Path $packagePath)) {
        if ($Required) {
            throw "Package file is missing: $packagePath"
        }
        return
    }

    try {
        Add-AppxPackage -Path $packagePath -ErrorAction Stop
        Write-Host "    [OK] Installed: $($Package.name)" -ForegroundColor Green
    }
    catch {
        if ($Required) {
            throw
        }

        Write-Host "    [SKIP] Dependency already installed or not required: $($Package.name)" -ForegroundColor DarkGray
    }
}

function Install-SelectedPackages {
    param(
        $PackageSelection,
        $InstalledPackage
    )

    Stop-TargetProcess
    Remove-InstalledPackage -InstalledPackage $InstalledPackage

    if ($PackageSelection.Dependencies.Count -gt 0) {
        Write-Host "    Installing dependencies..."
        foreach ($dependency in $PackageSelection.Dependencies) {
            Add-PackageFromCache -Package $dependency
        }
    }

    Write-Host "    Installing main package..."
    Add-PackageFromCache -Package $PackageSelection.MainPackage -Required
}

function Write-PackageSummary {
    param($PackageSelection)

    $mainVersion = Get-PackageVersionFromName $PackageSelection.MainPackage.name
    Write-Host "    Main package: $($PackageSelection.MainPackage.name)"
    Write-Host "    Latest version: $mainVersion"
    Write-Host "    Dependencies: $($PackageSelection.Dependencies.Count)"
}

function Write-InstallSummary {
    $package = Get-InstalledPackage -PackageName $Installer.PackageName
    if (!$package) {
        Write-Host "    [WARN] Installation finished, but the app package was not found." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Installation complete" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  App name:     $($package.Name)"
    Write-Host "  Version:      $($package.Version)"
    Write-Host "  Architecture: $($package.Architecture)"
    Write-Host "  Path:         $($package.InstallLocation)"
    Write-Host ""
    Write-Host "  Launch options:" -ForegroundColor Cyan
    Write-Host "  - Open ChatGPT Codex from the Start menu"
    Write-Host "  - Or run: explorer.exe shell:appsFolder\$($Installer.AppUserModelId)"
    Write-Host ""
    Write-Host "  Download cache: $DownloadDir"
}

function Start-Installer {
    Write-Banner

    $architecture = Resolve-StoreArchitecture
    Write-Host "[*] System architecture: $architecture"
    Write-Host "[*] Release ring: $Ring"
    Write-Host "[*] Download cache: $DownloadDir"

    Ensure-Directory -Path $DownloadDir

    Write-Section -Index 1 -Total 4 -Message "Fetching Store package metadata"
    $packages = Invoke-PackageMetadataRequest -StoreUrl $Installer.StoreUrl -PackageApiUrl $Installer.PackageApiUrl -Ring $Ring
    Write-Host "    Found $($packages.Count) packages"

    Write-Section -Index 2 -Total 4 -Message "Selecting Codex packages"
    $selection = Select-InstallerPackages -Packages $packages -Architecture $architecture
    Write-PackageSummary -PackageSelection $selection

    $installedPackage = Get-InstalledPackage -PackageName $Installer.PackageName
    $latestVersion = Get-PackageVersionFromName $selection.MainPackage.name
    if ($installedPackage) {
        Write-Host "    Installed version: $($installedPackage.Version)"
    }

    if ($installedPackage -and !$Force -and ([version]$installedPackage.Version -eq $latestVersion)) {
        Write-Host ""
        Write-Host "    [OK] ChatGPT Codex is already up to date. Use -Force to reinstall." -ForegroundColor Green
        return
    }

    Write-Section -Index 3 -Total 4 -Message "Downloading package files"
    Save-InstallerPackages -PackageSelection $selection

    if ($DownloadOnly) {
        Write-Host ""
        Write-Host "    [OK] Download complete. Installation skipped because -DownloadOnly was set." -ForegroundColor Green
        return
    }

    Write-Section -Index 4 -Total 4 -Message "Installing ChatGPT Codex"
    Install-SelectedPackages -PackageSelection $selection -InstalledPackage $installedPackage
    Write-InstallSummary
}

try {
    Start-Installer
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

    Wait-BeforeExit
    exit 1
}

Wait-BeforeExit

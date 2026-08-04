function Write-InstallerBanner {
    param([hashtable] $Context)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $($Context.App.Name) Offline Installer" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-InstallerSection {
    param(
        [int] $Index,
        [int] $Total,
        [string] $Message
    )

    Write-Host ""
    Write-Host "[$Index/$Total] $Message" -ForegroundColor Yellow
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

function ConvertFrom-HtmlEncodedText {
    param([string] $Text)

    return [System.Net.WebUtility]::HtmlDecode($Text)
}

function Get-StorePackageVersion {
    param([string] $PackageName)

    if ($PackageName -match '_(\d+\.\d+\.\d+\.\d+)_') {
        return [version]$Matches[1]
    }

    return $null
}

function Get-InstalledAppPackage {
    param([hashtable] $App)

    return Get-AppxPackage -Name $App.PackageName -ErrorAction SilentlyContinue
}

function Invoke-StorePackageQuery {
    param(
        [hashtable] $App,
        [string] $Ring
    )

    $body = @{
        type  = "url"
        value = $App.StoreUrl
        ring  = $Ring
    } | ConvertTo-Json

    $response = Invoke-WebRequest -Uri $App.PackageApiUrl -Method Post -Body $body `
        -ContentType "application/json" -UseBasicParsing -TimeoutSec 30

    $data = $response.Content | ConvertFrom-Json
    if (!$data.ok -or !$data.packages) {
        throw "The package metadata response did not include a package list."
    }

    return $data.packages
}

function Test-InstallablePackageName {
    param([string] $PackageName)

    return ($PackageName -match "\.(appx|appxbundle|msix|msixbundle)$")
}

function Test-PackageArchitecture {
    param(
        $Package,
        [string] $Architecture
    )

    return ($Package.arch -eq $Architecture -or $Package.arch -eq "neutral")
}

function Select-CodexPackageSet {
    param(
        [hashtable] $App,
        [object[]] $Packages,
        [string] $Architecture
    )

    $mainCandidates = @()
    $dependencies = @()

    foreach ($package in $Packages) {
        if (!(Test-InstallablePackageName -PackageName $package.name)) {
            continue
        }

        $isTargetMainPackage = $package.name -like "$($App.PackageNamePrefix)*" -and
            $package.name -match "_$Architecture`_"

        if ($isTargetMainPackage) {
            $mainCandidates += $package
            continue
        }

        if (Test-PackageArchitecture -Package $package -Architecture $Architecture) {
            $dependencies += $package
        }
    }

    if ($mainCandidates.Count -eq 0) {
        throw "No $Architecture package was found for $($App.PackageName)."
    }

    $mainPackage = $mainCandidates |
        Sort-Object @{ Expression = { Get-StorePackageVersion $_.name }; Descending = $true }, name |
        Select-Object -First 1

    return [pscustomobject]@{
        MainPackage  = $mainPackage
        Dependencies = $dependencies
    }
}

function Get-PackageCachePath {
    param(
        [hashtable] $Context,
        $Package
    )

    return Join-Path $Context.DownloadDir $Package.name
}

function Test-PackageCache {
    param(
        $Package,
        [string] $Path
    )

    if (!(Test-Path $Path)) {
        return $false
    }

    return ((Get-Item $Path).Length -eq $Package.size)
}

function Save-StorePackage {
    param(
        [hashtable] $Context,
        $Package
    )

    $outputPath = Get-PackageCachePath -Context $Context -Package $Package
    if (Test-PackageCache -Package $Package -Path $outputPath) {
        Write-Host "    [OK] Cached: $($Package.name)" -ForegroundColor Green
        return
    }

    $packageUrl = ConvertFrom-HtmlEncodedText $Package.url

    for ($attempt = 1; $attempt -le $Context.DownloadRetries; $attempt++) {
        try {
            Write-Host "    Downloading: $($Package.name)"
            Write-Host "    Size: $([math]::Round($Package.size / 1MB, 2)) MB, attempt $attempt of $($Context.DownloadRetries)"

            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($packageUrl, $outputPath)

            if (!(Test-PackageCache -Package $Package -Path $outputPath)) {
                $actualSize = 0
                if (Test-Path $outputPath) {
                    $actualSize = (Get-Item $outputPath).Length
                }

                throw "Downloaded file size mismatch. Expected $($Package.size), got $actualSize."
            }

            Write-Host "    [OK] Downloaded: $($Package.name)" -ForegroundColor Green
            return
        }
        catch {
            if (Test-Path $outputPath) {
                Remove-Item $outputPath -Force
            }

            if ($attempt -eq $Context.DownloadRetries) {
                throw
            }

            Write-Host "    [WARN] Download failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds ([math]::Min($attempt * 2, 10))
        }
    }
}

function Save-SelectedPackages {
    param(
        [hashtable] $Context,
        $PackageSet
    )

    $orderedPackages = @($PackageSet.Dependencies) + @($PackageSet.MainPackage)
    foreach ($package in $orderedPackages) {
        Save-StorePackage -Context $Context -Package $package
    }
}

function Stop-AppProcess {
    param([hashtable] $App)

    $process = Get-Process -Name $App.ProcessName -ErrorAction SilentlyContinue
    if (!$process) {
        return
    }

    Write-Host "    Closing running process: $($App.ProcessName)"
    Stop-Process -Name $App.ProcessName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "    [OK] Process closed" -ForegroundColor Green
}

function Remove-AppPackageIfInstalled {
    param($InstalledPackage)

    if (!$InstalledPackage) {
        return
    }

    Write-Host "    Removing installed version: $($InstalledPackage.Version)"
    Remove-AppxPackage -Package $InstalledPackage.PackageFullName -ErrorAction Stop
    Write-Host "    [OK] Installed version removed" -ForegroundColor Green
}

function Add-CachedPackage {
    param(
        [hashtable] $Context,
        $Package,
        [switch] $Required
    )

    $packagePath = Get-PackageCachePath -Context $Context -Package $Package
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

function Install-CodexPackageSet {
    param(
        [hashtable] $Context,
        $PackageSet,
        $InstalledPackage
    )

    Stop-AppProcess -App $Context.App
    Remove-AppPackageIfInstalled -InstalledPackage $InstalledPackage

    if ($PackageSet.Dependencies.Count -gt 0) {
        Write-Host "    Installing dependencies..."
        foreach ($dependency in $PackageSet.Dependencies) {
            Add-CachedPackage -Context $Context -Package $dependency
        }
    }

    Write-Host "    Installing main package..."
    Add-CachedPackage -Context $Context -Package $PackageSet.MainPackage -Required
}

function Write-PackageSetSummary {
    param($PackageSet)

    $mainVersion = Get-StorePackageVersion $PackageSet.MainPackage.name
    Write-Host "    Main package: $($PackageSet.MainPackage.name)"
    Write-Host "    Latest version: $mainVersion"
    Write-Host "    Dependencies: $($PackageSet.Dependencies.Count)"
}

function Write-InstalledPackageSummary {
    param([hashtable] $Context)

    $package = Get-InstalledAppPackage -App $Context.App
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
    Write-Host "  - Or run: explorer.exe shell:appsFolder\$($Context.App.AppUserModelId)"
    Write-Host ""
    Write-Host "  Download cache: $($Context.DownloadDir)"
}

function Start-CodexOfflineInstall {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $AppManifest,

        [Parameter(Mandatory = $true)]
        [string] $DownloadDir,

        [Parameter(Mandatory = $true)]
        [string] $Ring,

        [Parameter(Mandatory = $true)]
        [int] $DownloadRetries,

        [switch] $Force,

        [switch] $DownloadOnly,

        [switch] $NoPause
    )

    $context = @{
        App             = $AppManifest
        DownloadDir     = $DownloadDir
        Ring            = $Ring
        DownloadRetries = [math]::Max($DownloadRetries, 1)
        Force           = [bool]$Force
        DownloadOnly    = [bool]$DownloadOnly
        NoPause         = [bool]$NoPause
    }

    Write-InstallerBanner -Context $context

    $architecture = Resolve-StoreArchitecture
    Write-Host "[*] System architecture: $architecture"
    Write-Host "[*] Release ring: $Ring"
    Write-Host "[*] Download cache: $DownloadDir"

    Ensure-Directory -Path $DownloadDir

    Write-InstallerSection -Index 1 -Total 4 -Message "Fetching Store package metadata"
    $packages = Invoke-StorePackageQuery -App $AppManifest -Ring $Ring
    Write-Host "    Found $($packages.Count) packages"

    Write-InstallerSection -Index 2 -Total 4 -Message "Selecting Codex packages"
    $packageSet = Select-CodexPackageSet -App $AppManifest -Packages $packages -Architecture $architecture
    Write-PackageSetSummary -PackageSet $packageSet

    $installedPackage = Get-InstalledAppPackage -App $AppManifest
    $latestVersion = Get-StorePackageVersion $packageSet.MainPackage.name
    if ($installedPackage) {
        Write-Host "    Installed version: $($installedPackage.Version)"
    }

    if ($installedPackage -and !$Force -and ([version]$installedPackage.Version -eq $latestVersion)) {
        Write-Host ""
        Write-Host "    [OK] ChatGPT Codex is already up to date. Use -Force to reinstall." -ForegroundColor Green
        return
    }

    Write-InstallerSection -Index 3 -Total 4 -Message "Downloading package files"
    Save-SelectedPackages -Context $context -PackageSet $packageSet

    if ($DownloadOnly) {
        Write-Host ""
        Write-Host "    [OK] Download complete. Installation skipped because -DownloadOnly was set." -ForegroundColor Green
        return
    }

    Write-InstallerSection -Index 4 -Total 4 -Message "Installing ChatGPT Codex"
    Install-CodexPackageSet -Context $context -PackageSet $packageSet -InstalledPackage $installedPackage
    Write-InstalledPackageSummary -Context $context
}

Export-ModuleMember -Function Start-CodexOfflineInstall

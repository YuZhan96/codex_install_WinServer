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

function Get-ChecksumPath {
    param([hashtable] $Context)

    return Join-Path $Context.DownloadDir "checksums.json"
}

function Read-ChecksumIndex {
    param([hashtable] $Context)

    $path = Get-ChecksumPath -Context $Context
    if (!(Test-Path $path)) {
        return @{}
    }

    try {
        $raw = Get-Content -Raw -Path $path
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @{}
        }

        $parsed = $raw | ConvertFrom-Json
        $index = @{}
        foreach ($property in $parsed.PSObject.Properties) {
            $index[$property.Name] = [string]$property.Value
        }
        return $index
    }
    catch {
        return @{}
    }
}

function Write-ChecksumIndex {
    param(
        [hashtable] $Context,
        [hashtable] $Index
    )

    $path = Get-ChecksumPath -Context $Context
    $Index | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding utf8
}

function Get-FileSha256 {
    param([string] $Path)

    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToUpperInvariant()
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
        [string] $Path,
        [hashtable] $ChecksumIndex
    )

    if (!(Test-Path $Path)) {
        return $false
    }

    if ((Get-Item $Path).Length -ne $Package.size) {
        return $false
    }

    $cachedHash = $ChecksumIndex[$Package.name]
    if ([string]::IsNullOrWhiteSpace($cachedHash)) {
        return $true
    }

    return ((Get-FileSha256 -Path $Path) -eq $cachedHash)
}

function Save-StorePackage {
    param(
        [hashtable] $Context,
        $Package,
        [hashtable] $ChecksumIndex
    )

    $outputPath = Get-PackageCachePath -Context $Context -Package $Package
    if (Test-PackageCache -Package $Package -Path $outputPath -ChecksumIndex $ChecksumIndex) {
        Write-Host "    [OK] Cached: $($Package.name)" -ForegroundColor Green
        return
    }

    $packageUrl = ConvertFrom-HtmlEncodedText $Package.url

    for ($attempt = 1; $attempt -le $Context.DownloadRetries; $attempt++) {
        try {
            Write-Host "    Downloading: $($Package.name)"
            Write-Host "    Size: $([math]::Round($Package.size / 1MB, 2)) MB, attempt $attempt of $($Context.DownloadRetries)"

            $request = [System.Net.HttpWebRequest]::Create($packageUrl)
            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()
            $fileStream = [System.IO.File]::Open($outputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $buffer = New-Object byte[] 81920
            $totalRead = 0L

            try {
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $fileStream.Write($buffer, 0, $read)
                    $totalRead += $read

                    if ($Package.size -gt 0) {
                        $percent = [math]::Min([math]::Round(($totalRead / [double]$Package.size) * 100, 0), 100)
                        Write-Progress -Activity "Downloading $($Package.name)" -Status "$([math]::Round($totalRead / 1MB, 2)) MB / $([math]::Round($Package.size / 1MB, 2)) MB" -PercentComplete $percent
                    }
                }
            }
            finally {
                Write-Progress -Activity "Downloading $($Package.name)" -Completed
                $fileStream.Dispose()
                $stream.Dispose()
                $response.Dispose()
            }

            if (!(Test-PackageCache -Package $Package -Path $outputPath -ChecksumIndex $ChecksumIndex)) {
                $actualSize = 0
                if (Test-Path $outputPath) {
                    $actualSize = (Get-Item $outputPath).Length
                }

                throw "Downloaded file size mismatch. Expected $($Package.size), got $actualSize."
            }

            $ChecksumIndex[$Package.name] = (Get-FileSha256 -Path $outputPath)
            Write-ChecksumIndex -Context $Context -Index $ChecksumIndex
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

    $checksumIndex = Read-ChecksumIndex -Context $Context
    $orderedPackages = @($PackageSet.Dependencies) + @($PackageSet.MainPackage)
    foreach ($package in $orderedPackages) {
        Save-StorePackage -Context $Context -Package $package -ChecksumIndex $checksumIndex
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

function Write-InstallPlan {
    param(
        [hashtable] $Context,
        $PackageSet,
        $InstalledPackage
    )

    Write-Host ""
    Write-Host "Plan:" -ForegroundColor Cyan
    Write-Host "  App: $($Context.App.Name)"
    Write-Host "  Architecture: $(Resolve-StoreArchitecture)"
    Write-Host "  Manifest: $($Context.ManifestPath)"
    Write-Host "  Download cache: $($Context.DownloadDir)"
    Write-Host "  Main package: $($PackageSet.MainPackage.name)"
    Write-Host "  Dependencies: $($PackageSet.Dependencies.Count)"

    if ($InstalledPackage) {
        Write-Host "  Installed version: $($InstalledPackage.Version)"
    }

    Write-Host "  Actions:"
    Write-Host "    1. Query Store package metadata"
    Write-Host "    2. Select matching packages"
    Write-Host "    3. Download or reuse cached packages"
    Write-Host "    4. Close running app process if needed"
    Write-Host "    5. Remove installed version if present"
    Write-Host "    6. Install dependencies"
    Write-Host "    7. Install main package"
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
        [string] $ManifestPath,

        [Parameter(Mandatory = $true)]
        [string] $DownloadDir,

        [Parameter(Mandatory = $true)]
        [string] $Ring,

        [Parameter(Mandatory = $true)]
        [int] $DownloadRetries,

        [switch] $Force,

        [switch] $DownloadOnly,

        [switch] $PlanOnly,

        [switch] $NoPause
    )

    $context = @{
        App             = $AppManifest
        ManifestPath    = $ManifestPath
        DownloadDir     = $DownloadDir
        Ring            = $Ring
        DownloadRetries = [math]::Max($DownloadRetries, 1)
        Force           = [bool]$Force
        DownloadOnly    = [bool]$DownloadOnly
        PlanOnly        = [bool]$PlanOnly
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

    if ($PlanOnly) {
        Write-InstallerSection -Index 3 -Total 4 -Message "Previewing install plan"
        Write-InstallPlan -Context $context -PackageSet $packageSet -InstalledPackage $installedPackage
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

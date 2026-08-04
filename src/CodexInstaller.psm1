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

function Get-InstallManifestPath {
    param([hashtable] $Context)

    return Join-Path $Context.DownloadDir "install-manifest.json"
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
            if ($property.Value -is [string]) {
                $index[$property.Name] = [pscustomobject]@{
                    Sha256 = $property.Value
                    Size   = $null
                }
            }
            else {
                $index[$property.Name] = [pscustomobject]@{
                    Sha256 = [string]$property.Value.sha256
                    Size   = $property.Value.size
                }
            }
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
    $serializable = @{}
    foreach ($key in $Index.Keys) {
        $entry = $Index[$key]
        $serializable[$key] = @{
            sha256 = [string]$entry.Sha256
            size   = $entry.Size
        }
    }

    $serializable | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding utf8
}

function Set-ChecksumEntry {
    param(
        [hashtable] $Index,
        $Package,
        [string] $Hash
    )

    $Index[$Package.name] = [pscustomobject]@{
        Sha256 = $Hash.ToUpperInvariant()
        Size   = [int64]$Package.size
    }
}

function Get-ChecksumEntry {
    param(
        [hashtable] $Index,
        $Package
    )

    $entry = $Index[$Package.name]
    if (!$entry) {
        return $null
    }

    if ($entry -is [string]) {
        return [string]$entry
    }

    return [string]$entry.Sha256
}

function Get-ExpectedPackageHash {
    param($Package)

    foreach ($propertyName in @("sha256", "sha256Hash", "hash", "digest")) {
        $property = $Package.PSObject.Properties[$propertyName]
        if ($property -and $property.Value) {
            return ([string]$property.Value -replace "^SHA256:", "").ToUpperInvariant()
        }
    }

    return $null
}

function Get-FileSha256 {
    param(
        [string] $Path,
        [string] $Label = "file"
    )

    Write-Host "    Calculating SHA256: $Label"

    $stream = [System.IO.File]::OpenRead($Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $buffer = New-Object byte[] 1048576
    $totalRead = 0L
    $totalSize = $stream.Length

    try {
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            [void]$sha256.TransformBlock($buffer, 0, $read, $buffer, 0)
            $totalRead += $read

            if ($totalSize -gt 0) {
                $percent = [math]::Min([math]::Round(($totalRead / [double]$totalSize) * 100, 0), 100)
                Write-Progress -Activity "Hashing $Label" -Status "$([math]::Round($totalRead / 1MB, 2)) MB / $([math]::Round($totalSize / 1MB, 2)) MB" -PercentComplete $percent
            }
        }

        [void]$sha256.TransformFinalBlock($buffer, 0, 0)
        return ([BitConverter]::ToString($sha256.Hash) -replace "-", "").ToUpperInvariant()
    }
    finally {
        Write-Progress -Activity "Hashing $Label" -Completed
        $sha256.Dispose()
        $stream.Dispose()
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

function Get-PackageCacheState {
    param(
        $Package,
        [string] $Path,
        [hashtable] $ChecksumIndex,
        [switch] $RequireChecksum
    )

    $state = [ordered]@{
        Exists       = $false
        SizeMatches  = $false
        HashRecorded = $false
        HashMatches  = $null
        Valid        = $false
        ActualSize   = 0L
        ActualHash   = $null
    }

    if (!(Test-Path $Path)) {
        return [pscustomobject]$state
    }

    $state.Exists = $true
    $state.ActualSize = (Get-Item $Path).Length
    $state.SizeMatches = ($state.ActualSize -eq $Package.size)
    if (!$state.SizeMatches) {
        return [pscustomobject]$state
    }

    $cachedHash = Get-ChecksumEntry -Index $ChecksumIndex -Package $Package
    $expectedHash = Get-ExpectedPackageHash -Package $Package
    if ([string]::IsNullOrWhiteSpace($cachedHash) -and [string]::IsNullOrWhiteSpace($expectedHash)) {
        $state.Valid = (-not $RequireChecksum)
        return [pscustomobject]$state
    }

    $state.HashRecorded = $true
    Write-Host "    Verifying SHA256: $($Package.name)"
    $state.ActualHash = Get-FileSha256 -Path $Path -Label $Package.name
    $comparisonHash = if ($cachedHash) { $cachedHash } else { $expectedHash }
    $state.HashMatches = ($state.ActualHash -eq $comparisonHash.ToUpperInvariant())
    $state.Valid = $state.HashMatches
    return [pscustomobject]$state
}

function Save-StorePackage {
    param(
        [hashtable] $Context,
        $Package,
        [hashtable] $ChecksumIndex
    )

    $outputPath = Get-PackageCachePath -Context $Context -Package $Package
    $cacheState = Get-PackageCacheState -Package $Package -Path $outputPath -ChecksumIndex $ChecksumIndex
    if ($cacheState.Valid) {
        if (!(Get-ChecksumEntry -Index $ChecksumIndex -Package $Package)) {
            $hash = $cacheState.ActualHash
            if ([string]::IsNullOrWhiteSpace($hash)) {
                $hash = Get-FileSha256 -Path $outputPath -Label $Package.name
            }

            Set-ChecksumEntry -Index $ChecksumIndex -Package $Package -Hash $hash
            Write-ChecksumIndex -Context $Context -Index $ChecksumIndex
        }

        Write-Host "    [OK] Cached: $($Package.name)" -ForegroundColor Green
        return
    }

    if ($cacheState.Exists) {
        if (!$cacheState.SizeMatches) {
            Write-Host "    [WARN] Cached file size mismatch. Re-downloading: $($Package.name)" -ForegroundColor Yellow
        }
        elseif ($cacheState.HashMatches -eq $false) {
            Write-Host "    [WARN] Cached SHA256 mismatch. Re-downloading: $($Package.name)" -ForegroundColor Yellow
        }
        else {
            Write-Host "    [WARN] Cached package has no trusted checksum. Re-downloading: $($Package.name)" -ForegroundColor Yellow
        }
    }

    $packageUrl = ConvertFrom-HtmlEncodedText $Package.url

    for ($attempt = 1; $attempt -le $Context.DownloadRetries; $attempt++) {
        try {
            Write-Host "    Downloading: $($Package.name)"
            Write-Host "    Size: $([math]::Round($Package.size / 1MB, 2)) MB, attempt $attempt of $($Context.DownloadRetries)"

            $request = [System.Net.HttpWebRequest]::Create($packageUrl)
            $request.Timeout = 30000
            $request.ReadWriteTimeout = 30000
            $request.UserAgent = "codex_install_WinServer/1.0"

            $response = $null
            $stream = $null
            $fileStream = $null
            try {
                $response = $request.GetResponse()
                $stream = $response.GetResponseStream()
                $fileStream = [System.IO.File]::Open($outputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $buffer = New-Object byte[] 81920
                $totalRead = 0L

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
                if ($fileStream) {
                    $fileStream.Dispose()
                }
                if ($stream) {
                    $stream.Dispose()
                }
                if ($response) {
                    $response.Dispose()
                }
            }

            Write-Host "    Download stream closed. Verifying file..."
            if (!(Test-Path $outputPath) -or (Get-Item $outputPath).Length -ne $Package.size) {
                $actualSize = 0
                if (Test-Path $outputPath) {
                    $actualSize = (Get-Item $outputPath).Length
                }

                throw "Downloaded file size mismatch. Expected $($Package.size), got $actualSize."
            }

            $actualHash = Get-FileSha256 -Path $outputPath -Label $Package.name
            $expectedHash = Get-ExpectedPackageHash -Package $Package
            if ($expectedHash -and $actualHash -ne $expectedHash) {
                throw "Downloaded SHA256 mismatch for $($Package.name). Expected $expectedHash, got $actualHash."
            }

            Set-ChecksumEntry -Index $ChecksumIndex -Package $Package -Hash $actualHash
            Write-ChecksumIndex -Context $Context -Index $ChecksumIndex
            Write-Host "    [OK] SHA256 verified: $($actualHash.Substring(0, 16))..." -ForegroundColor Green
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
        $PackageSet,
        [string] $Architecture
    )

    $checksumIndex = Read-ChecksumIndex -Context $Context
    $orderedPackages = @($PackageSet.Dependencies) + @($PackageSet.MainPackage)
    foreach ($package in $orderedPackages) {
        Save-StorePackage -Context $Context -Package $package -ChecksumIndex $checksumIndex
    }

    Write-InstallManifest -Context $Context -PackageSet $PackageSet -Architecture $Architecture
}

function Convert-PackageToManifestRecord {
    param($Package)

    return [ordered]@{
        name    = [string]$Package.name
        size    = [int64]$Package.size
        arch    = [string]$Package.arch
        version = [string](Get-StorePackageVersion $Package.name)
    }
}

function Write-InstallManifest {
    param(
        [hashtable] $Context,
        $PackageSet,
        [string] $Architecture
    )

    $manifest = [ordered]@{
        schemaVersion   = 1
        appName         = [string]$Context.App.Name
        packageName     = [string]$Context.App.PackageName
        architecture    = $Architecture
        ring            = $Context.Ring
        createdAt       = (Get-Date).ToUniversalTime().ToString("o")
        mainPackage     = Convert-PackageToManifestRecord -Package $PackageSet.MainPackage
        dependencies    = @($PackageSet.Dependencies | ForEach-Object {
            Convert-PackageToManifestRecord -Package $_
        })
    }

    $path = Get-InstallManifestPath -Context $Context
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding utf8
    Write-Host "    [OK] Install manifest written: $path" -ForegroundColor Green
}

function Read-InstallManifest {
    param([hashtable] $Context)

    $path = Get-InstallManifestPath -Context $Context
    if (!(Test-Path $path)) {
        throw "Install manifest not found: $path. Run -DownloadOnly first."
    }

    try {
        $manifest = Get-Content -Raw -Path $path | ConvertFrom-Json
    }
    catch {
        throw "Install manifest is not valid JSON: $path"
    }

    if ($manifest.schemaVersion -ne 1) {
        throw "Unsupported install manifest schema: $($manifest.schemaVersion)"
    }

    if ($manifest.packageName -ne $Context.App.PackageName) {
        throw "Install manifest belongs to '$($manifest.packageName)', not '$($Context.App.PackageName)'."
    }

    if (!$manifest.mainPackage -or !$manifest.mainPackage.name) {
        throw "Install manifest does not contain a main package."
    }

    return $manifest
}

function Convert-InstallManifestToPackageSet {
    param($Manifest)

    $mainPackage = [pscustomobject]@{
        name = [string]$Manifest.mainPackage.name
        size = [int64]$Manifest.mainPackage.size
        arch = [string]$Manifest.mainPackage.arch
    }

    $dependencies = @($Manifest.dependencies | ForEach-Object {
        [pscustomobject]@{
            name = [string]$_.name
            size = [int64]$_.size
            arch = [string]$_.arch
        }
    })

    return [pscustomobject]@{
        MainPackage  = $mainPackage
        Dependencies = $dependencies
    }
}

function Assert-PackageSetReady {
    param(
        [hashtable] $Context,
        $PackageSet
    )

    $checksumIndex = Read-ChecksumIndex -Context $Context
    $orderedPackages = @($PackageSet.Dependencies) + @($PackageSet.MainPackage)

    foreach ($package in $orderedPackages) {
        $path = Get-PackageCachePath -Context $Context -Package $package
        $state = Get-PackageCacheState -Package $package -Path $path `
            -ChecksumIndex $checksumIndex -RequireChecksum

        if (!$state.Exists) {
            throw "Required package is missing from cache: $path"
        }

        if (!$state.SizeMatches) {
            throw "Cached package size mismatch: $($package.name)"
        }

        if ($state.HashMatches -ne $true) {
            throw "Cached package SHA256 validation failed: $($package.name)"
        }

        Write-Host "    [OK] Cache verified: $($package.name)" -ForegroundColor Green
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

        $identityName = ($Package.name -split "_")[0]
        $existingPackage = Get-AppxPackage -Name $identityName -ErrorAction SilentlyContinue
        if ($existingPackage) {
            Write-Host "    [SKIP] Dependency already installed: $($Package.name)" -ForegroundColor DarkGray
            return
        }

        throw "Dependency installation failed for $($Package.name): $($_.Exception.Message)"
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
    if ($Context.InstallOnly) {
        Write-Host "    1. Load offline install manifest"
        Write-Host "    2. Validate cached package files"
    }
    else {
        Write-Host "    1. Query Store package metadata"
        Write-Host "    2. Select matching packages"
        Write-Host "    3. Download or reuse cached packages"
    }
    Write-Host "    4. Close running app process if needed"
    Write-Host "    5. Remove installed version if present"
    Write-Host "    6. Install dependencies"
    Write-Host "    7. Install main package"
}

function Write-InstalledPackageSummary {
    param(
        [hashtable] $Context,
        $ExpectedPackage
    )

    $package = Get-InstalledAppPackage -App $Context.App
    if (!$package) {
        throw "Installation finished, but the app package was not found."
    }

    $expectedVersion = Get-StorePackageVersion $ExpectedPackage.name
    if ($expectedVersion -and ([version]$package.Version -ne $expectedVersion)) {
        throw "Installation verification failed. Expected version $expectedVersion, found $($package.Version)."
    }

    Write-Host "    [OK] Installation verified: $($package.Name) $($package.Version)" -ForegroundColor Green
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

        [switch] $InstallOnly,

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
        InstallOnly     = [bool]$InstallOnly
        PlanOnly        = [bool]$PlanOnly
        NoPause         = [bool]$NoPause
    }

    Write-InstallerBanner -Context $context

    $architecture = Resolve-StoreArchitecture
    Write-Host "[*] System architecture: $architecture"
    Write-Host "[*] Release ring: $Ring"
    Write-Host "[*] Download cache: $DownloadDir"

    Ensure-Directory -Path $DownloadDir

    if ($InstallOnly) {
        Write-InstallerSection -Index 1 -Total 4 -Message "Loading offline install manifest"
        $offlineManifest = Read-InstallManifest -Context $context
        if ($offlineManifest.architecture -ne $architecture) {
            throw "Offline manifest architecture '$($offlineManifest.architecture)' does not match this system '$architecture'."
        }

        $packageSet = Convert-InstallManifestToPackageSet -Manifest $offlineManifest
        Write-Host "    Loaded package manifest created at $($offlineManifest.createdAt)"

        Write-InstallerSection -Index 2 -Total 4 -Message "Selecting cached Codex packages"
        Write-PackageSetSummary -PackageSet $packageSet
        $installedPackage = Get-InstalledAppPackage -App $AppManifest

        if ($PlanOnly) {
            Write-InstallerSection -Index 3 -Total 4 -Message "Previewing offline install plan"
            Write-InstallPlan -Context $context -PackageSet $packageSet -InstalledPackage $installedPackage
            return
        }

        Write-InstallerSection -Index 3 -Total 4 -Message "Validating cached package files"
        Assert-PackageSetReady -Context $context -PackageSet $packageSet

        Write-InstallerSection -Index 4 -Total 4 -Message "Installing ChatGPT Codex from cache"
        Install-CodexPackageSet -Context $context -PackageSet $packageSet -InstalledPackage $installedPackage
        Write-InstalledPackageSummary -Context $context -ExpectedPackage $packageSet.MainPackage
        return
    }

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

    if ($installedPackage -and !$Force -and !$DownloadOnly -and !$PlanOnly -and
        ([version]$installedPackage.Version -eq $latestVersion)) {
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
    Save-SelectedPackages -Context $context -PackageSet $packageSet -Architecture $architecture

    if ($DownloadOnly) {
        Write-Host ""
        Write-Host "    [OK] Download complete and package set verified." -ForegroundColor Green
        Write-Host "    [OK] Installation skipped because -DownloadOnly was set." -ForegroundColor Green
        Write-Host "    Run with -InstallOnly to install from this cache." -ForegroundColor Cyan
        return
    }

    Write-InstallerSection -Index 4 -Total 4 -Message "Installing ChatGPT Codex"
    Install-CodexPackageSet -Context $context -PackageSet $packageSet -InstalledPackage $installedPackage
    Write-InstalledPackageSummary -Context $context -ExpectedPackage $packageSet.MainPackage
}

Export-ModuleMember -Function Start-CodexOfflineInstall

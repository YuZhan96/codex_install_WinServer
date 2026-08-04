# codex_install_WinServer

[中文文档](README.zh.md)

🚀 Offline installer for the ChatGPT Codex desktop app on Windows environments where Microsoft Store is unavailable or impractical, especially Windows Server, stripped-down Windows images, and restricted enterprise machines.

Repository:

https://github.com/YuZhan96/codex_install_WinServer

## 🎯 Purpose

This project focuses on installing the ChatGPT Codex desktop app on Windows Server. It does not redistribute, modify, crack, or repackage the Codex app itself. The installer resolves Microsoft Store package metadata, selects the matching Codex MSIX package and dependencies for the current CPU architecture, then installs them through the native Windows Appx/MSIX tooling.

The code is written in English for easier maintenance and review. A Chinese README is provided separately for Chinese users.

Although this repository is maintained for ChatGPT Codex, the structure can also be used as a template for other Microsoft Store / MSIX apps. To adapt it, replace the app manifest, package matching rules, process name, launch entry, and dependency selection logic as needed.

## ✨ Features

- Detects x64, x86, and ARM64 Windows architectures
- Queries Microsoft Store package metadata for ChatGPT Codex
- Selects the matching main package for the current architecture
- Downloads architecture-compatible dependencies
- Validates cached package size before reuse
- Retries failed downloads
- Checks the installed version before reinstalling
- Supports forced reinstall
- Supports download-only mode
- Supports install-only mode from a verified local cache
- Supports preview mode with `-PlanOnly`
- Supports alternate manifests with `-Manifest`
- Shows download progress for large packages
- Verifies cached packages with SHA256
- Writes an install manifest for repeatable offline installation
- Closes the running Codex process before installation
- Uses standard `Add-AppxPackage` and `Remove-AppxPackage` flows

## 🧩 Project Structure

```text
codex_install_WinServer/
|-- Codex_Installer.ps1       # Thin entry script
|-- config/
|   `-- codex.app.psd1        # Codex-specific app manifest
|-- src/
|   `-- CodexInstaller.psm1   # Installer workflow module
|-- README.md                 # English documentation
|-- README.zh.md              # Chinese documentation
|-- LICENSE
`-- winget/                   # Dependency metadata and auxiliary files
```

Downloaded package files are cached in `downloads/` by default. This directory is ignored by Git; large installer packages should not be committed to the repository.

The cache also contains:

- `install-manifest.json`: the selected main package, dependencies, architecture, and release ring
- `checksums.json`: SHA256 and size records for each downloaded package

## ✅ Requirements

- Windows 10 17763 or later
- Windows 11
- Windows Server 2019 or later
- PowerShell 5.1 or later
- Administrator privileges

## ⚡ Quick Start

Open PowerShell as Administrator, enter the project directory, then run:

```powershell
.\Codex_Installer.ps1
```

If script execution is blocked, run this in the current PowerShell session first:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then run the installer again.

## 🛠️ Options

```powershell
.\Codex_Installer.ps1 -DownloadOnly
```

Downloads the Codex main package and dependencies without installing them.

A verified `downloads/install-manifest.json` and `downloads/checksums.json` are written for the next step.

```powershell
.\Codex_Installer.ps1 -InstallOnly
```

Installs only from the previously downloaded cache. This mode does not query the network; it validates every package size and SHA256 value before installing.

```powershell
.\Codex_Installer.ps1 -Force
```

Runs the install flow even if the installed version already matches the latest resolved package.

```powershell
.\Codex_Installer.ps1 -NoPause
```

Skips the final "Press Enter to exit" prompt. This is useful for automation.

```powershell
.\Codex_Installer.ps1 -Ring Retail -DownloadRetries 5
```

Sets the Store release ring and download retry count.

```powershell
.\Codex_Installer.ps1 -Manifest .\config\codex.app.psd1 -PlanOnly
```

Loads a specific manifest and prints the install plan without changing the system.

### Download Then Install

For a two-stage workflow on a server with restricted network access:

```powershell
# Stage 1: resolve and download packages
.\Codex_Installer.ps1 -DownloadOnly -NoPause

# Stage 2: verify the local cache and install
.\Codex_Installer.ps1 -InstallOnly -NoPause
```

The download stage must finish successfully before `-InstallOnly` can run. Do not delete `install-manifest.json`, `checksums.json`, or any package file from `downloads/`.

## 📦 Codex App Manifest

Codex-specific values live in `config/codex.app.psd1`:

| Key | Current value | Description |
| --- | --- | --- |
| `PackageName` | `OpenAI.Codex` | Windows app package name |
| `PackageNamePrefix` | `OpenAI.Codex_` | Store package file prefix |
| `ProcessName` | `OpenAI.Codex` | Process to close before installation |
| `StoreUrl` | Codex Microsoft Store URL | Target Store page |
| `PackageApiUrl` | Store package metadata endpoint | Used to resolve offline packages |
| `AppUserModelId` | Codex app launch entry | Used in the final launch command |

Most users do not need to edit these values.

## 🔁 Adapting The Idea To Other Apps

This repository is maintained for ChatGPT Codex, but the modular layout makes the idea reusable. A practical migration usually looks like this:

1. Find the target app page on Microsoft Store and copy its URL.
2. Copy `config/codex.app.psd1` to a new manifest file, for example `config/example.app.psd1`.
3. Replace `StoreUrl` with the target Store URL.
4. Replace `PackageName` with the target app package name shown by `Get-AppxPackage`.
5. Replace `PackageNamePrefix` with the filename prefix used by the Store package list.
6. Replace `ProcessName` if the app needs to be closed before updating.
7. Replace `AppUserModelId` if you want the final launch command to be accurate.
8. If the target app uses unusual package names, adjust `Select-CodexPackageSet` in `src/CodexInstaller.psm1`.
9. Launch the installer with `-Manifest .\config\example.app.psd1` so the same code path can target the new app.

Example manifest shape:

```powershell
@{
    Name              = "Example Store App"
    PackageName       = "Vendor.ExampleApp"
    PackageNamePrefix = "Vendor.ExampleApp_"
    ProcessName       = "ExampleApp"
    StoreUrl          = "https://apps.microsoft.com/detail/EXAMPLEID"
    PackageApiUrl     = "https://store.uihtm.com/api/packages"
    AppUserModelId    = "Vendor.ExampleApp_abc123!App"
}
```

After creating a new manifest, the entry script can be adjusted to load that manifest instead of `config/codex.app.psd1`. Package naming, dependencies, architecture markers, and launch entries vary between apps, so confirm the target package list before adapting the installer.

## ⚠️ Notes

- This project is not affiliated with OpenAI or Microsoft
- ChatGPT Codex belongs to its respective rights holder
- This project does not provide or modify the Codex app itself
- Download URLs may expire; rerun the script to resolve fresh URLs
- Windows 7 is not supported because it does not support the required MSIX install flow

## 📄 License

MIT License

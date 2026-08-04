# codex_install_WinServer

[中文文档](README.zh.md)

Offline installer for the ChatGPT Codex desktop app on Windows environments where Microsoft Store is unavailable or impractical, especially Windows Server, stripped-down Windows images, and restricted enterprise machines.

Repository:

https://github.com/YuZhan96/codex_install_WinServer

## Purpose

This project focuses on installing the ChatGPT Codex desktop app on Windows Server. It does not redistribute, modify, crack, or repackage the Codex app itself. The installer resolves Microsoft Store package metadata, selects the matching Codex MSIX package and dependencies for the current CPU architecture, then installs them through the native Windows Appx/MSIX tooling.

The code is written in English for easier maintenance and review. A Chinese README is provided separately for Chinese users.

Although this repository is maintained for ChatGPT Codex, the structure can also be used as a template for other Microsoft Store / MSIX apps. To adapt it, replace the app manifest, package matching rules, process name, launch entry, and dependency selection logic as needed.

## Features

- Detects x64, x86, and ARM64 Windows architectures
- Queries Microsoft Store package metadata for ChatGPT Codex
- Selects the matching main package for the current architecture
- Downloads architecture-compatible dependencies
- Validates cached package size before reuse
- Retries failed downloads
- Checks the installed version before reinstalling
- Supports forced reinstall
- Supports download-only mode
- Closes the running Codex process before installation
- Uses standard `Add-AppxPackage` and `Remove-AppxPackage` flows

## Requirements

- Windows 10 17763 or later
- Windows 11
- Windows Server 2019 or later
- PowerShell 5.1 or later
- Administrator privileges

## Quick Start

Open PowerShell as Administrator, enter the project directory, then run:

```powershell
.\Codex_Installer.ps1
```

If script execution is blocked, run this in the current PowerShell session first:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then run the installer again.

## Options

```powershell
.\Codex_Installer.ps1 -DownloadOnly
```

Downloads the Codex main package and dependencies without installing them.

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

## Project Structure

```text
codex_install_WinServer/
├── Codex_Installer.ps1       # Thin entry script
├── config/
│   └── codex.app.psd1        # Codex-specific app manifest
├── src/
│   └── CodexInstaller.psm1   # Installer workflow module
├── README.md                 # English documentation
├── README.zh.md              # Chinese documentation
├── LICENSE
└── winget/                   # Dependency metadata and auxiliary files
```

Downloaded package files are cached in `downloads/` by default. This directory is ignored by Git; large installer packages should not be committed to the repository.

## Codex App Manifest

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

## Adapting To Other Apps

This repository is maintained for ChatGPT Codex. If you want to adapt the structure for another Microsoft Store / MSIX app, review these replacement points:

- Change `StoreUrl`
- Change `PackageName` and `PackageNamePrefix`
- Adjust main package selection rules if the target app uses a different naming pattern
- Change `ProcessName`
- Change `AppUserModelId`
- Adjust dependency filtering if the target app has special package requirements

Package naming, dependencies, architecture markers, and launch entries vary between apps. Confirm the target package list before adapting the installer.

## Notes

- This project is not affiliated with OpenAI or Microsoft
- ChatGPT Codex belongs to its respective rights holder
- This project does not provide or modify the Codex app itself
- Download URLs may expire; rerun the script to resolve fresh URLs
- Windows 7 is not supported because it does not support the required MSIX install flow

## License

MIT License

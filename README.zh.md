# codex_install_WinServer

[English README](README.md)

用于在没有 Microsoft Store 或不适合使用 Microsoft Store 的 Windows 环境中安装 ChatGPT Codex 桌面版，主要面向 Windows Server、精简系统、受限企业环境等场景。

远程仓库：

https://github.com/YuZhan96/codex_install_WinServer

## 项目定位

本项目专注于 ChatGPT Codex 桌面版在 Windows Server 环境中的安装，不重新分发、修改、破解或重新打包 Codex 应用本体。安装器会解析 Microsoft Store 包信息，选择当前 CPU 架构对应的 Codex MSIX 主包与依赖包，然后通过 Windows 原生 Appx/MSIX 工具完成安装。

代码本身使用英文，方便维护、审查和继续扩展。中文文档单独提供，便于中文用户快速使用。

虽然本仓库默认维护 ChatGPT Codex 的安装逻辑，但这个结构也可以作为其他 Microsoft Store / MSIX 软件的安装模板。适配其他软件时，需要替换应用清单、包匹配规则、进程名、启动入口和依赖筛选逻辑。

## 主要功能

- 自动识别 x64、x86、ARM64 Windows 架构
- 查询 ChatGPT Codex 的 Microsoft Store 包信息
- 选择当前架构匹配的主包
- 下载当前架构可用的依赖包
- 复用缓存前校验文件大小
- 支持下载失败重试
- 安装前检查已安装版本
- 支持强制重装
- 支持只下载不安装
- 安装前关闭正在运行的 Codex 进程
- 使用标准 `Add-AppxPackage` 和 `Remove-AppxPackage` 流程

## 系统要求

- Windows 10 17763 及以上
- Windows 11
- Windows Server 2019 及以上
- PowerShell 5.1 或更高版本
- 管理员权限

## 快速使用

以管理员身份打开 PowerShell，进入项目目录后运行：

```powershell
.\Codex_Installer.ps1
```

如果系统阻止脚本执行，可以先在当前 PowerShell 会话中运行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

然后再次执行安装脚本。

## 常用参数

```powershell
.\Codex_Installer.ps1 -DownloadOnly
```

只下载 Codex 主包和依赖包，不执行安装。

```powershell
.\Codex_Installer.ps1 -Force
```

即使当前已安装版本和解析到的最新版本一致，也执行安装流程。

```powershell
.\Codex_Installer.ps1 -NoPause
```

脚本结束时不等待用户按回车，适合自动化环境。

```powershell
.\Codex_Installer.ps1 -Ring Retail -DownloadRetries 5
```

指定 Store 发布通道和下载重试次数。

## 项目结构

```text
codex_install_WinServer/
├── Codex_Installer.ps1       # 轻量入口脚本
├── config/
│   └── codex.app.psd1        # Codex 专用应用清单
├── src/
│   └── CodexInstaller.psm1   # 安装流程模块
├── README.md                 # 英文文档
├── README.zh.md              # 中文文档
├── LICENSE
└── winget/                   # 依赖信息与辅助文件
```

下载文件默认缓存在 `downloads/` 目录。该目录已被 Git 忽略，不建议把大型安装包提交到仓库。

## Codex 应用清单

Codex 专用配置位于 `config/codex.app.psd1`：

| 配置 | 当前值 | 说明 |
| --- | --- | --- |
| `PackageName` | `OpenAI.Codex` | Windows 应用包名 |
| `PackageNamePrefix` | `OpenAI.Codex_` | Store 包文件名前缀 |
| `ProcessName` | `OpenAI.Codex` | 安装前需要关闭的进程名 |
| `StoreUrl` | Codex 的 Microsoft Store 链接 | 目标商店页面 |
| `PackageApiUrl` | Store 包信息接口 | 用于解析离线安装包 |
| `AppUserModelId` | Codex 应用启动入口 | 用于安装完成后的启动命令 |

普通用户通常不需要修改这些配置。

## 适配其他软件

本仓库默认维护 ChatGPT Codex 安装逻辑。如果你想基于此结构适配其他 Microsoft Store / MSIX 软件，可以重点检查以下替换点：

- 修改 `StoreUrl`
- 修改 `PackageName` 和 `PackageNamePrefix`
- 如果目标软件包命名规则不同，调整主包选择逻辑
- 修改 `ProcessName`
- 修改 `AppUserModelId`
- 如果目标软件有特殊依赖，调整依赖筛选逻辑

不同软件的包命名、依赖关系、架构标记和启动入口可能不同。适配前建议先确认目标软件的包列表。

## 注意事项

- 本项目不隶属于 OpenAI 或 Microsoft
- ChatGPT Codex 的版权归其权利方所有
- 本项目不提供或修改 Codex 应用本体
- 下载链接可能具有时效性，过期后重新运行脚本即可重新获取
- Windows 7 不支持所需 MSIX 安装流程，因此不在支持范围内

## 许可证

MIT License

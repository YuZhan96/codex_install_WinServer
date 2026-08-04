# codex_install_WinServer

[English README](README.md)

🚀 用于在没有 Microsoft Store 或不适合使用 Microsoft Store 的 Windows 环境中安装 ChatGPT Codex 桌面版，主要面向 Windows Server、精简系统、受限企业环境等场景。

远程仓库：

https://github.com/YuZhan96/codex_install_WinServer

## 🎯 项目定位

本项目专注于 ChatGPT Codex 桌面版在 Windows Server 环境中的安装，不重新分发、修改、破解或重新打包 Codex 应用本体。安装器会解析 Microsoft Store 包信息，选择当前 CPU 架构对应的 Codex MSIX 主包与依赖包，然后通过 Windows 原生 Appx/MSIX 工具完成安装。

代码本身使用英文，方便维护、审查和继续扩展。中文文档单独提供，便于中文用户快速使用。

虽然本仓库默认维护 ChatGPT Codex 的安装逻辑，但这个结构也可以作为其他 Microsoft Store / MSIX 软件的安装模板。适配其他软件时，需要替换应用清单、包匹配规则、进程名、启动入口和依赖筛选逻辑。

## ✨ 主要功能

- 自动识别 x64、x86、ARM64 Windows 架构
- 查询 ChatGPT Codex 的 Microsoft Store 包信息
- 选择当前架构匹配的主包
- 下载当前架构可用的依赖包
- 复用缓存前校验文件大小
- 支持下载失败重试
- 安装前检查已安装版本
- 支持强制重装
- 支持只下载不安装
- 支持基于已验证缓存的只安装模式
- 支持 `-PlanOnly` 预览模式
- 支持 `-Manifest` 指定其他应用清单
- 下载大包时显示进度条
- 使用 SHA256 校验缓存文件
- 生成可重复使用的离线安装清单
- 安装前关闭正在运行的 Codex 进程
- 使用标准 `Add-AppxPackage` 和 `Remove-AppxPackage` 流程

## 🧩 项目结构

```text
codex_install_WinServer/
|-- Codex_Installer.ps1       # 轻量入口脚本
|-- config/
|   `-- codex.app.psd1        # Codex 专用应用清单
|-- src/
|   `-- CodexInstaller.psm1   # 安装流程模块
|-- README.md                 # 英文文档
|-- README.zh.md              # 中文文档
|-- LICENSE
`-- winget/                   # 依赖信息与辅助文件
```

下载文件默认缓存在 `downloads/` 目录。该目录已被 Git 忽略，不建议把大型安装包提交到仓库。

## ✅ 系统要求

- Windows 10 17763 及以上
- Windows 11
- Windows Server 2019 及以上
- PowerShell 5.1 或更高版本
- 管理员权限

## ⚡ 快速使用

以管理员身份打开 PowerShell，进入项目目录后运行：

```powershell
.\Codex_Installer.ps1
```

如果系统阻止脚本执行，可以先在当前 PowerShell 会话中运行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

然后再次执行安装脚本。

## 🛠️ 常用参数

```powershell
.\Codex_Installer.ps1 -DownloadOnly
```

只下载 Codex 主包和依赖包，不执行安装。

成功后会生成 `downloads/install-manifest.json` 和 `downloads/checksums.json`，供下一步使用。

```powershell
.\Codex_Installer.ps1 -InstallOnly
```

只使用之前下载的本地缓存进行安装。此模式不会访问网络，会在安装前校验每个包的文件大小和 SHA256。

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

```powershell
.\Codex_Installer.ps1 -Manifest .\config\codex.app.psd1 -PlanOnly
```

加载指定应用清单并仅预览安装计划，不修改系统。

### 下载后再安装

对于网络受限的服务器，可以分两步执行：

```powershell
# 第一步：解析并下载安装包
.\Codex_Installer.ps1 -DownloadOnly -NoPause

# 第二步：验证本地缓存并安装
.\Codex_Installer.ps1 -InstallOnly -NoPause
```

只有下载阶段成功结束后，`-InstallOnly` 才能运行。不要删除 `downloads/` 下的 `install-manifest.json`、`checksums.json` 或任何安装包文件。

## 📦 Codex 应用清单

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

## 🔁 举一反三：安装其他软件

本仓库默认维护 ChatGPT Codex，但模块化结构可以复用到其他 Microsoft Store / MSIX 软件。一个实际迁移流程通常是：

1. 打开目标软件的 Microsoft Store 页面，复制 Store 链接。
2. 复制 `config/codex.app.psd1`，例如改成 `config/example.app.psd1`。
3. 把 `StoreUrl` 替换成目标软件的 Store 链接。
4. 把 `PackageName` 替换成目标应用的 Windows 包名，可以通过 `Get-AppxPackage` 查询。
5. 把 `PackageNamePrefix` 替换成目标软件在 Store 包列表中的文件名前缀。
6. 如果安装或更新前需要关闭目标软件，替换 `ProcessName`。
7. 如果希望安装完成后显示准确启动命令，替换 `AppUserModelId`。
8. 如果目标软件包命名比较特殊，调整 `src/CodexInstaller.psm1` 中的 `Select-CodexPackageSet` 逻辑。
9. 运行安装器时传入 `-Manifest .\config\example.app.psd1`，就能用同一套代码流程指向新软件。

示例应用清单结构：

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

创建新清单后，可以让入口脚本加载新的清单文件，而不是 `config/codex.app.psd1`。不同软件的包命名、依赖关系、架构标记和启动入口可能不同，适配前建议先确认目标软件的包列表。

## ⚠️ 注意事项

- 本项目不隶属于 OpenAI 或 Microsoft
- ChatGPT Codex 的版权归其权利方所有
- 本项目不提供或修改 Codex 应用本体
- 下载链接可能具有时效性，过期后重新运行脚本即可重新获取
- Windows 7 不支持所需 MSIX 安装流程，因此不在支持范围内

## 📄 许可证

MIT License

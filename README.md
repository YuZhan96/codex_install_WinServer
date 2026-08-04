# codex_install_WinServer

用于在没有 Microsoft Store 的 Windows 环境中安装 ChatGPT Codex 桌面版的离线安装工具，主要面向 Windows Server、精简系统、受限企业环境等场景。

远程仓库：

https://github.com/YuZhan96/codex_install_WinServer

## 项目定位

本项目专注于 ChatGPT Codex 桌面版在 Windows Server 环境中的安装，不重新分发、修改或破解应用本体。脚本会通过 Microsoft Store 包信息获取当前系统架构对应的 Codex 主包与依赖包，再调用 Windows 原生 Appx/MSIX 安装能力完成安装。

代码本身保持英文，便于维护、审查和继续扩展；项目文档保留中文，方便中文用户快速使用。

同时，本项目也可以作为其他 Microsoft Store / MSIX 软件的安装模板。若要适配其他软件，需要替换 Store 链接、包名规则、进程名、启动入口和依赖筛选逻辑。

## 主要能力

- 自动识别 x64、x86、ARM64 系统架构
- 按 Microsoft Store 包信息筛选 Codex 主包
- 自动识别并下载当前架构所需依赖
- 校验下载缓存文件大小，避免使用损坏包
- 支持下载重试
- 检查已安装版本，避免重复安装
- 支持强制重装
- 支持只下载不安装
- 安装前自动关闭正在运行的 Codex 进程
- 使用标准 `Add-AppxPackage` / `Remove-AppxPackage` 流程安装和更新

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

即使当前已经是最新版本，也重新下载安装流程。

```powershell
.\Codex_Installer.ps1 -NoPause
```

脚本结束时不等待用户按回车，适合自动化环境。

```powershell
.\Codex_Installer.ps1 -Ring Retail -DownloadRetries 5
```

指定发布通道与下载重试次数。

## 文件说明

```text
codex_install_WinServer/
├── Codex_Installer.ps1    # 主安装脚本
├── README.md              # 中文说明文档
├── LICENSE                # 开源许可证
└── winget/                # 依赖包信息与辅助文件
```

下载文件默认保存在脚本同目录下的 `downloads/` 文件夹。该目录已经被 Git 忽略，不建议把大型安装包提交到仓库。

## 脚本配置

脚本顶部保留了 Codex 专用配置：

| 配置 | 当前值 | 说明 |
| --- | --- | --- |
| `PackageName` | `OpenAI.Codex` | Windows 应用包名 |
| `PackageNamePrefix` | `OpenAI.Codex_` | Store 包文件名前缀 |
| `ProcessName` | `OpenAI.Codex` | 安装前需要关闭的进程名 |
| `StoreUrl` | Codex 的 Microsoft Store 链接 | 目标应用商店页面 |
| `PackageApiUrl` | Store 包信息接口 | 用于获取离线包列表 |
| `AppUserModelId` | Codex 启动入口 | 安装完成后的启动命令 |

普通用户无需修改这些配置。

## 适配其他软件

本仓库默认只维护 ChatGPT Codex 安装逻辑。如果想基于此项目安装其他 Microsoft Store / MSIX 软件，可以参考以下替换点：

- 将 `StoreUrl` 改为目标软件的 Microsoft Store 链接
- 修改 `PackageName` 和 `PackageNamePrefix`
- 修改主包筛选规则
- 修改 `ProcessName`
- 修改 `AppUserModelId`
- 根据目标软件依赖情况调整依赖包筛选逻辑

不同软件的包命名、依赖关系、架构标记和启动入口可能不同。适配前建议先确认目标软件的包列表。

## 注意事项

- 本项目不隶属于 OpenAI 或 Microsoft
- ChatGPT Codex 的版权归其权利方所有
- 本项目不提供、修改或破解 Codex 应用本体
- 下载链接可能具有时效性，过期后重新运行脚本即可重新获取
- Windows 7 不支持 MSIX 安装流程，因此不在支持范围内

## 许可证

MIT License

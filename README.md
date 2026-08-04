# codex_install_WinServer

用于在没有 Microsoft Store 的 Windows 环境中安装 ChatGPT Codex 桌面版的离线安装脚本，主要面向 Windows Server、精简系统、受限企业环境等场景。

远程仓库：

https://github.com/YuZhan96/codex_install_WinServer

## 项目定位

本项目仍然专注于 ChatGPT Codex 桌面版安装，不试图做成通用软件商店，也不重新分发应用本体。脚本会通过 Microsoft Store 包信息获取对应架构的 Codex 主包和依赖包，然后在本机完成安装。

同时，这个项目的结构可以作为其他 Microsoft Store / MSIX 软件的安装模板使用。若需要适配其他软件，通常只需要替换 Store 链接、包名匹配规则、进程名、启动入口等配置与判断逻辑。

## 功能

- 自动识别 x64、x86、ARM64 系统架构
- 从 Microsoft Store 包信息中筛选 ChatGPT Codex 主包
- 自动下载对应架构的依赖包
- 检查本机已安装版本，避免重复安装
- 支持更新已有安装
- 自动关闭正在运行的 Codex 进程
- 安装完成后显示版本、架构、路径和安装体积

## 系统要求

- Windows 10 17763 及以上
- Windows 11
- Windows Server 2019 及以上
- PowerShell 5.1 或更高版本
- 管理员权限

## 使用方法

以管理员身份打开 PowerShell，进入项目目录后运行：

```powershell
.\Codex_Installer.ps1
```

如果系统阻止脚本执行，可以先在当前 PowerShell 会话中运行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

然后再次运行安装脚本。

## 文件说明

```text
codex_install_WinServer/
├── Codex_Installer.ps1    # 主安装脚本
├── README.md              # 中文说明文档
├── LICENSE                # 开源许可证
└── winget/                # 依赖包信息与辅助文件
```

下载的安装包会保存到脚本同目录下的 `downloads/` 文件夹。该目录已被 Git 忽略，不建议把大型安装包提交到仓库。

## 可配置项

脚本顶部保留了少量配置：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `$DownloadDir` | `downloads` | 下载缓存目录 |
| `$StoreUrl` | Codex 的 Microsoft Store 链接 | 目标应用商店页面 |
| `$ApiUrl` | Store 包信息接口 | 用于获取离线包列表 |
| `$Ring` | `Retail` | 发布通道 |

发布通道包括 `Retail`、`RP`、`Slow`、`Fast`、`WIS`、`WIF`。普通用户建议保持 `Retail`。

## 适配其他软件

本仓库默认只维护 Codex 安装逻辑。如果你想基于此项目安装其他 Microsoft Store / MSIX 软件，可以参考以下替换点：

- 将 `$StoreUrl` 改为目标软件的 Microsoft Store 链接
- 修改主包筛选规则，例如 `OpenAI.Codex_`
- 修改已安装包检测名称，例如 `OpenAI.Codex`
- 修改需要关闭的进程名
- 修改安装后的启动入口
- 根据目标软件依赖情况调整依赖包筛选逻辑

不同软件的包命名、依赖关系和启动入口可能不同，适配前建议先确认目标软件的包信息。

## 注意事项

- 本项目不隶属于 OpenAI 或 Microsoft
- ChatGPT Codex 的版权归其权利方所有
- 本项目不提供、修改或破解 Codex 应用本体
- 下载链接可能具有时效性，过期后重新运行脚本即可重新获取
- Windows 7 不支持 MSIX 安装流程，因此不在支持范围内

## 许可证

MIT License

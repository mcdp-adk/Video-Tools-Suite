# Video Tools Suite - 项目概述

## 项目目的
基于 PowerShell 的视频处理工具集，用于视频下载（支持 1800+ 网站）、字幕处理和字幕内封。

## 技术栈
- **语言**: PowerShell 5.1+
- **外部依赖**:
  - yt-dlp: 视频/字幕下载
  - ffmpeg: 视频处理、字幕内封
  - deno: JavaScript 运行时（用于 YouTube 验证）
  - bgutil-ytdlp-pot-provider: YouTube PO Token 插件

## 项目结构
```
Video-Tools-Suite/
├── vts.bat              # 主入口（启动 TUI）
├── config.json          # 用户配置（gitignore）
├── config.example.json  # 配置模板
├── output/              # 默认输出目录（gitignore）
└── scripts/
    ├── vts.ps1          # TUI 主程序（dot source 其他脚本）
    ├── download.ps1     # 视频下载功能
    ├── download.bat
    ├── process.ps1      # 字幕文本处理
    ├── process.bat
    ├── mux.ps1          # 字幕内封
    └── mux.bat
```

## 核心架构
### 双重接口模式
每个核心脚本同时支持：
1. **函数接口**（TUI 集成）: `Invoke-*` 函数
2. **命令行接口**: 通过 .bat 文件调用

### Dot Sourcing 机制
`vts.ps1` 通过 dot sourcing 加载其他脚本，各脚本的 `param()` 必须在文件最顶部。

### 变量命名规范
各脚本使用带前缀的 `$script:` 变量避免冲突：
- download.ps1: `$script:YtdlOutputDir`, `$script:YtdlCookieFile`
- process.ps1: `$script:ProcessedOutputDir`
- mux.ps1: `$script:MuxerOutputDir`

## 核心函数
| 脚本 | 函数 |
|------|------|
| download.ps1 | `Invoke-YouTubeDownloader`, `Invoke-YouTubeSubtitleDownloader` |
| process.ps1 | `Invoke-TextProcessor` |
| mux.ps1 | `Invoke-SubtitleMuxer` |

## 配置系统
- 配置文件: `config.json`（项目根目录）
- 加载函数: `Import-Config`（在 vts.ps1 中）
- 保存函数: `Export-Config`（在 vts.ps1 中）
- 配置项: CookieFile, DownloadDir, MuxDir, ProcessedDir

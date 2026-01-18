# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

基于 PowerShell 的视频处理工具集：视频下载（支持 1800+ 网站）、字幕处理、字幕内封。

## 文件结构

```
Video-Tools-Suite/
├── vts.bat              # 主入口
├── config.json          # 用户配置（gitignore）
├── config.example.json  # 配置模板
├── output/              # 默认输出目录（gitignore）
└── scripts/
    ├── vts.ps1          # TUI 主程序
    ├── download.ps1     # 视频下载（yt-dlp 支持的所有网站）
    ├── download.bat
    ├── process.ps1      # 字幕处理
    ├── process.bat
    ├── mux.ps1          # 字幕内封
    └── mux.bat
```

## 架构设计

### 双重接口模式

每个核心脚本同时支持函数调用和命令行调用：

```powershell
# 函数接口（TUI 集成）
$result = Invoke-YouTubeDownloader -InputUrl $url
$result = Invoke-TextProcessor -InputPath $file
$result = Invoke-SubtitleMuxer -VideoPath $video -SubtitlePath $sub

# 命令行接口
powershell -File scripts\download.ps1 <url>
```

### Dot Sourcing 机制

`vts.ps1` 通过 dot sourcing 加载其他脚本，因此各脚本的 `param()` 必须在文件最顶部。

各脚本使用带前缀的 `$script:` 变量避免冲突：
- download.ps1: `$script:YtdlOutputDir`, `$script:YtdlCookieFile`
- process.ps1: `$script:ProcessedOutputDir`
- mux.ps1: `$script:MuxerOutputDir`

### 核心函数

| 脚本 | 函数 |
|------|------|
| download.ps1 | `Invoke-YouTubeDownloader`, `Invoke-YouTubeSubtitleDownloader` |
| process.ps1 | `Invoke-TextProcessor` |
| mux.ps1 | `Invoke-SubtitleMuxer` |

## 配置系统

### 配置文件

项目根目录的 `config.json` 存储用户设置，程序启动时自动加载：

```json
{
  "CookieFile": "",
  "DownloadDir": "./output",
  "MuxDir": "./output",
  "ProcessedDir": "./output"
}
```

### 默认路径

所有输出默认保存到项目内 `output/` 文件夹。使用 `$PSScriptRoot` 确保路径始终相对于脚本位置。

| 配置 | 默认值 |
|------|------|
| Cookie 文件 | （空） |
| 下载输出 | `./output` |
| 内封输出 | `./output` |
| 处理后字幕 | `./output` |

### 配置函数

- `Import-Config` - 启动时从 config.json 加载设置
- `Export-Config` - 保存设置到 config.json

## 处理逻辑

### 字幕文本处理 (process.ps1)

- 中文标点（，。、）替换为空格
- 中文与英文/数字之间添加空格
- 输出：UTF-8 with BOM，文件名添加 `_processed` 后缀

### 字幕内封 (mux.ps1)

- 输出格式：MKV（兼容 ASS 字幕）
- 保留原视频所有字幕轨
- 新字幕设为默认轨道
- 元数据：language=`chi`, title=`Bilingual Subtitles`

## 依赖项

- yt-dlp, ffmpeg, deno, bgutil-ytdlp-pot-provider

详见 README.md 安装说明。

## yt-dlp 参数

`Get-CommonYtDlpArgs` 返回的通用参数：

| 参数 | 说明 |
|------|------|
| `--no-warnings` | 隐藏警告信息 |
| `--no-progress` | 不在控制台显示进度条 |
| `--console-title` | 在终端标题栏显示进度 |
| `--restrict-filenames` | 文件名使用 ASCII 安全字符 |

## TUI 功能

### 主菜单

- 显示当前输出目录
- 菜单选项：1-5 功能 + S 设置 + Q 退出

### 设置菜单

可修改并持久化保存：
- Cookie 文件路径
- 下载输出目录
- 内封输出目录
- 处理后字幕输出目录

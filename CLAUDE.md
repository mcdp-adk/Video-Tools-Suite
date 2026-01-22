# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Video Tools Suite 是一个基于 PowerShell 的视频处理工具集，用于：

- 基于 PowerShell 5.1

- 使用 yt-dlp 下载视频和字幕
- 使用 AI (OpenAI 兼容 API) 翻译字幕
- 生成双语 ASS 字幕
- 将字幕内封到视频 (MKV)

## 常用命令

```powershell
# 运行主程序
.\vts.bat

# 验证脚本语法
powershell -Command ". .\scripts\<module>.ps1"

# 单独运行模块
powershell .\scripts\download.ps1 "https://youtube.com/watch?v=xxx"
powershell .\scripts\translate.ps1 "subtitle.vtt"
powershell .\scripts\transcript.ps1 "subtitle.vtt"
powershell .\scripts\mux.ps1 "video.mp4" "subtitle.ass"
```

## 架构

```
vts.bat → vts.ps1 (主 TUI 程序)
              │
              ├── 配置管理: Import-Config, Export-Config, Apply-ConfigToModules
              │
              └── 菜单调用模块 API:
                    ├── download.ps1   → New-VideoProjectDir, Invoke-VideoDownload, Invoke-SubtitleDownload, Get-VideoSubtitleInfo, Get-PlaylistVideoUrls
                    ├── batch.ps1      → Invoke-BatchWorkflow, Invoke-BatchRetry
                    ├── translate.ps1  → Invoke-SubtitleTranslator
                    ├── transcript.ps1 → Invoke-TranscriptGenerator
                    ├── mux.ps1        → Invoke-SubtitleMuxer
                    └── workflow.ps1   → Invoke-FullWorkflow (全流程封装)

底层工具模块:
    ├── ai-client.ps1     → Invoke-AiCompletion, Invoke-SubtitleTranslate, Invoke-GlobalProofread
    ├── subtitle-utils.ps1 → Import-SubtitleFile, New-BilingualAssContent, Export-AssFile
    ├── glossary.ps1      → Get-AllGlossaryTerms, Import-Glossary
    ├── lang-config.ps1   → Get-LanguageDisplayName, $script:LanguageMap, $script:DefaultTargetLanguage
    └── utils.ps1         → Show-Success, Show-Error, Show-Warning, Show-Info
```

### 配置同步机制

vts.ps1 通过 `Apply-ConfigToModules` 将中央配置同步到各模块的 `$script:*` 变量：
- `$script:YtdlOutputDir`, `$script:MuxerOutputDir` 等 → 各模块输出目录
- `$script:AiClient_*` → AI API 配置
- `$script:TargetLanguage` → 翻译目标语言

每个模块也有默认值，支持独立运行。

### 语言配置 (lang-config.ps1)

统一管理语言相关配置，避免硬编码分散：

```powershell
$script:LanguageMap           # 语言代码 → AI 显示名称 (如 'zh-Hans' → 'Chinese (Simplified)')
$script:QuickSelectLanguages  # 快速选择菜单的语言列表
$script:DefaultTargetLanguage # 默认目标语言 ('zh-Hans')

Get-LanguageDisplayName -LangCode 'zh-Hans'  # 返回 'Chinese (Simplified)'
```

**向后兼容**：`Import-Config` 自动将旧配置 `zh-CN` → `zh-Hans`，`zh-TW` → `zh-Hant`

### 主 API 函数

| 模块 | 主 API | 用途 |
|------|--------|------|
| download.ps1 | `New-VideoProjectDir` | 创建项目目录结构 |
| download.ps1 | `Invoke-VideoDownload` | 下载视频 |
| download.ps1 | `Invoke-SubtitleDownload` | 智能下载字幕（见下方返回值说明） |
| download.ps1 | `Get-VideoSubtitleInfo` | 获取视频字幕元数据 |
| download.ps1 | `Get-PlaylistVideoUrls` | 从播放列表提取视频 URL |
| translate.ps1 | `Invoke-SubtitleTranslator` | 翻译字幕，输出双语 ASS |
| transcript.ps1 | `Invoke-TranscriptGenerator` | 字幕转纯文本 |
| mux.ps1 | `Invoke-SubtitleMuxer` | 字幕内封到视频 |
| workflow.ps1 | `Invoke-FullWorkflow` | 全流程处理 (Download → Translate → Mux) |
| batch.ps1 | `Invoke-BatchWorkflow` | 批量处理多个视频 |
| batch.ps1 | `Invoke-BatchRetry` | 重试失败项 |
| lang-config.ps1 | `Get-LanguageDisplayName` | 获取语言代码的显示名称 |
| utils.ps1 | `Show-Success/Error/Warning/Info` | 统一消息输出 |

### Invoke-SubtitleDownload 返回值

智能字幕下载，按优先级选择最佳字幕：
1. 目标语言手动字幕存在 → 跳过（已内封到视频）
2. 视频原始语言手动字幕 → 下载
3. 视频原始语言自动字幕 (*-orig) → 下载

```powershell
@{
    SubtitleFile    = "path/to/subtitle.vtt"  # 字幕文件路径，或 $null
    VideoLanguage   = "en"                     # 视频原始语言
    SubtitleType    = "manual|auto|embedded|none"
    SkipTranslation = $true|$false            # 是否跳过翻译
}
```

## 编码规范

- 文件编码：UTF-8 (无 BOM)
- PowerShell 命名：动词-名词 (Verb-Noun)
- 参数支持 `-Quiet` 开关控制输出
- 使用 `-LiteralPath` 处理含特殊字符的路径

### TUI 与脚本风格规范

**语言要求**：
- 所有 TUI 界面和脚本输出必须使用**英文**
- 禁止在代码中出现中文字符（注释除外）

**消息格式**（使用 utils.ps1 中的函数）：
```powershell
Show-Success "Operation completed"    # [SUCCESS] ... (Green)
Show-Error "Something failed"         # [ERROR] ... (Red)
Show-Warning "Check this"             # [WARNING] ... (Yellow)
Show-Info "Processing..."             # [INFO] ... (Cyan)
```

**颜色规范**：
| 用途 | 颜色 |
|------|------|
| 标题/分隔线 | Cyan |
| 子标题/步骤 | Yellow |
| 选项文字 | White |
| 选项描述 | DarkGray |
| 成功消息 | Green |
| 错误消息 | Red |
| 警告消息 | Yellow |
| 信息提示 | Gray |

**选项菜单格式**：
```powershell
Write-Host ""
Write-Host "  [1] Option One" -ForegroundColor White
Write-Host "      Description here" -ForegroundColor DarkGray
Write-Host "  [2] Option Two" -ForegroundColor White
Write-Host "  [3] Custom" -ForegroundColor White
Write-Host ""
do {
    $choice = Read-Host "  Select [1-3, default=1]"
    if (-not $choice) { $choice = '1' }
} while ($choice -notmatch '^[1-3]$')
```

**交互规范**：
- 两个空格缩进（`"  [1] ..."`）
- 选项输入使用循环验证
- 空输入采用默认值
- 分隔线使用 `("-" * 60)` 或 `("=" * 60)`

## 外部依赖

- yt-dlp: 视频下载
- ffmpeg: 视频处理
- AI API: OpenAI 兼容端点 (可配置)

## 配置系统

### 配置文件

- **位置**: `config.json`（项目根目录）
- **示例**: `config.example.json`

### 配置项

| 配置键 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `FirstRun` | bool | `true` | 首次运行标记 |
| `OutputDir` | string | `"./output"` | 输出目录 |
| `CookieFile` | string | `""` | yt-dlp cookie 文件路径 |
| `AiProvider` | string | `"openai"` | AI 提供商标识 |
| `AiBaseUrl` | string | `"https://api.openai.com/v1"` | AI API 端点 |
| `AiApiKey` | string | `""` | AI API 密钥 |
| `AiModel` | string | `"gpt-4o-mini"` | AI 模型名称 |
| `TargetLanguage` | string | `"zh-Hans"` | 翻译目标语言 |
| `GenerateTranscriptInWorkflow` | bool | `false` | 工作流中是否生成纯文本 |

### 配置同步机制

```
config.json → Import-Config → $script:Config → Apply-ConfigToModules → 模块变量
```

**模块变量映射**:

| 配置键 | 模块变量 | 所属模块 |
|--------|----------|----------|
| `OutputDir` | `$script:YtdlOutputDir` | download.ps1 |
| `OutputDir` | `$script:MuxerOutputDir` | mux.ps1 |
| `OutputDir` | `$script:TranscriptOutputDir` | transcript.ps1 |
| `OutputDir` | `$script:TranslateOutputDir` | translate.ps1 |
| `OutputDir` | `$script:WorkflowOutputDir` | workflow.ps1 |
| `CookieFile` | `$script:YtdlCookieFile` | download.ps1 |
| `TargetLanguage` | `$script:TargetLanguage` | translate.ps1 |
| `AiBaseUrl` | `$script:AiClient_BaseUrl` | ai-client.ps1 |
| `AiApiKey` | `$script:AiClient_ApiKey` | ai-client.ps1 |
| `AiModel` | `$script:AiClient_Model` | ai-client.ps1 |

### Claude 测试命令指南

**读取配置**:
```powershell
# 读取当前用户配置
Get-Content config.json | ConvertFrom-Json

# 获取 cookie 路径
(Get-Content config.json | ConvertFrom-Json).CookieFile
```

**使用 yt-dlp 测试时**:
```powershell
# 正确方式：从配置读取 cookie
$config = Get-Content config.json | ConvertFrom-Json
yt-dlp --cookies $config.CookieFile --list-subs "URL"

# 错误方式：硬编码路径
yt-dlp --cookies "D:\some\path\cookies.txt" --list-subs "URL"  # ❌ 不要这样做
```

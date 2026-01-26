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
              ├── config-manager.ps1 (配置中间件)
              │     ├── Import-Config, Export-Config
              │     ├── Get-ConfigValue, Set-ConfigValue
              │     └── Apply-ConfigToModules
              │
              ├── settings.ps1 → Invoke-SettingsMenu (设置界面)
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
    ├── lang-config.ps1   → Get-LanguageDisplayName, $script:LanguageMap
    ├── tui-utils.ps1     → Set-VtsWindowTitle, Save-WindowTitle, New-ProgressBar, Write-AtPosition
    └── utils.ps1         → Show-Success, Show-Error, Show-Warning, Show-Info
```

### 配置同步机制

config-manager.ps1 是配置系统的中间件，所有配置操作通过它进行：

```powershell
# 配置流程
config.example.json → Initialize-Config → config.json
config.json → Import-Config → $script:Config → Apply-ConfigToModules → 模块变量

# 主要函数
Import-Config          # 加载配置到 $script:Config
Export-Config          # 保存 $script:Config 到文件
Get-ConfigValue        # 读取单个配置项
Set-ConfigValue        # 设置单个配置项
Apply-ConfigToModules  # 同步配置到各模块的 $script:* 变量
Ensure-ConfigReady     # 确保配置已初始化（首次运行检查）
```

**重要**：模块不再有默认值，必须通过 config-manager.ps1 获取配置。

### 语言配置 (lang-config.ps1)

统一管理语言相关配置，避免硬编码分散：

```powershell
$script:LanguageMap           # 语言代码 → AI 显示名称 (如 'zh-Hans' → 'Chinese (Simplified)')
$script:QuickSelectLanguages  # 快速选择菜单的语言列表

Get-LanguageDisplayName -LangCode 'zh-Hans'  # 返回 'Chinese (Simplified)'
```

**向后兼容**：`Import-Config` 自动将旧配置 `zh-CN` → `zh-Hans`，`zh-TW` → `zh-Hant`

### TUI 工具 (tui-utils.ps1)

提供统一的窗口标题和进度显示功能：

**窗口标题 Emoji 规范**：
| 阶段 | Emoji | 示例 |
|------|-------|------|
| 下载 | 📥 | `📥 Downloading 45%` |
| Transcript | 📝 | `📝 Generating transcript...` |
| 翻译 | 🌐 | `🌐 Translating batch 3/5...` |
| 封装 | 🎬 | `🎬 Muxing...` |

```powershell
# 设置窗口标题
Set-VtsWindowTitle -Phase Download -Status "Downloading..."

# 保存和恢复标题
$originalTitle = Save-WindowTitle
# ... 执行操作 ...
Restore-WindowTitle -Title $originalTitle

# 生成进度条
New-ProgressBar -Current 5 -Total 10  # 返回 "[████████░░░░] 5/10"
```

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
| batch.ps1 | `Invoke-BatchWorkflow` | 批量处理多个视频（并行下载 + 顺序翻译/封装） |
| batch.ps1 | `Invoke-ParallelDownload` | 并行下载多个视频 |
| batch.ps1 | `Invoke-BatchRetry` | 重试失败项 |
| lang-config.ps1 | `Get-LanguageDisplayName` | 获取语言代码的显示名称 |
| utils.ps1 | `Show-Success/Error/Warning/Info` | 统一消息输出 |
| tui-utils.ps1 | `Set-VtsWindowTitle` | 设置带 emoji 的窗口标题 |
| tui-utils.ps1 | `New-ProgressBar` | 生成进度条字符串 |
| tui-utils.ps1 | `Write-AtPosition` | 在指定位置写入文本（用于 TUI 刷新） |

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
Show-Success "Operation completed"    # Green text
Show-Error "Something failed"         # Red text
Show-Warning "Check this"             # Yellow text
Show-Info "Processing..."             # Cyan text (auto blank line before)
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
| `TargetLanguage` | string | `"zh-Hans"` | 翻译目标语言 |
| `EmbedFontFile` | string | `"LXGWWenKaiLite-Medium.ttf"` | 嵌入字体文件名 |
| `GenerateTranscriptInWorkflow` | bool | `false` | 工作流中是否生成纯文本 |
| `BatchParallelDownloads` | int | `3` | 批量下载并行数 (1-10) |
| `AiProvider` | string | `"openai"` | AI 提供商标识 |
| `AiBaseUrl` | string | `"https://api.openai.com/v1"` | AI API 端点 |
| `AiApiKey` | string | `""` | AI API 密钥 |
| `AiModel` | string | `"gpt-4o-mini"` | AI 模型名称 |

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
| `OutputDir` | `$script:BatchOutputDir` | batch.ps1 |
| `CookieFile` | `$script:YtdlCookieFile` | download.ps1 |
| `TargetLanguage` | `$script:TargetLanguage` | translate.ps1, workflow.ps1 |
| `EmbedFontFile` | `$script:EmbedFontFile` | translate.ps1, mux.ps1 |
| `AiBaseUrl` | `$script:AiClient_BaseUrl` | ai-client.ps1 |
| `AiApiKey` | `$script:AiClient_ApiKey` | ai-client.ps1 |
| `AiModel` | `$script:AiClient_Model` | ai-client.ps1 |
| `BatchParallelDownloads` | `$script:BatchParallelDownloads` | batch.ps1 |
| `GenerateTranscriptInWorkflow` | `$script:GenerateTranscriptInWorkflow` | batch.ps1 |

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

## 字体嵌入

### 字体目录

- **位置**: `fonts/` (项目根目录)
- **默认字体**: `LXGWWenKaiLite-Medium.ttf`

### 工作流程

1. **设置界面**：从 `fonts/` 目录读取可用 `.ttf` 文件供用户选择
2. **翻译时**：使用配置的字体名称（不含扩展名）生成 ASS 字幕
3. **封装时**：通过 `ffmpeg -attach` 将字体文件嵌入 MKV

### 代码规范

- **禁止硬编码字体名称**：不要在代码中写死如 "Microsoft YaHei"、"Noto Sans" 等
- **ASS 字体名**：使用文件名（不含扩展名），如 `LXGWWenKaiLite-Medium`
- **不嵌入时**：默认使用 `Arial`（通用字体）

```powershell
# 正确：从配置读取字体
$fontName = [System.IO.Path]::GetFileNameWithoutExtension($script:EmbedFontFile)

# 错误：硬编码字体名称
$fontName = "Microsoft YaHei"  # ❌ 不要这样做
```

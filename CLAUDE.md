# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Video Tools Suite 是一个基于 PowerShell 的视频处理工具集，用于：
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
                    ├── download.ps1   → New-VideoProjectDir, Invoke-VideoDownload, Invoke-SubtitleDownload
                    ├── translate.ps1  → Invoke-SubtitleTranslator
                    ├── transcript.ps1 → Invoke-TranscriptGenerator
                    ├── mux.ps1        → Invoke-SubtitleMuxer
                    └── workflow.ps1   → Invoke-FullWorkflow (全流程封装)

底层工具模块:
    ├── ai-client.ps1     → Invoke-AiCompletion, Invoke-SubtitleTranslate, Invoke-GlobalProofread
    ├── subtitle-utils.ps1 → Import-SubtitleFile, New-BilingualAssContent, Export-AssFile
    └── glossary.ps1      → Get-AllGlossaryTerms, Import-Glossary
```

### 配置同步机制

vts.ps1 通过 `Apply-ConfigToModules` 将中央配置同步到各模块的 `$script:*` 变量：
- `$script:YtdlOutputDir`, `$script:MuxerOutputDir` 等 → 各模块输出目录
- `$script:AiClient_*` → AI API 配置
- `$script:TargetLanguage` → 翻译目标语言

每个模块也有默认值，支持独立运行。

### 主 API 函数

| 模块 | 主 API | 用途 |
|------|--------|------|
| download.ps1 | `New-VideoProjectDir` | 创建项目目录结构 |
| download.ps1 | `Invoke-VideoDownload` | 下载视频 |
| download.ps1 | `Invoke-SubtitleDownload` | 下载字幕 |
| translate.ps1 | `Invoke-SubtitleTranslator` | 翻译字幕，输出双语 ASS |
| transcript.ps1 | `Invoke-TranscriptGenerator` | 字幕转纯文本 |
| mux.ps1 | `Invoke-SubtitleMuxer` | 字幕内封到视频 |
| workflow.ps1 | `Invoke-FullWorkflow` | 全流程处理 |

## 编码规范

- 文件编码：UTF-8 (无 BOM)
- PowerShell 命名：动词-名词 (Verb-Noun)
- 参数支持 `-Quiet` 开关控制输出
- 使用 `-LiteralPath` 处理含特殊字符的路径

## 外部依赖

- yt-dlp: 视频下载
- ffmpeg: 视频处理
- AI API: OpenAI 兼容端点 (可配置)

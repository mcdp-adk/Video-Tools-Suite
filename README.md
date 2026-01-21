# Video Tools Suite

基于 PowerShell 的视频处理工具集，支持视频下载、AI 字幕翻译、双语字幕生成和字幕内封。

## 功能

- **视频下载** - 下载视频及字幕（支持 yt-dlp 所有 1800+ 网站）
- **AI 字幕翻译** - 使用 AI 翻译字幕，支持术语库控制
- **Google 翻译** - 免费翻译选项，无需 API
- **双语字幕** - 自动生成双语字幕（ASS 格式）
- **字幕文本处理** - 优化中文字幕显示（标点替换、中英文间距）
- **字幕内封** - 将字幕合并到视频文件（输出 MKV 格式）
- **生成转录文本** - 将字幕转换为纯文本
- **全流程处理** - 一键完成：下载 → 翻译 → 双语字幕 → 内封

## 依赖安装

需要 Windows PowerShell 5.1 或更高版本。

```powershell
# 安装 Scoop（如未安装）
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex

# 安装核心依赖
scoop bucket add extras
scoop install yt-dlp ffmpeg deno
pip install bgutil-ytdlp-pot-provider
```

### 依赖说明

| 依赖 | 用途 | 必需 |
|------|------|------|
| yt-dlp | 视频下载 | 是 |
| ffmpeg | 视频处理、字幕内封 | 是 |
| deno | JavaScript 运行时 | YouTube |
| bgutil-ytdlp-pot-provider | YouTube 验证 | YouTube |
| AI API Key | AI 翻译 | 可选 |

## 使用方式

```bash
vts.bat
```

### 菜单选项

| 选项 | 功能 |
|------|------|
| A | 全流程处理（下载 → 翻译 → 双语 → 内封）|
| 1 | 下载视频和字幕 |
| 2 | 仅下载字幕 |
| 3 | 生成转录文本 |
| 4 | 翻译字幕（AI/Google）|
| 5 | 文本处理 |
| 6 | 字幕内封 |
| S | 设置 |
| Q | 退出 |

### 设置菜单

| 选项 | 说明 |
|------|------|
| 1 | 输出目录 |
| 2 | AI 提供商 |
| 3 | API Key |
| 4 | 模型 |
| 5 | 翻译方式 |
| 6 | 目标语言 |
| 7 | 术语库管理 |
| 8 | Cookie 文件 |
| R | 重新运行设置向导 |
| B | 返回 |

## 配置

首次运行时会启动设置向导。配置保存在 `config.json`：

```json
{
  "FirstRun": false,
  "OutputDir": "./output",
  "CookieFile": "",
  "AiProvider": "openai",
  "AiBaseUrl": "https://api.openai.com/v1",
  "AiApiKey": "",
  "AiModel": "gpt-4o-mini",
  "TranslateMethod": "ai",
  "TargetLanguage": "zh-CN"
}
```

### 配置项说明

| 设置 | 说明 |
|------|------|
| OutputDir | 所有输出的默认目录 |
| CookieFile | YouTube Cookie 文件路径 |
| AiProvider | AI 提供商（openai/deepseek/openrouter/custom） |
| AiBaseUrl | AI API 端点 |
| AiApiKey | AI API 密钥 |
| AiModel | AI 模型名称 |
| TranslateMethod | 翻译方法（ai/google） |
| TargetLanguage | 目标语言代码 |

### 支持的 AI 提供商

| 提供商 | API 端点 |
|--------|----------|
| OpenAI | https://api.openai.com/v1 |
| DeepSeek | https://api.deepseek.com |
| OpenRouter | https://openrouter.ai/api/v1 |
| 自定义 | 任何兼容 OpenAI API 的端点 |

## 术语库

术语库用于控制 AI 翻译中的专业术语。

- 术语库存储在 `glossaries/` 目录
- 预置：General、Technology、Gaming、Football
- 通过设置菜单管理术语库

## YouTube Cookie 配置

如果遇到 "Sign in to confirm you're not a bot" 错误：

1. 在浏览器隐私窗口登录 YouTube
2. 导出 Cookie 到配置的路径
3. 关闭隐私窗口（防止 Cookie 被轮换）

## 故障排除

| 问题 | 解决方案 |
|------|----------|
| 只能下载低清晰度视频 | 确保已安装 deno 和 bgutil-ytdlp-pot-provider |
| "Sign in to confirm you're not a bot" | 配置 YouTube Cookie 文件 |
| 字幕内封失败 | 确保 ffmpeg 已安装且在 PATH 中 |
| AI 翻译失败 | 检查 API Key 和网络连接 |

## 许可证

MIT

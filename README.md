# Video Tools Suite

基于 PowerShell 的视频处理工具集，用于 YouTube 视频下载、字幕处理和字幕内封。

## 功能

- **YouTube 视频下载** - 下载最高质量视频及字幕文件
- **字幕文本处理** - 优化中文字幕显示（标点替换、中英文间距）
- **字幕内封** - 将字幕合并到视频文件（输出 MKV 格式）

## 依赖安装

需要 Windows PowerShell 5.1 或更高版本。

```powershell
# 安装 Scoop（如未安装）
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex

# 安装依赖
scoop bucket add extras
scoop install yt-dlp ffmpeg deno
pip install bgutil-ytdlp-pot-provider
```

### 依赖说明

| 依赖 | 用途 |
|------|------|
| yt-dlp | YouTube 下载 |
| ffmpeg | 视频处理、字幕内封 |
| deno | JavaScript 运行时，解决 YouTube 验证 |
| bgutil-ytdlp-pot-provider | PO Token 插件，YouTube 请求验证 |

## 使用方式

### 交互式界面

```bash
vts.bat
```

菜单选项：
1. Download YouTube Video - 下载视频
2. Download Subtitles Only - 仅下载字幕
3. Process Subtitle Text - 处理字幕文本
4. Mux Subtitle into Video - 字幕内封
5. Process + Mux (Combined) - 处理+内封

S. Settings - 设置（Cookie 路径、输出目录）

### 命令行

```bash
# YouTube 视频下载
scripts\download.bat <URL或视频ID>

# 字幕文本处理
scripts\process.bat <字幕文件>

# 字幕内封
scripts\mux.bat <视频文件> <字幕文件>
```

## 配置

所有输出文件默认保存到 `output/` 文件夹。设置保存在项目根目录的 `config.json` 中。

复制 `config.example.json` 为 `config.json` 并根据需要调整路径：

```json
{
  "CookieFile": "",
  "DownloadDir": "./output",
  "MuxDir": "./output",
  "ProcessedDir": "./output"
}
```

| 设置 | 说明 |
|------|------|
| CookieFile | YouTube Cookie 文件路径 |
| DownloadDir | 下载输出目录 |
| MuxDir | 内封视频输出目录 |
| ProcessedDir | 处理后字幕输出目录 |

可通过设置菜单（S）修改，也可直接编辑文件。

## YouTube Cookie 配置

如果遇到 "Sign in to confirm you're not a bot" 错误，需要配置 Cookie：

1. 在浏览器隐私窗口登录 YouTube
2. 导出 Cookie 到配置的路径
3. 关闭隐私窗口（防止 Cookie 被轮换）

脚本会自动检测并使用该 Cookie 文件。

## 故障排除

| 问题 | 解决方案 |
|------|----------|
| 只能下载低清晰度视频 | 确保已安装 deno 和 bgutil-ytdlp-pot-provider |
| "Sign in to confirm you're not a bot" | 配置 YouTube Cookie 文件 |
| 字幕内封失败 | 确保 ffmpeg 已安装且在 PATH 中 |

## 许可证

MIT

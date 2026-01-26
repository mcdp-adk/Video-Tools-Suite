# Video Tools Suite

基于 PowerShell 的视频处理工具集，支持视频下载、AI 字幕翻译、双语字幕生成和字幕内封。

## 功能

- **视频下载** - 支持 yt-dlp 所有 1800+ 网站
- **AI 字幕翻译** - 支持 OpenAI/DeepSeek/OpenRouter，术语库控制
- **双语字幕** - 自动生成 ASS 格式，支持字体嵌入
- **字幕内封** - 合并到 MKV 文件
- **批量处理** - 播放列表/多 URL 并行下载
- **全流程处理** - 一键完成下载、翻译、内封

## 依赖

需要 Windows PowerShell 5.1 或更高版本。

```powershell
# 安装 Scoop（如未安装）
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex

# 安装依赖
scoop install yt-dlp ffmpeg deno
pip install bgutil-ytdlp-pot-provider
```

## 使用

```bash
vts.bat
```

首次运行会启动设置向导，配置 AI API、输出目录等。之后通过交互式菜单操作。

配置保存在 `config.json`，可随时在设置中修改。

## 目录结构

```
├── config.json          # 用户配置
├── fonts/               # 字幕嵌入字体
├── glossaries/          # 术语库
└── output/              # 默认输出目录
```

## 术语库

翻译时 AI 自动根据字幕内容匹配相关术语库，确保专有名词翻译一致。

格式为 CSV，每行一个术语：

```csv
source,target
Machine Learning,机器学习
Neural Network,神经网络
```

按领域分文件管理（如 `tech.csv`、`mufc.csv`），AI 会根据内容自动选择。

## 字体嵌入

双语字幕会嵌入 `fonts/` 目录下的字体到 MKV 文件，确保播放时正确显示。

1. 将 `.ttf` 字体文件放入 `fonts/` 目录
2. 在设置中选择要使用的字体

## YouTube Cookie

遇到 "Sign in to confirm you're not a bot" 时：

1. 在浏览器隐私窗口登录 YouTube
2. 导出 Cookie 文件
3. 在设置中配置 Cookie 路径
4. 关闭隐私窗口（防止 Cookie 失效）

## 致谢

- [WEIFENG2333/VideoCaptioner](https://github.com/WEIFENG2333/VideoCaptioner) - 全流程处理的灵感来源
- [immersive-translate/terms](https://github.com/immersive-translate/terms) - 术语库格式参考
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) - 视频下载
- [ffmpeg](https://github.com/FFmpeg/FFmpeg) - 视频处理
- [LXGW WenKai](https://github.com/lxgw/LxgwWenKai) - 默认嵌入字体

## 许可证

[MIT](LICENSE)

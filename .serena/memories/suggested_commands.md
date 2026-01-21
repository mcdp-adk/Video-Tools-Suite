# Video Tools Suite - 开发命令

## 运行项目
```powershell
# 启动 TUI（交互式界面）
.\vts.bat

# 命令行模式
.\scripts\download.bat <URL>
.\scripts\process.bat <字幕文件>
.\scripts\mux.bat <视频文件> <字幕文件>
```

## 测试脚本
```powershell
# 直接在 PowerShell 中测试函数
. .\scripts\download.ps1
Invoke-YouTubeDownloader -InputUrl "https://www.youtube.com/watch?v=xxx"

. .\scripts\process.ps1
Invoke-TextProcessor -InputPath "subtitle.vtt"

. .\scripts\mux.ps1
Invoke-SubtitleMuxer -VideoPath "video.mp4" -SubtitlePath "subtitle.ass"
```

## Git 命令
```powershell
git status
git add .
git commit -m "message"
git log --oneline -10
```

## Windows 系统命令
```powershell
# 列出文件
Get-ChildItem -Path . -Recurse
ls

# 查找文件
Get-ChildItem -Path . -Recurse -Filter "*.ps1"

# 搜索文件内容
Select-String -Path ".\scripts\*.ps1" -Pattern "pattern"

# 检查依赖
Get-Command yt-dlp
Get-Command ffmpeg
Get-Command deno
```

## 依赖安装
```powershell
# 使用 Scoop
scoop install yt-dlp ffmpeg deno
pip install bgutil-ytdlp-pot-provider
```

## 调试技巧
```powershell
# 检查 PowerShell 版本
$PSVersionTable.PSVersion

# 设置 UTF-8 编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 检查脚本语法
Get-Command -Syntax Invoke-YouTubeDownloader
```

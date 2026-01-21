# Video Tools Suite - 代码风格和规范

## PowerShell 命名规范
- **函数**: PascalCase，使用动词-名词格式（如 `Invoke-YouTubeDownloader`）
- **参数**: PascalCase（如 `$InputUrl`, `$VideoPath`）
- **脚本级变量**: `$script:` 前缀 + PascalCase（如 `$script:YtdlOutputDir`）
- **本地变量**: camelCase 或小写（如 `$content`, `$result`）

## 文件结构规范
每个脚本文件的结构：
1. `param()` 声明（必须在文件最顶部，用于 dot sourcing 兼容）
2. 配置变量（`$script:` 作用域）
3. 辅助函数（`Test-*`, `Get-*`, `Build-*`）
4. 主函数（`Invoke-*` - 公开 API）
5. 命令行接口（`if ($InputPath) { ... }`）

## 编码规范
- 文件编码: UTF-8 (without BOM)
- 输出文件编码: UTF-8 with BOM（为了播放器兼容性）
- 中英文之间添加空格

## 错误处理
```powershell
# 使用 throw 抛出错误
if (-not (Test-Path $path)) {
    throw "File not found: $path"
}

# 使用 try-catch 捕获
try {
    $result = SomeOperation
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
```

## 函数设计原则
- 每个核心脚本必须提供 `Invoke-*` 函数作为公开 API
- 函数应返回结果路径（字符串）
- 使用 `[Parameter(Mandatory=$true)]` 标记必需参数
- 内部辅助函数使用 `Test-*`, `Get-*`, `Build-*` 前缀

## TUI 集成
- 使用 `Show-Header`, `Show-Success`, `Show-Error` 等辅助函数
- 菜单函数命名: `Invoke-*Menu`
- 使用 `Pause-Menu` 暂停等待用户确认

## 注释规范
- 仅在必要时添加注释
- 使用 `#` 单行注释
- 注释使用英文或中文均可

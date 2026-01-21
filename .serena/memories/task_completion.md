# Video Tools Suite - 任务完成检查清单

## 代码修改后的检查项

### 1. 语法检查
```powershell
# 确保脚本没有语法错误
powershell -Command "& { . .\scripts\download.ps1 }"
powershell -Command "& { . .\scripts\process.ps1 }"
powershell -Command "& { . .\scripts\mux.ps1 }"
powershell -Command "& { . .\scripts\vts.ps1 }"
```

### 2. 功能测试
- [ ] TUI 主菜单正常显示
- [ ] 各菜单选项可正常进入
- [ ] 设置菜单可正常保存配置
- [ ] 命令行接口可正常工作

### 3. 代码质量检查
- [ ] `param()` 在文件最顶部（dot sourcing 兼容性）
- [ ] 使用 `$script:` 作用域的变量
- [ ] 函数命名遵循 `Invoke-*` 规范
- [ ] 错误处理使用 `throw` 和 `try-catch`
- [ ] UTF-8 编码

### 4. 配置同步
如果修改了配置项：
- [ ] 更新 `config.example.json`
- [ ] 更新 `Import-Config` 函数
- [ ] 更新 `Export-Config` 函数
- [ ] 更新设置菜单 `Invoke-SettingsMenu`

### 5. 文档更新
如果添加新功能：
- [ ] 更新 `README.md`
- [ ] 更新 `CLAUDE.md`

### 6. Git 提交
```powershell
git status
git diff
git add .
git commit -m "feat/fix/docs: 简短描述"
```

## 新增脚本的检查项
- [ ] 创建 `.ps1` 文件（遵循文件结构规范）
- [ ] 创建对应的 `.bat` 入口文件
- [ ] 在 `vts.ps1` 中 dot source 新脚本
- [ ] 在 TUI 菜单中添加新选项
- [ ] 更新 README 和 CLAUDE.md

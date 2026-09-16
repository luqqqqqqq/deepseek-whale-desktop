# ⚠️ 不要用 GitHub 网页编辑器改 `whale.ps1`（会丢 BOM）

## 现象

在 GitHub 网页上编辑并提交 `whale.ps1`，本地 `git pull` 之后挂件**启动不了**：
双击 `start-widget.bat` 什么都不出现，也没有任何报错。

## 原因

- GitHub 网页编辑器保存的是 **UTF-8 无 BOM**
- Windows PowerShell 5.1 读 `.ps1` 时，**没有 BOM 就按系统 ANSI（中文系统 ＝ GBK）解码**
- 脚本里的中文被解成乱码 → 乱码字节破坏了引号/括号 → 语法解析失败
- 而 `start-widget.bat` 是**隐藏窗口**运行 PowerShell 的，报错看不见，表现就是「启动不了」

实测报错示例（用 `powershell -File whale.ps1` 前台运行才会看到）：

```
At whale.ps1:218 char:57
Unexpected token '\codex-runtimes\...\node.exe' }
```

## 修复：把 BOM 补回来

```powershell
$f = "D:\Tools\deepseek-whale-desktop\whale.ps1"   # 改成你自己的实际路径
$c = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($f, $c, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "已补回 UTF-8 BOM"
```

或者用编辑器保存：

| 编辑器 | 操作 |
|---|---|
| 记事本 | 另存为 → 编码选 **UTF-8 with BOM**（不能选「UTF-8」，那是无 BOM） |
| VS Code | 右下角编码 → **Save with Encoding** → **UTF-8 with BOM** |

验证前 3 个字节应该是 `239,187,191`：

```powershell
([System.IO.File]::ReadAllBytes($f))[0..2] -join ','
```

## 结论

**`whale.ps1` 必须保持 UTF-8 with BOM。**
要改它就本地用编辑器改；如果确实要用网页编辑器改，改完记得按上面把 BOM 补回来。

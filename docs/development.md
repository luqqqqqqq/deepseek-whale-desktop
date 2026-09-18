# 开发与验证

[返回项目首页](../README.md) · [文档导航](README.md)

## 源码入口

| 文件 | 职责 |
| --- | --- |
| [`src/host.cs`](../src/host.cs) | WPF 窗口、拖动、屏幕吸附、翻转与锁定 |
| [`src/start.mjs`](../src/start.mjs) | 本地 HTTP 服务、最小 DSH 环境和前端消息桥接 |
| [`src/widget/lib/index.js`](../src/widget/lib/index.js) | 上游路由、配置、余额与资源管理 |
| [`src/widget/lib/accounting.mjs`](../src/widget/lib/accounting.mjs) | 上游记账逻辑 |
| [`src/widget/assets/whale-widget.js`](../src/widget/assets/whale-widget.js) | 上游挂件界面 |
| [`scripts/launch.ps1`](../scripts/launch.ps1) | 服务与预编译宿主的启动、退出协调 |

`src/widget/` 内部保留上游目录关系，其 `.github/` 也是上游归档的一部分，不是本仓库根目录的发布工作流。

## 重新构建宿主

修改 C# 宿主后，在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-host.ps1
```

脚本使用 .NET Framework 4.x 的 `csc.exe`、WPF 程序集和 [`tools/webview2/`](../tools/webview2/) 中的程序集。结果写入忽略的 `build/desktop-host/`，包含 `host.exe` 和所需 Core、Wpf、Loader DLL；不会自动覆盖发布文件。

确认构建成功后，先正常退出桌宠，再用以下命令更新默认启动入口使用的宿主：

```powershell
Copy-Item -LiteralPath build/desktop-host/host.exe -Destination releases/v2.0.0/host.exe
Copy-Item -Path build/desktop-host/*.dll -Destination releases/v2.0.0/
```

随后运行根目录 `start-widget.bat`，验证修改的桌面行为。发布目录被 Git 跟踪，替换后的二进制需要单独检查再提交。当前目录 `v2.0.0` 对应既有桌面版本；原有 Git 标签拼写为 `V2.0.0`。

修改 JavaScript 不需要重新编译 C# 宿主，退出后重新启动即可加载。

## 路径与预编译兼容

- 启动脚本根据自身位置定位仓库根目录，不依赖打开终端时的工作目录。
- `src/start.mjs` 通过自身文件地址查找相邻 `widget/`，默认数据路径为根目录 `.dshw-data/`。
- `releases/v2.0.0/host.exe` 与运行 DLL 保持同目录，已有二进制无需为目录整理重新编译。
- 宿主通过 `AppDomain.CurrentDomain.BaseDirectory` 选择 `wv2-profile/` 和 `host.log`，这些文件留在 EXE 相邻目录并被忽略。
- `tools/webview2/` 保存编译及辅助 PowerShell 外壳需要的程序集；`releases/v2.0.0/` 保存部署所需副本。
- 自启条目保存脚本绝对路径。项目移动或升级目录结构后需要重新运行开启自启脚本。

## 端口配置

Node.js 服务读取环境变量 `PORT`，默认 9876。整套启动链需要同步调整 `scripts/launch.ps1` 的 `$port` 与 `src/host.cs` 的默认 URL，然后重新构建、替换宿主。若使用辅助外壳，还需调整 `scripts/shell.ps1` 的默认 URL。

## 本地检查

在仓库根目录可执行 JavaScript 语法检查，不会启动服务：

```powershell
node --check src/start.mjs
node --check src/widget/lib/index.js
node --check src/widget/lib/accounting.mjs
node --check src/widget/assets/whale-widget.js
```

PowerShell 脚本可通过解析器检查语法，无需运行启动、停止或自启逻辑。移动发布文件、上游源码及资源时应核对内容哈希；验证启动链时可替换进程操作为测试桩，检查它选择的文件与工作目录。

语法、文件路径和内容一致性检查不能代替真实编译或桌面交互验证。仓库没有自动化桌面交互测试，透明窗口、缩放、多屏和 WebView2 兼容性仍需实机检查。

## 功能边界

桌面服务只提供最小 DSH 兼容环境，没有派发 DSH 会话事件。每轮消耗提示、任务结束音及会话 token 驱动的额度累计，需要事件集成才能使用。上游本地会话统计逻辑仍在源码中，仓库尚未提供桌面环境下的完整兼容性验证记录。

当前启动器的强制停止按进程名称生效，启动时也会尝试终止占用端口的进程；验证路径时不要直接运行这些分支。运行数据中的 API Key 为明文，勿随测试材料或项目分发。

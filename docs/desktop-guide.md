# 桌面版使用与开发

[返回项目首页](../README.md)

本文对应桌面版 2.0.0。`source/` 保存上游 DSH 插件，其安装方式和运行环境与本仓库的 Windows 桌面启动器不同。

## 启动与退出

双击根目录的 [`start-widget.bat`](../start-widget.bat)。启动链为：

```text
start-widget.bat → start-widget.vbs → launch.ps1
                                      ├── Node.js → start.mjs
                                      └── host.exe → WebView2 本地页面
```

启动器优先寻找 PATH 中的 `node`，随后尝试一个固定的 Codex 内置运行时路径。该备用路径不保证在其他机器上存在，因此建议单独安装受支持的 Node.js LTS 并加入 PATH。

默认页面地址为 `http://127.0.0.1:9876/`。启动器会等待本地服务响应，再启动桌面窗口；窗口关闭后，它会结束自己启动的 Node.js 服务。

- **正常退出：** 点击鲸鱼使窗口获得焦点，再按 `Esc`。
- **强制停止：** [`stop-widget.bat`](../stop-widget.bat) 调用当前启动器的 `-Stop` 分支，会终止所有名为 `node`、`host` 的进程。它可能影响其他程序，不适合在其他 Node.js 任务运行时使用。
- **端口占用：** 当前启动器会尝试终止占用 9876 端口的进程。启动前先检查端口用途，避免干扰其他服务。

[`start-shell.bat`](../start-shell.bat) 只打开辅助 PowerShell 外壳，要求本地服务已经运行；日常使用请从 `start-widget.bat` 进入。

## 数据与配置

| 位置 | 用途 |
| --- | --- |
| `.dshw-data/` | 默认的数据目录，保存设置、账本、自定义角色、音效等 |
| `.dshw-data/credentials.json` | 明文 API 凭据 |
| `wv2-profile/` | WebView2 用户数据和缓存 |
| `server.log`、`server.err.log` | 本地服务输出与错误 |
| `launch.err.log` | 启动环境或宿主缺失等错误 |
| `host.log` | 桌面宿主日志 |

可在启动进程的环境中设置 `DSH_HOME`，更改服务数据目录。该目录中仍会保存明文凭据；如果改为仓库内其他路径，需要自行加入 `.gitignore`。备份或分享项目时，不要把数据目录、缓存及日志一起上传。

API Key 在鲸鱼菜单中配置。其他厂商的余额和额度功能取决于其接口；没有余额接口的厂商不会因为添加模型就自动获得真实余额。

桌面服务注册了上游插件，但没有派发 DSH 会话事件。上游文档中的每轮消耗提示、任务结束音及会话 token 驱动的额度更新需要事件集成才能使用。上游本地会话统计逻辑仍在源码中，仓库尚未提供桌面环境下的完整兼容性验证记录。

## 开机自启

- 开启：双击 [`enable-autostart.bat`](../enable-autostart.bat)。
- 关闭：双击 [`disable-autostart.bat`](../disable-autostart.bat)。

[`autostart.ps1`](../autostart.ps1) 写入当前用户的 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`，条目名为 `DSHWhaleV2`。移动或重命名项目目录后，需要重新开启自启以更新路径；删除项目之前先关闭自启。

## 重新构建宿主

修改 [`host.cs`](../host.cs) 后，在仓库根目录打开 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-host.ps1
```

脚本使用 .NET Framework 4.x 的 `csc.exe`、WPF 程序集及 [`webview2/`](../webview2/) 中的 WebView2 程序集。它会覆盖根目录 `host.exe`，并复制运行所需的 Core、Wpf 和 Loader DLL。编译前先退出桌宠，避免文件被占用。

代码位置：

| 文件 | 负责内容 |
| --- | --- |
| [`host.cs`](../host.cs) | 透明窗口、屏幕工作区、拖动、吸附、翻转与锁定 |
| [`start.mjs`](../start.mjs) | 本地 HTTP 服务、最小 DSH 环境、前端与宿主的消息桥接 |
| [`source/lib/index.js`](../source/lib/index.js) | 上游路由、配置、余额与资源管理 |
| [`source/lib/accounting.mjs`](../source/lib/accounting.mjs) | 上游记账逻辑 |
| [`source/assets/whale-widget.js`](../source/assets/whale-widget.js) | 上游挂件界面 |

修改 JavaScript 不需要重新编译 C# 宿主，退出后重新启动即可加载。请保留上游版权、许可证和素材来源说明。

## 端口配置

Node.js 服务读取环境变量 `PORT`，默认值为 9876。单独修改它并不能让整套启动链切换端口；还需要同步修改 [`launch.ps1`](../launch.ps1) 的 `$port` 以及 [`host.cs`](../host.cs) 的默认 URL，并重新编译宿主。若使用辅助外壳，也需要调整 [`shell.ps1`](../shell.ps1) 的默认 URL。

## 故障排查

| 现象 | 检查方法 |
| --- | --- |
| 双击没有窗口 | 确认 `node --version` 可用、根目录存在 `host.exe`，查看 `launch.err.log` 和服务日志 |
| 服务无法启动 | 查看 `server.err.log`，检查 9876 端口及项目目录写入权限 |
| 窗口空白或无法交互 | 确认 WebView2 Runtime 已安装、根目录 DLL 完整，再查看 `host.log` |
| 余额提示没有密钥 | 在鲸鱼菜单里配置 `DEEPSEEK_API_KEY`，检查当前使用的数据目录 |
| 每轮消耗或任务结束音未触发 | 桌面兼容环境没有提供 DSH 会话事件，参见上面的能力说明 |
| 自启失效 | 项目目录移动后重新执行开启自启脚本 |

反馈问题时请附 Windows、Node.js 和 WebView2 版本及必要的错误片段；去掉日志中的密钥和个人路径。

# 快速开始

[返回项目首页](../README.md) · [文档导航](README.md)

## 准备环境

| 环境 | 要求 |
| --- | --- |
| Windows | Windows 10 / 11，具备 .NET Framework 4.x |
| WebView2 | 安装 [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)，仅安装 Edge 不代表该运行时一定可用 |
| Node.js | 建议使用仍受支持的 [LTS 版本](https://nodejs.org/)，`node --version` 应能返回版本号 |

将整个仓库放到固定、可写的目录。服务仅使用 Node.js 内置模块，不需要执行 `npm install`。启动器优先使用 PATH 中的 `node`，随后尝试一个固定的 Codex 运行时路径；该备用路径不保证在其他机器存在。

## 启动与退出

双击根目录的 [`start-widget.bat`](../start-widget.bat)。启动链为：

```text
start-widget.bat → scripts/start-widget.vbs → scripts/launch.ps1
                                              ├── Node.js → src/start.mjs
                                              └── releases/v2.0.0/host.exe
```

服务地址为 `http://127.0.0.1:9876/`。启动器等待服务响应后打开桌面窗口，窗口关闭后结束自己启动的 Node.js 服务。

- **正常退出：** 点击鲸鱼使窗口获得焦点，再按 `Esc`。
- **强制停止：** [`scripts/stop-widget.bat`](../scripts/stop-widget.bat) 会终止所有名为 `node`、`host` 的进程，可能影响其他程序；运行其他 Node.js 任务时请使用正常退出方式。
- **端口占用：** 当前启动器会尝试终止占用 9876 端口的进程，启动前先确认该端口没有被其他程序使用。

[`scripts/start-shell.bat`](../scripts/start-shell.bat) 只打开辅助 PowerShell 外壳，不启动服务。日常使用根目录入口即可。请保持 `src/`、`scripts/`、`releases/` 以及发布目录内的 EXE/DLL 完整。

## 数据与配置

在鲸鱼菜单中配置 `DEEPSEEK_API_KEY`，或进入「模型」设置添加其他厂商。余额与额度取决于对应厂商接口；没有余额接口的厂商不会自动获得真实余额。

| 默认位置 | 用途 |
| --- | --- |
| `.dshw-data/` | 仓库根目录下的设置、账本、自定义角色、音效等 |
| `.dshw-data/credentials.json` | 明文 API 凭据，不应上传或随项目分发 |
| `releases/v2.0.0/wv2-profile/` | 预编译宿主的 WebView2 用户数据和缓存 |
| `releases/v2.0.0/host.log` | 预编译宿主日志 |
| `server.log`、`server.err.log` | 仓库根目录下的服务输出与错误 |
| `launch.err.log` | 仓库根目录下的启动环境错误 |

可通过启动进程的 `DSH_HOME` 环境变量更改服务数据目录。如果指定仓库内其他目录，需要自行加入 `.gitignore`。数据、缓存和日志默认已被忽略；备份或分享时仍需检查其中的凭据和个人信息。

从旧目录结构更新时，根目录 `.dshw-data/` 的路径保持不变。预编译宿主现在位于 `releases/v2.0.0/`，会在该目录建立新的 WebView2 缓存；旧根目录缓存不影响启动。

## 开机自启

- 开启：双击 [`scripts/enable-autostart.bat`](../scripts/enable-autostart.bat)。
- 关闭：双击 [`scripts/disable-autostart.bat`](../scripts/disable-autostart.bat)。

[`scripts/autostart.ps1`](../scripts/autostart.ps1) 写入当前用户的 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`，条目名为 `DSHWhaleV2`。移动项目或从旧目录结构更新后，重新开启自启以更新脚本路径；删除项目之前先关闭自启。

## 故障排查

| 现象 | 检查方法 |
| --- | --- |
| 双击没有窗口 | 检查 `node --version`、发布目录的 `host.exe`，查看 `launch.err.log` 和服务日志 |
| 服务无法启动 | 查看 `server.err.log`，检查 9876 端口及项目目录写入权限 |
| 窗口空白或无法交互 | 确认 WebView2 Runtime 与宿主相邻 DLL 完整，查看发布目录的 `host.log` |
| 余额提示没有密钥 | 在鲸鱼菜单里配置凭据，确认当前数据目录 |
| 每轮消耗或任务结束音未触发 | 桌面兼容环境没有派发 DSH 会话事件，见[开发与验证](development.md#功能边界) |
| 自启失效 | 重新执行 `scripts/enable-autostart.bat` 更新启动路径 |

反馈问题时请提供 Windows、Node.js 和 WebView2 版本及必要错误片段，去掉密钥和个人路径。

# DeepSeek Whale 桌宠 V2.0.0（独立桌面版）

完全复用原版 [MeteorNOX/DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget) 的网页前端（`whale-widget.js`），用本地 Node 服务 + WebView2（Edge）做成的 **Windows 独立桌面悬浮鲸鱼**。功能、操作方式、外观与原版一致，并额外加入了桌面端需要的吸附、翻转、锁定、避让等能力。

## 一、主要功能

- 透明无边框、始终置顶，桌面上只显示鲸鱼本体（含气泡/菜单）。
- 点击鲸鱼右上角菜单按钮可打开菜单/气泡；按住身体拖动；按 `Esc` 关闭。
- 拖动自动限制在当前屏幕内，不会跑出桌面或钻到任务栏下面。
- 宿主窗口会自动收缩到刚好包住鲸鱼和菜单，不遮挡桌面其它区域。
- 鲸鱼在菜单里调大调小时，窗口会跟着一起变大变小。
- **屏幕级吸附与翻转**：拖到屏幕边缘附近自动吸附贴边，并按“吸附与翻转”里的翻转线决定朝左/朝右（菜单 → 吸附与翻转 → 自定义）。
- **锁定位置**：菜单里勾选后，鲸鱼固定在当前屏幕位置不可拖动（状态会记住）。
- **避让滚动条**：菜单里开启后，鲸鱼在屏幕右侧按设定像素留出距离。

## 二、环境要求

- Windows 10 / 11
- Microsoft Edge（WebView2 运行时，系统一般自带）
- Node.js（启动本地服务用；装过 Codex 的机器自带，无需单独安装）

## 三、安装与启动

1. 把整个文件夹放到固定位置（例如 `D:\Tools\deepseek-whale-v2`）。
2. 双击 `start-widget.bat` 启动。

停止方式：

- 在鲸鱼上按 `Esc`（或关闭挂件窗口），本地服务会自动结束；
- 或双击 `stop-widget.bat`。

## 四、配置 API Key

第一次打开后，在挂件菜单里按提示配置 `DEEPSEEK_API_KEY`（余额），或用菜单里的“模型”设置添加其它厂商。

> ⚠️ 凭据以明文保存在本机 `.dshw-data/credentials.json`，**不要提交、不要上传、不要分享**；该目录已在 `.gitignore` 中忽略。

## 五、开机自启

- 开启：双击 `enable-autostart.bat`
- 关闭：双击 `disable-autostart.bat`

## 六、重新构建宿主（可选）

只有当你修改了 `host.cs`（宿主窗口逻辑）时才需要重新编译：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-host.ps1
```

编译需要 .NET Framework 4.x 自带的 `csc.exe`（Windows 自带），以及 `webview2/` 目录下的 WebView2 程序集。编译成功后 `host.exe` 及运行所需 DLL 会自动就位。

## 七、目录结构

```text
deepseek-whale-v2/
├─ start.mjs             # 本地 Node 服务 + 页面注入（吸附/翻转/锁定/避让配置桥接）
├─ host.cs              # 宿主窗口源码（WPF 透明窗口 + WebView2 + 拖动/吸附/翻转/锁定）
├─ host.exe             # 已编译的宿主窗口
├─ build-host.ps1       # 编译 host.cs → host.exe
├─ launch.ps1           # 启动/停止编排（Node 服务 + host.exe）
├─ start-widget.bat     # 启动入口
├─ stop-widget.bat      # 停止入口
├─ enable-autostart.bat / disable-autostart.bat / autostart.ps1   # 开机自启
├─ source/              # 原版插件源码（宿主 + 前端 whale-widget.js + 素材）
├─ webview2/            # WebView2 程序集（重新编译时引用）
├─ Microsoft.Web.WebView2.Core.dll / Wpf.dll / WebView2Loader.dll  # 运行时 DLL
└─ .dshw-data/          # 运行数据（设置、凭据、角色、音效等；不要提交）
```

## 八、常见问题

- **双击没反应**：确认装了 Edge 和 Node；查看 `server.log` / `server.err.log`。
- **端口被占用**：修改 `start.mjs` 里的 `PORT`（默认 9876），并同步修改 `launch.ps1`。
- **窗口看不到 / 点不到**：确认 Edge WebView2 运行时存在；先尝试重新启动。
- **凭据泄露风险**：`.dshw-data/credentials.json` 为明文，请勿随项目分发。

## 九、版本

- 当前版本：**V2.0.0**
- 原版前端上游：[MeteorNOX/DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)

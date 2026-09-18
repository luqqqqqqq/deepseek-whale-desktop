# DeepSeek Whale Desktop

<div align="center">

**把小鲸鱼放到 Windows 桌面上**<br>
*A Windows desktop companion built with Node.js, WPF and WebView2*

<img src="source/assets/DSniang1.png" alt="小鲸鱼内置角色素材" width="240" />

[快速开始](#快速开始) · [使用与开发](docs/desktop-guide.md) · [更新日志](CHANGELOG.md)

</div>

## 项目简介

DeepSeek Whale Desktop 将 [MeteorNOX 的余额小鲸鱼挂件](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget) 封装为透明、置顶的 Windows 桌面窗口。可以拖动鲸鱼、查看余额、编辑气泡、切换角色和音效，并通过桌面宿主实现屏幕边缘吸附、翻转、位置锁定和滚动条避让。

当前桌面版本为 **2.0.0**，见 [`VERSION`](VERSION)。仓库包含桌面宿主源码、启动脚本、预编译宿主和前端资源。`source/` 中保留的上游插件版本为 0.3.1，两者各自使用原有版本号。

DeepSeek Whale Desktop wraps the upstream whale widget in a standalone Windows window. It includes the local Node.js server, desktop host source, prebuilt host and widget assets. Features that depend on DSH conversation events require additional integration.

## 主要特性

| 功能 | 说明 |
| --- | --- |
| 桌面悬浮 | 透明无边框、始终置顶，窗口随鲸鱼和菜单尺寸调整 |
| 屏幕交互 | 拖动、边缘吸附、水平翻转、位置锁定、右侧滚动条避让 |
| 气泡与外观 | 自定义气泡内容、缩放、角色图片、图片与音效资源 |
| 余额显示 | 配置凭据后查询 DeepSeek 余额；其他厂商取决于对应接口 |
| 本地运行 | Node.js 提供本地页面，WPF + WebView2 承载窗口，无需安装 DSH |
| 启动管理 | 提供启动入口和当前用户的开机自启开关 |

## 快速开始

### 准备环境

- **Windows 10 / 11**，具备 .NET Framework 4.x。
- **Microsoft Edge WebView2 Runtime**；安装 Edge 不代表运行时一定可用，可从 [Microsoft 官方页面](https://developer.microsoft.com/microsoft-edge/webview2/) 获取。
- **Node.js**：建议使用仍受支持的 LTS 版本，`node --version` 应能正常返回。服务使用 Node.js 内置模块，不需要执行 `npm install`。

### 启动桌宠

1. 克隆或下载整个仓库，放到固定且可写的目录。
2. 双击 [`start-widget.bat`](start-widget.bat)。保持 `host.exe`、根目录 DLL、`source/` 与启动脚本的相对位置不变。
3. 在鲸鱼菜单中配置 `DEEPSEEK_API_KEY`，或进入「模型」设置添加其他厂商。
4. 按住鲸鱼身体拖动；需要退出时，先让鲸鱼窗口获得焦点，再按 `Esc`。启动器会随后结束对应的本地服务。

默认使用本机 `127.0.0.1:9876`。当前启动器会尝试终止占用该端口的进程，启动前请确认该端口未被其他程序使用。`stop-widget.bat` 会按名称终止所有 `node` 和 `host` 进程，运行其他 Node.js 程序时请使用上面的 `Esc` 退出方式。

配置、角色和音效等数据默认写入 `.dshw-data/`。其中 `credentials.json` **以明文保存 API Key**；该目录已忽略，不应随仓库分发。详见[数据与配置](docs/desktop-guide.md#数据与配置)。

## 目录结构

```text
.
├── start-widget.bat / .vbs       # 日常启动入口
├── launch.ps1                   # 启动本地服务和桌面宿主
├── start.mjs                    # 本地 HTTP 服务与桌面消息桥接
├── host.cs / host.exe           # WPF + WebView2 宿主源码与预编译程序
├── build-host.ps1               # 重新编译宿主
├── enable-autostart.bat          # 开启当前用户的开机自启
├── disable-autostart.bat         # 关闭开机自启
├── webview2/                    # 编译所需的 WebView2 程序集
├── source/                      # 上游插件源码、前端、素材及原始说明
├── docs/desktop-guide.md         # 使用、开发与故障排查
├── CHANGELOG.md
└── VERSION
```

根目录 WebView2 DLL 是宿主运行依赖，`webview2/` 内的副本用于编译。`start-shell.bat` 与 `shell.ps1` 是单独打开网页外壳的辅助入口，不会自动启动本地服务。

## 使用与开发

- [启动、退出、自启和故障排查](docs/desktop-guide.md)
- [重新构建桌面宿主](docs/desktop-guide.md#重新构建宿主)
- [上游插件说明](source/README.md)与[素材来源](source/PROVENANCE.md)
- [版本变更记录](CHANGELOG.md)

## 当前限制

- 面向 Windows；没有提供 macOS 或 Linux 桌面宿主。
- 桌面服务只提供最小 DSH 兼容环境，尚未接入 DSH 的会话事件。因此上游说明中的每轮对话消耗、任务结束音及依赖会话事件的自动额度累计，不能直接视为桌面版已支持的能力。
- 余额、额度和定价依赖厂商接口及配置；本地观测统计不能代替厂商账单。
- 仓库没有自动化桌面交互测试；透明窗口、缩放和多屏行为仍需要实际桌面验证。

## 致谢与许可证

感谢 [MeteorNOX/DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget) 及其贡献者提供挂件源码和资源。

`source/` 中的上游代码保留 [MIT 许可证](source/LICENSE)及原始版权声明；图片、动图和音效的许可范围另见 [PROVENANCE.md](source/PROVENANCE.md)。WebView2 组件遵循 Microsoft 对应条款。

**本仓库尚未为新增的桌面宿主和启动脚本声明顶层许可证。** 上游的 MIT 许可不代表仓库内所有文件都已按 MIT 授权。

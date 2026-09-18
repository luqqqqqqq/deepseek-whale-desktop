# DeepSeek Whale Desktop v2.0.0

<div align="center">

**把小鲸鱼放到 Windows 桌面上**<br>
*A Windows desktop companion built with Node.js, WPF and WebView2*

[快速开始](#快速开始) · [文档导航](#文档导航) · [更新日志](CHANGELOG.md)

</div>

<p align="center">
  <img src="src/widget/assets/DSniang1.png" alt="小鲸鱼内置角色素材" width="240" />
</p>

## 项目简介

DeepSeek Whale Desktop 将 [MeteorNOX 的余额小鲸鱼挂件](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget) 封装为透明、置顶的 Windows 桌面窗口。可以拖动鲸鱼、查看余额、编辑气泡、切换角色和音效，并通过桌面宿主实现屏幕边缘吸附、翻转、位置锁定和滚动条避让。

桌面版本为 **2.0.0**，见 [`VERSION`](VERSION)；内置上游插件保留其 0.3.1 版本。仓库提供宿主源码、启动脚本、预编译宿主及前端资源。

DeepSeek Whale Desktop wraps the upstream whale widget in a standalone Windows window. It includes a local Node.js server, desktop host source, prebuilt host and widget assets. Features that depend on DSH conversation events require additional integration.

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

1. 准备 Windows 10 / 11、.NET Framework 4.x、[WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) 和受支持的 [Node.js LTS](https://nodejs.org/)。
2. 克隆或下载整个仓库，放到固定且可写的目录；不需要执行 `npm install`。
3. 双击根目录 [`start-widget.bat`](start-widget.bat)，在鲸鱼菜单中配置 API 凭据。
4. 退出时让鲸鱼窗口获得焦点，再按 `Esc`。

启动前确认本机 9876 端口没有被其他程序使用。环境检查、强制停止行为、明文凭据存储和开机自启说明见[快速开始指南](docs/getting-started.md)。

## 目录结构

```text
.
├── src/
│   ├── host.cs                 # WPF + WebView2 桌面宿主
│   ├── start.mjs               # 本地服务与桌面消息桥接
│   └── widget/                 # 上游插件源码、前端、素材及许可
├── scripts/                    # 启动、停止、自启及构建脚本
├── releases/v2.0.0/             # 原有预编译宿主与运行 DLL
├── tools/webview2/              # 编译及辅助外壳使用的 WebView2 程序集
├── docs/                       # 使用、开发和文档导航
├── start-widget.bat             # 日常启动入口
├── README.md
├── CHANGELOG.md
├── VERSION
└── .gitignore
```

编译结果写入忽略的 `build/desktop-host/`，用户数据仍保存在根目录 `.dshw-data/`。预编译宿主的 WebView2 缓存与日志保留在其相邻目录，详见[数据与配置](docs/getting-started.md#数据与配置)。

## 文档导航

| 文档 | 内容 |
| --- | --- |
| [文档入口](docs/README.md) | 使用与开发资料索引 |
| [快速开始](docs/getting-started.md) | 环境、启动、数据、自启及故障排查 |
| [开发与验证](docs/development.md) | 源码、宿主构建、目录约定及验证范围 |
| [上游插件说明](src/widget/README.md) | 原始 DSH 插件能力与使用说明 |
| [素材来源](src/widget/PROVENANCE.md) | 图片、动图与音效的来源及许可范围 |
| [更新日志](CHANGELOG.md) | 桌面版发布记录与后续整理 |

## 开发与验证

构建入口为 [`scripts/build-host.ps1`](scripts/build-host.ps1)，需要 .NET Framework 的 C# 编译器；完整步骤见[开发指南](docs/development.md)。

- 路径调整涉及本地服务及启动脚本，预编译宿主和上游实现保持原有内容。
- 仓库没有自动化桌面交互测试；透明窗口、缩放和多屏行为需要实际桌面验证。
- 桌面服务没有接入 DSH 会话事件；上游的每轮消耗、任务结束音及会话事件驱动的自动额度累计需要额外集成。
- 余额、额度和定价取决于厂商接口及配置，本地统计不能代替厂商账单。
- 当前宿主面向 Windows，没有提供 macOS 或 Linux 桌面程序。

## 致谢

感谢 [MeteorNOX/DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget) 及其贡献者提供挂件源码和资源。桌面宿主使用 Microsoft WPF 与 WebView2。

## 许可证

本仓库尚未为新增的桌面宿主和启动脚本声明顶层许可证。

`src/widget/` 中的上游代码保留 [MIT 许可证](src/widget/LICENSE)及原始版权声明；图片、动图和音效的许可范围另见 [PROVENANCE.md](src/widget/PROVENANCE.md)。WebView2 组件遵循 Microsoft 对应条款。

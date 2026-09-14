# 小鲸鱼余额桌宠（DeepSeek Balance Whale Desktop）

DeepSeek 余额小鲸鱼 **独立桌面版**：常驻 Windows 桌面的透明置顶挂件，实时显示 DeepSeek 账户余额、今日已用与峰谷时段。

> 这是**独立运行**的版本，不需要 DeepSeek Harness（DSH），也不需要 Electron / Chromium —— 用 Windows 原生 WPF 实现，开箱即用。

> **本项目修改自** [MeteorNOX/DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)（MIT License）。原项目是 DeepSeek Harness（DSH）的网页挂件插件，本项目把它改造为**不依赖 DSH 的独立 Windows 桌面版**：界面与交互用 WPF 原生重写，移除了 Electron / Chromium 依赖，并新增了位置锁定、异步刷新等改进。

当前版本：**v1.0.0**

## 下载

### 方式 A：下载发行包（推荐，不需要 git）

1. 打开本仓库的 **[Releases](https://github.com/luqqqqqqq/deepseek-whale-desktop/releases)** 页面
2. 在最新版本（Latest）的 Assets 里下载 `deepseek-whale-desktop-vX.Y.Z.zip`
3. 解压到任意目录，例如 `D:\Tools\deepseek-whale-desktop`
4. 按下面的「配置与运行」创建 `config.json` 并填入自己的 API Key

### 方式 B：克隆仓库

```bash
git clone https://github.com/luqqqqqqq/deepseek-whale-desktop.git
cd deepseek-whale-desktop
```

> ⚠️ 两种方式下载后都**不会带 API Key**必须自己创建并填写。

## 特性

- 🐋 **桌面常驻 + 始终置顶**：透明无边框窗口，贴在桌面最上层，不占用任务栏
- 💰 **实时余额**：每 60 秒自动刷新，单击鲸鱼立即刷新
- 📊 **今日已用**：小鲸鱼记账模式（按余额差值自动记账），跨天归零并保留 30 天
- ⏰ **峰谷时段**：显示当前为高峰 / 空闲时段
- 🖱️ **拖动 + 位置记忆 + 位置锁定**：可拖到任意边缘且不会拖出屏幕，记住位置，可锁定防误拖
- 💬 **气泡 + 随机台词**：点击气泡切换随机台词，5 秒后自动收起
- 🎵 **按压音效**：按下 / 松开鲸鱼播放音效（内置「小黄鸭」「音效1」两套）
- ⚙️ **完整设置面板**：大小滑块、音效、音量、用量模式、峰谷文案、气泡开关、位置锁定
- 🚀 **开机自启**：一次点击注册，登录后自动出现

## 环境要求

- Windows 10 / 11
- 系统自带的 Windows PowerShell 5.1 与 .NET Framework（无需额外安装）
- 可选：Node.js —— 仅当 PowerShell 无法直连余额接口时作为兜底，一般用不到

**不需要** Electron、Chromium、Python 或任何第三方运行时。

## 安装与运行

1. 将整个文件夹放到任意位置（例如 `D:\Tools\deepseek-whale-desktop`）
2. 把 `config.example.json` 复制为 `config.json`，填入你的 DeepSeek API Key：

   ```json
   { "DEEPSEEK_API_KEY": "sk-你的密钥" }
   ```

   Key 在 <https://platform.deepseek.com> 获取，用于读取账户余额（只读，不会发起任何扣费操作）
3. 双击 `start-widget.bat` 启动（黑窗口一闪即退），鲸鱼出现在屏幕右下角

## 开机自启

双击一次 `enable-autostart.bat` 即可（写入当前用户的注册表启动项，无需管理员权限）。

取消自启：删除注册表 `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run` 下的 `DSHWhaleWidget`。

## 使用说明

| 操作 | 效果 |
|---|---|
| 鼠标移到鲸鱼上 | 右上角浮现 `≡` 设置按钮 |
| 点击 `≡` | 打开设置面板 |
| 单击鲸鱼 | 立即刷新余额 |
| 点击气泡 | 切换随机台词 |
| 按住鲸鱼拖动 | 移动位置（不会拖出屏幕） |
| 设置里勾选「锁定」 | 固定位置，防止误拖 |
| 设置面板底部「退出挂件」 | 关闭挂件 |

## 设置项

| 设置 | 说明 |
|---|---|
| 大小 | 0.6–2.5 倍缩放 |
| 音效 | 小黄鸭 / 音效1 |
| 音量 | 0–100% |
| 用量 | 小鲸鱼记账（推荐） / 实时·令牌 |
| 峰谷 | 默认（空闲/高峰时段） / 梁文峰谷（梁文谷/梁文峰） / !?强强?!（!?谷谷?!/!?峰峰?!） |
| 气泡 | 开 / 关 |
| 锁定 | 锁定后位置不可拖动 |

所有设置保存在 `.dshw-size.json`，重启后自动恢复。

## 工作原理

- 余额来自 DeepSeek 官方接口 `https://api.deepseek.com/user/balance`
- 「今日已用」默认使用**余额差值记账**：每次观测到余额下降，就把差值累计到当天（记录在 `.dshw-usage.json`，保留 30 天）
- 界面使用 WPF 原生绘制（透明分层窗口），不依赖任何浏览器内核
- 网络请求在后台线程执行，**不会阻塞界面**，连点也不会卡
- 取得余额的链路依次为：PowerShell 直连 → 系统 `curl.exe` → Node.js 兜底

## 已知限制

- 「实时·令牌」模式需要 DeepSeek 平台会话令牌；未提供时会自动回落为记账模式，功能不受影响
- 不包含「每轮对话消耗统计」——该功能依赖 DSH 的会话事件，独立版本无法获取

## 许可证

MIT License，详见 [LICENSE](LICENSE)。

## 来源与致谢

本项目**修改自** [MeteorNOX/DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)（MIT License）：

- 小鲸鱼形象（`DSniang1.png`）、音效（`Ya1/Ya2/D1/D2.mp3`）、随机台词等素材来自原项目
- 余额接口、峰谷定价、记账逻辑等设计参考自原项目
- 本项目的主要改动：把原 DSH 网页插件改为**独立 Windows 桌面程序**（WPF 原生渲染，透明置顶窗口），移除 Electron / Chromium 依赖，重写拖动与位置记忆逻辑，并新增**位置锁定**、后台异步刷新等功能

感谢原作者 [MeteorNOX](https://github.com/MeteorNOX) 的开源工作。原项目同样以 MIT License 发布。

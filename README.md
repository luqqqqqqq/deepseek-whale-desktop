# 小鲸鱼余额桌宠（DeepSeek Balance Whale Desktop）

DeepSeek 余额小鲸鱼**独立桌面版**：常驻 Windows 桌面的透明置顶挂件，显示账户余额、今日已用、峰谷时段，还能统计你本机 Codex 的 token 用量。

不需要 DSH，不需要 Electron / Chromium —— 用 Windows 原生 WPF 实现，双击就能跑。

> 本项目**修改自** [MeteorNOX/DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)（MIT License）。
> 原项目是 DeepSeek Harness（DSH）的网页挂件插件；本项目把它改成**不依赖 DSH 的独立 Windows 桌面程序**，
> 界面与交互用 WPF 原生重写、移除 Electron / Chromium，并新增位置锁定、异步刷新、一键获取令牌、Codex 本地用量统计等改进。

当前版本：**v1.0.0**

---

## 特性

- 💰 **实时余额**：每 60 秒自动刷新，单击鲸鱼立即刷新
- 📊 **今日已用**：两种算法（记账 / 实时·令牌），见「用量模式」一节
- ⛰️ **峰谷时段**：显示当前是高峰还是空闲，并带**距下一次切换的倒计时**；支持三种文案样式
- 🖥️ **Codex 本地用量**：读本机 Codex 会话日志，统计今日 / 本月 / 累计 token（按模型分列）
- 🖱️ **拖动 + 吸附 + 翻转 + 位置锁定**：可拖到任意位置且不会拖出屏幕，松手自动吸附到屏幕边缘；贴左时角色水平镜像；重启后记住位置，可锁定防误拖
- 🗂️ **资源管理**：统一窗口查看 / 预览 / 试听 / 删除自定义角色、音效片段、泡泡图
- 🎵 **按压 / 松开音效（可自定义）**：内置「小黄鸭」「音效1」两套，也可自选两个音频文件作为按下/松开音效，音量可调
- 🔔 **任务结束音**：一轮 Codex 会话结束（本地 token 增加）时播放；内置「Minecraft·经验球」「A」两套，也可自选音频
- 💸 **每轮消耗提示**：一轮 Codex 会话结束自动弹「本轮花了多少」，内容模板、自动关闭秒数可自定义
- 📡 **订阅窗口**：有 ChatGPT 订阅时，Codex 菜单悬停会显示 5h / 周已用百分比与重置时间
- 🐳 **自定义角色**：可以把鲸鱼换成你自己的图片
- 🎚️ **余额预警 / 今日预算**：余额过低、今日已用达到预算时弹气泡提醒
- 📒 **用量记录窗口**：今日 / 近 7 天 / 全部明细，按模型与日期搜索
- 🙈 **可隐藏菜单按钮**：隐藏后桌面端**右键鲸鱼**唤出菜单
- 🔐 **一键获取平台令牌**：双击脚本自动开浏览器抓令牌、验证、写配置（也可手动）
- 🚀 **开机自启**：一次点击注册，登录后自动出现
- ⚙️ **完整设置面板**：大小、音效、音量、任务结束音、用量模式、峰谷文案、气泡、吸附、隐藏按钮、角色、预警、预算、台词、位置锁定

---

## 一、下载

### 方式 A：下载发行包（推荐，不用装 git）

1. 打开 [Releases](https://github.com/luqqqqqqq/deepseek-whale-desktop/releases) 页面
2. 在最新版本的 Assets 里下载 `deepseek-whale-desktop-vX.Y.Z.zip`
3. 解压到任意目录，例如 `D:\Tools\deepseek-whale-desktop`

### 方式 B：克隆仓库

```bash
git clone https://github.com/luqqqqqqq/deepseek-whale-desktop.git
```

> 两种方式都不会附带 API Key，需要你自己建一个 `config.json`（见下一步）。

---

## 二、配置 API Key（必做）

1. 把 `config.example.json` 复制一份，改名成 `config.json`
2. 填上你的密钥（在 <https://platform.deepseek.com> 里创建，只用于读余额，不会产生任何扣费操作）

```json
{
  "DEEPSEEK_API_KEY": "sk-你的密钥",
  "DEEPSEEK_PLATFORM_TOKEN": ""
}
```

`DEEPSEEK_PLATFORM_TOKEN` 是**可选项**：想用「实时·令牌」精确统计今日已用才需要填，留空就用默认的记账模式（见「用量模式」一节）。带不带 `Bearer ` 前缀都行。

**三个坑，请务必注意：**

- `config.json` 必须和 `whale.ps1` 放在**同一个目录**
- JSON 格式很严格：每一项后面要有逗号，最后一项不要逗号，键和值都用英文双引号
- 少一个逗号会让**整个文件失效**（连 API Key 一起读不进来，余额和用量都会显示不出来）

---

## 三、启动

双击 **`start-widget.bat`**（黑窗口一闪即退，属正常现象），小鲸鱼出现在桌面上。

想让它在开机后自动出现：双击一次 **`enable-autostart.bat`**。
取消自启：删除注册表 `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run` 下的 `DSHWhaleWidget`。

---

## 四、用量模式

挂件的「今日已用」有两种算法，在菜单里的「用量」切换：

| 模式 | 说明 |
|---|---|
| 小鲸鱼记账（默认） | 用**余额差值**估算：看到余额下降多少就记多少。不需要任何额外配置；币种切换时自动重置基准，不会把换币种的差额算进用量。缺点：跨设备、跨渠道的用量会漏记 |
| 实时·令牌 | 直接读 DeepSeek 平台的官方用量接口，**精确到每个模型、每个小时**，再乘峰谷价换算成金额 |

### 定价表

金额按 **CNY / 百万 tokens** 计，`[空闲时段, 高峰时段]`；高峰 = 工作日 9:00–12:00、14:00–18:00（北京时间），空闲价为高峰价的一半；**2026-08-23 起周末全天按谷价**。

| 模型 | 缓存命中 | 缓存未命中 | 输出 |
|---|---|---|---|
| `deepseek-flash`（DeepSeek-V4.1-Flash） | 0.02 / 0.04 | 1 / 2 | 4 / 8 |
| `deepseek-v4-pro`（V4 Pro） | 0.15 / 0.30 | 4.5 / 9.0 | 13.5 / 27.0 |

> 旧模型名 `deepseek-v4-flash`、`deepseek-v4-flash-vision-exp` 以及 `deepseek-chat` / `deepseek-reasoner` 仍可调用，都按 Flash 价计费。
> 价格写在 `whale.ps1` 顶部的 `$script:BasePrice` / `$script:ProPrice`，官方调价时改这两处。

### 峰谷与倒计时

气泡第二行会显示当前时段，并带上**距下一次峰/谷切换的倒计时**，例如：

```
今日已用 ¥2.74  ·  高峰时段（1小时20分后转空闲）
```

峰谷文案支持三种样式，在菜单「峰谷」里选：**默认**（空闲时段 / 高峰时段）、**梁文峰谷**（梁文谷 / 梁文峰）、**!?强强?!**（!?谷谷?! / !?峰峰?!）。

### 实时·令牌需要一份「平台会话令牌」

两种拿法：

**拿法 1：一键自动（推荐）**——双击 **`自动获取令牌.bat`**

- 脚本需要 Node.js + [Playwright](https://playwright.dev/)：用过 Codex 会自动找到自带运行时；否则先执行 `npm i -g playwright`（需先装 Node.js）
- 第一次运行会弹出一个浏览器窗口（用独立配置，**不会动你平时的浏览器**），登录一次 <https://platform.deepseek.com> 即可
- 登录成功后自动抓令牌、调一次用量接口验证、写进 `config.json`；之后每次都是后台静默完成
- 行为保证：只有**真能读到用量**的令牌才会写入；会保留原有字段并顺手修掉 JSON 语法错误；只读用量，不碰你账号里的任何东西
- 还没有 `config.json` 时，脚本会按 `config.example.json` 自动建一份

**拿法 2：手动（自动版失败时用）**——F12 控制台

1. 用你平时的浏览器登录 <https://platform.deepseek.com>
2. 按 `F12` → 切到 **Console（控制台）**
3. 把 `抓取平台令牌.js` 的内容整段粘贴进去，回车
4. 把它给出的那行填进 `config.json` 的 `DEEPSEEK_PLATFORM_TOKEN`

然后重启挂件（右键 → 退出挂件 → 再双击 `start-widget.bat`），菜单 → **用量** → **实时·令牌**。

> 平台会话令牌会过期（一般重新登录平台后失效）。失效了重跑一次 `自动获取令牌.bat`；令牌失效或没配置时，挂件自动落回记账模式，不影响使用。

---

## 五、Codex 本地用量统计

设置面板最上面有一行 **Codex**，显示「今日 / 本月 / 累计」token，鼠标悬停能看到各模型的明细。

- **数据来源**：本机 `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` 和 `archived_sessions/`，只读本地文件
- **不联网、不需要密钥**，也不会写入 `~/.codex`
- **口径**：优先用日志里累计量（`total_token_usage`）的**差值**累加，天然避免同一轮多条记录重复计数；分量按该事件的 `last_token_usage` 比例拆分；模型归属由 `turn_context.payload.model` 判定
- **缓存**：只把聚合结果和文件 `size/mtime` 存到 `.dshw-codex.json`，之后刷新很快
- **依赖 Node.js**：Codex 自带，所以一般不用装；没装 Node.js 时这一行会显示提示
- **小提示**：正在进行的会话日志文件被 Codex 独占锁住，统计会跳过它、下次刷新再读，所以「今日」数字会略滞后于当前这轮对话

---

## 六、使用说明

| 操作 | 效果 |
|---|---|
| 鼠标移到鲸鱼上 | 右上角浮现 `≡` 设置按钮 |
| 点击 `≡` | 打开设置面板 |
| 单击鲸鱼 | 立即刷新余额 |
| 点击气泡 | 切换随机台词 |
| 按住鲸鱼拖动 | 移动位置（不会拖出屏幕，松开后记住位置） |
| 设置里勾选「锁定」 | 固定位置，防止误拖 |
| 右键鲸鱼 | 打开设置面板（隐藏 `≡` 按钮后也可以这样唤出） |
| 设置面板底部「退出挂件」 | 关闭挂件 |

---

## 七、设置项

| 设置 | 说明 |
|---|---|
| Codex | 今日 / 本月 / 累计 token（悬停看模型明细） |
| 大小 | 0.6–2.5 倍缩放 |
| 音效 | 小黄鸭 / 音效1 / 自定义（自选按下、松开两个音频） |
| 音量 | 0–100% |
| 任务结束音 | 关闭 / Minecraft·经验球 / A / 自定义 |
| 每轮消耗 | 开 / 关；「自动关(秒)」0 表示不自动收起；「提示模板」支持 `{cost}` `{tokens}` `{model}` |
| 用量 | 小鲸鱼记账（默认） / 实时·令牌 |
| 峰谷 | 默认 / 梁文峰谷 / !?强强?!（气泡第二行带倒计时） |
| 气泡 | 开 / 关 |
| 吸附 | 松手时自动吸到屏幕边缘（贴左时角色镜像） |
| 隐藏按钮 | 隐藏 `≡` 按钮，改用右键鲸鱼唤出菜单 |
| 锁定 | 锁定后位置不可拖动 |
| 角色 | 选择自己的图片替换鲸鱼；「默认」恢复原样 |
| 余额预警 | 余额低于该值就提醒；0 或留空 = 关闭 |
| 今日预算 | 今日已用达到该值就提醒；0 或留空 = 关闭 |
| 台词 | 「编辑台词」打开 `custom-lines.txt`，「重载」重新读取 |

所有设置保存在 `.dshw-size.json`，重启后自动恢复。

菜单里「工具」入口：**资源管理…**（统一查看 / 试听 / 删除角色、音效片段、泡泡图）和**用量记录…**（今日 / 近 7 天 / 明细搜索）。

---

## 八、常见问题

**Q：双击 `start-widget.bat` 什么都没出现？**
多半是 `whale.ps1` 丢了 UTF-8 BOM（PowerShell 5.1 读中文脚本会乱码报错，而启动脚本是隐藏窗口运行的，所以看不到报错）。
解决办法见 [`BOM注意.md`](BOM注意.md)，**别用 GitHub 网页编辑器改 `.ps1`**。

**Q：余额正常，但「今日已用」一直是 0？**
按顺序查这几点：

1. `config.json` 里有没有 `DEEPSEEK_PLATFORM_TOKEN`
2. **JSON 上一行末尾有没有漏逗号**（少一个逗号，整个文件都读不进来，连 API Key 一起失效）
3. 令牌是不是被写成了 `Bearer xxx`（会变成 `Bearer Bearer xxx`，接口直接拒绝；现在的版本两种写法都兼容）
4. `config.json` 是不是和 `whale.ps1` 在同一目录
5. 菜单里的用量模式选的是不是「实时·令牌」

看挂件目录下的 `run.log` 可以确诊：

- `balance=74.22` → 余额读取成功
- `usage-token=2.74 tokens=11411048` → 实时·令牌成功
- `usage-token-failed(回落记账)` → 令牌失效或格式不对
- `codex=今日 15.0M · 本月 632.0M · 累计 5.1B` → Codex 统计成功
- 完全没有 `usage-token` 字样 → 没配令牌

**Q：Codex 那一行的「今日」数字和实际感觉对不上？**
正在进行的会话文件被 Codex 锁住，统计会跳过它、下一次刷新再读；等当前轮结束、文件释放后数字才会追平。

**Q：任务结束音什么时候响？**
一轮本机 Codex 会话结束（本地日志里 token 数增加）时响一次。因为正在写入的会话文件会被 Codex 锁住，要等这轮结束、文件释放后才会检测到，所以会有几秒延迟；没在菜单里选音效、或把「音效」关了就不会响。

**Q：这个挂件安全吗？**
它只做读操作：读余额（`api.deepseek.com/user/balance`）、读用量（`platform.deepseek.com/api/v0/usage/...`）、读本机 Codex 日志。不会发送、修改或删除你账号里的任何内容，也不会把数据发到第三方。密钥和令牌只存在本机的 `config.json` 里。

**Q：需要装 Node.js 吗？**
余额和用量一般不用（PowerShell 直连，失败时用系统 `curl.exe` 兜底）。只有「一键获取令牌」和「Codex 用量统计」会用到 Node.js；Codex 自带 Node，所以这两个功能在 Codex 机器上开箱即用。

---

## 九、文件说明（哪些不能上传）

| 文件 | 作用 | 能不能提交到仓库 |
|---|---|---|
| `whale.ps1` | 主程序 | ✅ |
| `getbalance.js` / `getusage.js` | 余额 / 用量的 Node 兜底 | ✅ |
| `codexstats.js` | 读本机 Codex 会话日志，统计 token | ✅ |
| `resource-manager.ps1` | 资源管理窗口 | ✅ |
| `usage-viewer.ps1` | 用量记录窗口（今日 / 近 7 天 / 明细搜索） | ✅ |
| `自动获取令牌.js` / `.bat` | 一键获取平台令牌 | ✅（不含任何个人信息） |
| `抓取平台令牌.js` | 控制台手动抓令牌 | ✅ |
| `start-widget.bat` / `start.bat` / `launch.ps1` / `start-widget.vbs` | 启动脚本 | ✅ |
| `enable-autostart.bat` / `.ps1` | 开机自启 | ✅ |
| `.gitattributes` | 保证 `.bat`/`.ps1` 检出为 CRLF | ✅ |
| `config.example.json` | 配置模板 | ✅ |
| `assets/` | 形象、按压/松开音效、任务结束音、泡泡图 | ✅ |
| **`config.json`** | **含你的 API Key 和令牌** | ❌ **绝对不能提交** |
| `.dshw-size.json`、`.dshw-usage.json`、`.dshw-pos.json`、`.dshw-codex.json`、`.dshw-bubble.json`、`.dshw-api.json`、`.dshw-credentials.json`、`custom-lines.txt`、`whale-roles/`、`whale-audio/`、`whale-bubble-imgs/`、`run.log` | 你本机的设置 / 自定义资源 / 凭据 / 运行数据 | ❌ 不用提交 |

仓库里的 `.gitignore` 已经把这些排除掉了；`git status` 里看不到它们就是正常的。

---

## 十、工作原理

- 余额：`https://api.deepseek.com/user/balance`
- 今日已用（记账模式）：每次观测到余额下降就把差值累计到当天，记录在 `.dshw-usage.json`，跨天自动归零；币种切换时重置基准
- 今日已用（令牌模式）：`https://platform.deepseek.com/api/v0/usage/by_api_key/amount`，按小时分桶取 token 数，再乘峰谷价换算成金额
- Codex 用量：读 `~/.codex/sessions/**/rollout-*.jsonl` 与 `archived_sessions/`，按「累计 token 差值」分天/模型聚合，缓存到 `.dshw-codex.json`
- 界面：WPF 原生绘制（透明分层窗口），不依赖浏览器内核
- 网络请求全部在后台线程执行，不阻塞界面，连点也不卡
- 取数据的链路：PowerShell 直连 → 系统 `curl.exe` → Node.js 兜底

---

## 十一、与原版的差异 / 已知限制

本项目是原版 DSH 插件的一个**精简独立版**。原版的「角色/音效、任务结束音、吸附翻转、隐藏菜单按钮、余额预警、今日预算、资源管理、每轮消耗提示、订阅窗口、用量记录窗口」都已移植为桌面版等价功能（见上），以下原版能力**暂未移植**：

- 模块化泡泡 / 泡泡编辑器
- 自定义 API（33 个厂商模板）
- 移动端适配（本桌面版面向 Windows 桌面，无移动端）

另外一处「做了但和原版略有差别」：订阅窗口依赖 Codex 日志里的 `rate_limits` 快照，只有 ChatGPT 订阅账号才会有值。

如果原版这些功能里有你想要的，欢迎提需求（Issue）或自行二开。

---

## 十二、维护者：发布一个新的 Release

1. 改完代码，确认 `whale.ps1` 仍是 **UTF-8 with BOM**
2. 打包（不含个人配置文件）：

```powershell
$src = "D:\Tools\deepseek-whale-desktop"   # 改成你自己的目录
$out = "$env:TEMP\deepseek-whale-desktop-v1.0.0.zip"
Compress-Archive -Path "$src\*" -DestinationPath $out
```

3. 在 GitHub 仓库 → **Releases** → **Draft a new release**
4. Tag 填 `v1.0.0`，标题写「v1.0.0」，把上面那个 zip 拖进 Assets
5. Publish release

---

## 许可证

MIT License，详见 [LICENSE](LICENSE)。

## 来源与致谢

本项目**修改自** [MeteorNOX/DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)（MIT License）：

- 小鲸鱼形象（`DSniang1.png`）、音效（`Ya1/Ya2/D1/D2.mp3`）、随机台词等素材来自原项目
- 余额接口、峰谷定价、记账逻辑、Codex 本地统计等设计参考自原项目
- 本项目的主要改动：把原 DSH 网页插件改为**独立 Windows 桌面程序**（WPF 原生渲染、透明置顶窗口），
  移除 Electron / Chromium 依赖，重写拖动与位置记忆逻辑，并新增**位置锁定**、后台异步刷新、
  **实时·令牌用量模式**、**一键获取平台令牌**、**峰谷倒计时**与** Codex 本地用量统计**等功能

感谢原作者 [MeteorNOX](https://github.com/MeteorNOX) 的开源工作。原项目同样以 MIT License 发布。

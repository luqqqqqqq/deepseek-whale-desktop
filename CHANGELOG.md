# 更新日志

## 未发布

- 统一首页章节和文档入口，将源码、脚本、预编译宿主分别整理到 `src/`、`scripts/` 和 `releases/v2.0.0/`。
- 更新相对路径，保留根目录启动入口和原有用户数据位置；本地宿主构建结果写入 `build/desktop-host/`。
- 重写项目首页，补充桌面版启动、开发、数据位置和故障排查文档。
- 明确桌面版与内置上游插件的版本、会话事件支持和许可证范围。
- 说明启动器的端口处理、强制停止行为和实际运行依赖。

## V2.0.0（2026-09-18）

独立桌面版首发：把原版网页挂件封装为 Windows 透明置顶悬浮鲸鱼。

### 新增

- 透明无边框、始终置顶的桌面悬浮窗口
- 点击菜单/气泡、按住身体拖动、`Esc` 关闭
- 宿主窗口自动收缩到刚好包住鲸鱼和菜单，并随鲸鱼缩放
- 屏幕级「吸附与翻转」（复用菜单里的吸附与翻转配置）
- 「锁定位置」开关（菜单内，状态持久化）
- 「避让滚动条」屏幕级支持
- 本地 Node 服务 + WebView2 承载，依赖 Node.js、.NET Framework 和 WebView2 Runtime
- 开机自启

### 说明

- 运行数据与凭据保存在 `.dshw-data/`，其中 `credentials.json` 为明文 API Key，请勿提交或分享。
- 原版前端上游：[MeteorNOX/DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)

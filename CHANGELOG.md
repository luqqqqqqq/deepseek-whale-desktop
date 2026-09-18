# 更新日志 / Release Notes

## V2.0.0（2026-09-18）

独立桌面版首发：把原版网页挂件封装为 Windows 透明置顶悬浮鲸鱼。

### 新增

- 透明无边框、始终置顶的桌面悬浮窗口
- 点击菜单/气泡、按住身体拖动、`Esc` 关闭
- 宿主窗口自动收缩到刚好包住鲸鱼和菜单，并随鲸鱼缩放
- 屏幕级「吸附与翻转」（复用菜单里的吸附与翻转配置）
- 「锁定位置」开关（菜单内，状态持久化）
- 「避让滚动条」屏幕级支持
- 本地 Node 服务 + WebView2（Edge）承载，无外部依赖
- 开机自启

### 说明

- 运行数据与凭据保存在 `.dshw-data/`，其中 `credentials.json` 为明文 API Key，请勿提交或分享。
- 原版前端上游：[MeteorNOX/DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)

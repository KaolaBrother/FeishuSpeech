# Changelog

## [Unreleased]

### Added
- 热键监控状态现在可被观察：新增 `MonitoringState`（`.stopped` / `.active` / `.failed`），菜单栏可实时反映 Event Tap 是否正常运行（issue #5）
- 安全输入检测：终端、1Password 等程序启用安全键盘时，菜单栏显示橙色提示"安全输入已启用，热键暂不可用"（issue #10）

### Fixed
- Event Tap 从主线程移至专用后台线程，避免与 AVCaptureSession 争用主 RunLoop 导致热键丢失（issue #9）
- Event Tap 创建失败或辅助功能权限未授予时，自动按指数退避重试（最长间隔 30 秒），不再硬限 3 次后放弃（issue #5）
- 录音停止后重置 Fn 键状态，防止重启监控时残留的按键状态触发误录（issue #9）
- 剪贴板还原不再与合成 Cmd+V 产生竞争：完整保存/还原所有粘贴板类型，通过 changeCount 轮询确认目标应用已读取后再还原；超时未确认时回退到通知（issue #13）
- 语音识别返回空结果时，不再静默无响应，而是将可观察的 `overlayMessage` 设为提示文字（issue #14）
- 录音最大时长计时器（maxDurationTimer）改用 `.common` 运行循环模式，菜单栏菜单打开时也能正常触发（issue #16）
- Overlay 隐藏动画不再与后续 show() 产生竞争：引入 generation 计数器，过期的 hide 完成回调不会关闭新弹出的 overlay（issue #17）

- 飞书 API 所有直连 IP 失败后自动回退至 URLSession DNS 解析，防止 CDN IP 轮换导致永久失效（issue #3）
- 开机启动功能（设置 → 通用 → 开机启动）
- 菜单栏「重置服务」按钮，手动恢复异常状态
- 连续失败 3 次自动重置 API 服务
- API 错误分类（可重试/不可重试），优化重试策略
- LICENSE 文件（MIT）
- CLAUDE.md 入口文件
- README 常见问题章节
- Kaola-Workflow scaffolding (CLAUDE.md, AGENTS.md redirect, docs/, roadmap)

### Fixed
- Fn 键在转录进行中松开不再启动新的录音会话（issue #6）
- 录音达到最大时长自动停止后，再松开 Fn 键不再产生「无音频数据」错误（issue #7）
- 在权限提示期间多次按下/松开 Fn 键不再导致重复的热键事件处理（issue #8）
- 「重置服务」现在能正确恢复卡住的麦克风：取消或出错后不再出现永久录音失败；`startRecording()` 在启动前重置任何残留会话状态（issue #1）
- NWConnection `.waiting` 状态忽略导致每个不可达 IP 等待 30–75 秒（issue #2）
- 识别中卡死长达 ~150s：30s 超时未正确取消 NWConnection，现使用 `withTaskCancellationHandler` 确保任务取消即时传播（issue #4）
- HTTP 400 错误后应用卡死：token 过期未清除导致重试持续失败
- Speech API 返回 400/401 时自动清除 token 缓存
- URLSession 从 computed property 改为 stored property，避免重复创建
- Token 缓存时间从 7000s 降至 6000s，增加安全余量
- 移除测试中引用已删除 `.armed` 状态的用例

## [0.3.0] - 2025

### Added
- 稳定性大幅优化
- Event Tap 自动恢复机制
- 音频转换兼容性改进（动态格式检测）
- 多显示器支持（Overlay 跟随鼠标屏幕）
- NWPathMonitor 网络状态监测
- API 重试机制（3 次指数退避）
- 错误自动恢复（3 秒后恢复 idle）
- 进程退出时完整资源清理

## [0.2.0] - 2025

### Fixed
- 修复无内置麦克风的 Mac 上启动崩溃

## [0.1.0] - 2025

### Added
- 初始版本
- 按住 Fn 键录音，松开自动识别
- 飞书语音识别 API 集成
- 自动输入文字到光标位置
- macOS 菜单栏应用
- 辅助功能和麦克风权限管理

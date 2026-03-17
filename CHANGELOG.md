# Changelog

## [Unreleased]

### Added
- 开机启动功能（设置 → 通用 → 开机启动）
- 菜单栏「重置服务」按钮，手动恢复异常状态
- 连续失败 3 次自动重置 API 服务
- API 错误分类（可重试/不可重试），优化重试策略
- LICENSE 文件（MIT）
- CLAUDE.md 入口文件
- README 常见问题章节

### Fixed
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

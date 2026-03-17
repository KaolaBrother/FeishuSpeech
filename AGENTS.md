# AGENTS.md - FeishuSpeech 项目指南

本文档为 AI 编码助手提供项目上下文和编码规范。

## 项目概述

FeishuSpeech 是一个 macOS 菜单栏应用，通过飞书语音识别 API 实现本地语音输入功能。用户按住 Fn 键 **0.3 秒后** 开始录音，松开后自动识别并输入文字到当前光标位置。

- **平台**: macOS 13.0+
- **语言**: Swift 5.9+
- **UI 框架**: SwiftUI (Menu Bar App)
- **架构**: MVVM + Services 层

## 构建/运行/测试命令

```bash
# 用 Xcode 打开项目
open FeishuSpeech.xcodeproj

# 命令行构建 (Debug)
xcodebuild -scheme FeishuSpeech -configuration Debug build

# 命令行构建 (Release)
xcodebuild -scheme FeishuSpeech -configuration Release build

# 运行测试
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test

# 运行 SwiftLint
swiftlint

# 构建产物位置
# ~/Library/Developer/Xcode/DerivedData/FeishuSpeech-xxx/Build/Products/Debug/FeishuSpeech.app

# 安装到 Applications
cp -R ~/Library/Developer/Xcode/DerivedData/FeishuSpeech-xxx/Build/Products/Release/FeishuSpeech.app /Applications/
```

## 项目结构

```
FeishuSpeech/
├── App/
│   ├── FeishuSpeechApp.swift    # @main 入口，MenuBarExtra 配置
│   └── AppDelegate.swift        # 应用生命周期，权限检查，开机启动同步
├── Controllers/
│   └── OverlayWindowController.swift # 浮动提示窗口管理 (NSPanel)
├── Models/
│   ├── AppSettings.swift        # 用户设置 (Codable)，含开机启动选项
│   ├── RecordingState.swift     # 录音状态枚举
│   └── SpeechResult.swift       # API 请求/响应模型
├── Services/
│   ├── FeishuAPIService.swift   # 飞书 API 调用 (actor)，含网络监测、超时、重试和 resetState()
│   ├── AudioRecorder.swift      # 音频录制 (AVCaptureSession + AVAudioConverter)
│   ├── HotKeyService.swift      # 全局快捷键监听，状态机实现，自动恢复
│   ├── HotKeyState.swift        # 热键状态枚举
│   ├── LoginItemService.swift   # 开机启动管理 (SMAppService)
│   ├── PermissionManager.swift  # 权限管理
│   └── TextInputSimulator.swift # 文字输入模拟
├── ViewModels/
│   └── MainViewModel.swift      # 主状态管理，含错误恢复、超时和连续失败自动重置
├── Views/
│   ├── MenuBarView.swift        # 菜单栏下拉视图，含重置服务按钮
│   ├── SettingsView.swift       # 设置窗口，含开机启动开关
│   ├── PermissionView.swift     # 权限状态视图
│   └── RecordingOverlayView.swift # 浮动提示视图
├── Resources/
│   └── Assets.xcassets          # 图标资源
├── Info.plist                   # 应用配置，包含麦克风权限描述
└── FeishuSpeech.entitlements    # 应用权限配置

FeishuSpeechTests/
├── HotKeyServiceTests.swift     # 热键状态机测试
└── MockURLProtocol.swift        # 网络请求 Mock 工具

配置文件/
├── .swiftlint.yml               # SwiftLint 配置
├── .github/workflows/ci.yml     # GitHub Actions CI/CD
├── CLAUDE.md                    # 项目入口文件
└── AGENTS.md                    # 本文档
```

## 核心功能

### Fn 键状态机

HotKeyService 使用状态机处理 Fn 键事件：

```
idle ──[Fn按下]──> pending ──[0.3s]──> recording ──[松开Fn]──> transcribing ──> idle
                       │                    │
                       │ [松开/其他键]       │ [超时60s]
                       └──> cancelled ──> idle
```

- **0.3s 延迟**: Fn 按下后等待 0.3 秒才开始录音（防止误触）
- **组合键排除**: 延迟期间按下其他键会取消触发
- **修饰键排除**: Fn+Cmd/Opt/Ctrl/Shift 不会触发

### 浮动提示

进入 recording 状态时，在**当前鼠标所在屏幕**中央显示 "🎤 可以开始说话..." 浮动提示。

### 音频处理流程

1. AVCaptureSession 捕获麦克风输入 (设备原生格式)
2. 动态检测格式 (采样率、位深、声道)
3. AVAudioConverter 转换为 16kHz 16-bit PCM mono
4. 数据缓冲到预分配内存 (2MB)
5. 停止时提取 PCM 数据发送给飞书 API

### API 错误处理与重试

FeishuAPIService 使用 `isRetriable` 属性区分错误类型：
- **可重试**: timeout, connectionFailed, networkError, httpError(400/401)（token 已自动清除）, httpError(5xx)
- **不可重试**: networkUnavailable, authFailed, recognitionFailed, invalidResponse, unknown

Speech API 返回 400/401 时自动清除 token 缓存，确保重试使用新 token。

### 崩溃恢复

- 连续失败 3 次自动调用 `FeishuAPIService.resetState()` 重置所有状态
- 菜单栏提供「重置服务」按钮供手动恢复
- 错误状态 3 秒后自动恢复 idle

### 开机启动

使用 `SMAppService.mainApp`（macOS 13.0+）管理开机启动：
- `LoginItemService.setEnabled()` 注册/注销
- 设置页面提供开关
- 应用启动时同步状态

### 稳定性保护

| 保护机制 | 值 | 说明 |
|---------|-----|------|
| Fn 延迟 | 0.3s | 防止误触 |
| 录音最大时长 | 60s | 自动停止并发送 |
| Buffer 上限 | 2MB | 防止内存溢出 |
| API 超时 | 30s | 请求超时保护 |
| API 重试 | 3次 | 指数退避重试 |
| 错误恢复 | 3s | 自动恢复 idle |
| 连续失败重置 | 3次 | 自动重置 API 服务 |
| Token 缓存 | 6000s | 留 1200s 安全余量 |
| 转换错误上限 | 10次 | 超过则停止录音 |
| Event Tap 重试 | 3次 | 自动恢复监控 |

## 代码风格规范

### Import 排序

按以下顺序导入，每组之间空一行：

```swift
import Foundation
import AppKit
import AVFoundation
import Combine
import SwiftUI
import os.log
```

### 命名约定

- **类型**: PascalCase (`MainViewModel`, `AudioRecorder`)
- **属性/方法**: camelCase (`isRecording`, `startMonitoring()`)
- **私有属性**: 无下划线前缀 (`audioBuffer`, `eventTap`)
- **静态常量**: camelCase (`storageKey`, `shared`)
- **枚举**: PascalCase cases (`.idle`, `.recording`, `.transcribing`)

### Logger 使用

每个文件顶部声明私有 logger：

```swift
private let logger = Logger(subsystem: "com.feishuspeech.app", category: "CategoryName")
```

日志级别：
- `.info()` - 正常流程
- `.warning()` - 预期但需注意的情况
- `.error()` - 错误情况

### ViewModel 模式

```swift
@MainActor
class MainViewModel: ObservableObject {
    @Published var status: RecordingState = .idle

    private let serviceName = Service.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
    }
}
```

### Service 模式

单例 + ObservableObject 或 actor：

```swift
// 普通服务（需要 ObservableObject）
class HotKeyService: ObservableObject {
    static let shared = HotKeyService()
    @Published private(set) var state: HotKeyState = .idle
    private init() {}
}

// 并发安全服务（使用 actor）
actor FeishuAPIService {
    static let shared = FeishuAPIService()
    private var cachedToken: String?
}

// 纯静态服务
enum LoginItemService {
    static var isEnabled: Bool { ... }
    static func setEnabled(_ enabled: Bool) { ... }
}
```

### 数据模型

使用 `Codable` 和 `Sendable`：

```swift
nonisolated struct SpeechResponse: Decodable, Sendable {
    let code: Int
    let msg: String
    let data: RecognitionData?

    enum CodingKeys: String, CodingKey {
        case code, msg
        case recognitionText = "recognition_text"
    }
}
```

### 错误处理

定义嵌套的 `LocalizedError` enum，含 `isRetriable` 属性：

```swift
enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case authFailed(String)
    case timeout

    var isRetriable: Bool {
        switch self {
        case .timeout, .connectionFailed, .networkError:
            return true
        case .httpError(let code):
            return code == 400 || code == 401 || (500...599).contains(code)
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无效响应"
        case .httpError(let code): return "HTTP 错误: \(code)"
        case .authFailed(let msg): return "认证失败: \(msg)"
        case .timeout: return "请求超时"
        }
    }
}
```

### SwiftUI 视图

```swift
struct SettingsView: View {
    @ObservedObject var viewModel: MainViewModel
    @AppStorage("key") private var value = defaultValue

    var body: some View {
        Form {
            Section("标题") {
                // 内容
            }
        }
        .formStyle(.grouped)
    }
}
```

### 异步模式

```swift
// async/await with timeout
let result = try await withTimeout(seconds: 30) {
    try await service.performAction()
}

// Combine
service.$state
    .sink { [weak self] state in
        self?.handleState(state)
    }
    .store(in: &cancellables)
```

## 测试

### 测试文件位置

- `FeishuSpeechTests/HotKeyServiceTests.swift` - 热键状态机测试
- `FeishuSpeechTests/MockURLProtocol.swift` - 网络请求 Mock

### 测试模式

```swift
@MainActor
final class HotKeyServiceTests: XCTestCase {
    private var sut: HotKeyService!

    override func setUp() async throws {
        sut = HotKeyService.shared
    }

    func test_initialState_isIdle() {
        XCTAssertEqual(sut.state, .idle)
    }
}
```

### 运行测试

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test
```

## 权限配置

### Info.plist

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要麦克风权限来录制语音</string>
<key>LSUIElement</key>
<true/>
```

### Entitlements

```xml
<key>com.apple.security.automation.apple-events</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

## 内存管理

- 使用 `[weak self]` 避免循环引用
- Combine 订阅存储在 `cancellables`
- 音频 buffer 预分配 2MB 容量，避免动态扩容
- 录音结束时 `removeAll(keepingCapacity: true)` 保留容量供下次使用
- 应用启动和录音前调用 `forceCleanup()` 释放残留资源
- 应用退出时完整清理所有资源

## 线程安全

- UI 更新必须在主线程 (`@MainActor` 或 `DispatchQueue.main.async`)
- `FeishuAPIService` 使用 `actor` 保证线程安全
- 音频回调在 `audioQueue` 后台队列
- Buffer 操作使用 `bufferQueue` 串行队列保护
- Overlay 动画在主线程执行

## 关键常量

| 常量 | 值 | 文件 | 说明 |
|-----|-----|------|------|
| `delayInterval` | 0.3s | HotKeyService.swift | Fn 键延迟时间 |
| `maxRecordingDuration` | 60s | MainViewModel.swift | 最大录音时长 |
| `errorRecoveryDelay` | 3s | MainViewModel.swift | 错误自动恢复延迟 |
| `maxConsecutiveFailures` | 3 | MainViewModel.swift | 连续失败自动重置阈值 |
| `requestTimeout` | 30s | FeishuAPIService.swift | API 请求超时 |
| `maxRetries` | 3 | FeishuAPIService.swift | API 重试次数 |
| `retryDelay` | 1s | FeishuAPIService.swift | 重试间隔基数 |
| Token 缓存 | 6000s | FeishuAPIService.swift | Token 缓存有效期 |
| `targetSampleRate` | 16000 | AudioRecorder.swift | 目标采样率 |
| `maxRecordingSeconds` | 60s | AudioRecorder.swift | 录音时长限制 |
| `estimatedMaxBufferSize` | 2MB | AudioRecorder.swift | Buffer 预分配大小 |
| `maxConversionErrors` | 10 | AudioRecorder.swift | 最大转换错误数 |
| `maxRestartRetries` | 3 | HotKeyService.swift | Event Tap 重启重试 |

## CI/CD

项目使用 GitHub Actions 进行 CI：
- `.github/workflows/ci.yml` - 构建和测试
- `.swiftlint.yml` - SwiftLint 配置

## 已实现的稳定性优化

### 1. 状态机简化
移除了未使用的 `armed` 状态，状态机简化为 `pending -> recording -> transcribing`。

### 2. Event Tap 自动恢复
- 超时禁用后自动重新启用
- 用户输入禁用后自动重启监控
- 创建失败时指数退避重试（最多3次）

### 3. 音频转换兼容性
- 动态检测输入格式（采样率、位深、声道数）
- 支持 32-bit Float 和 16-bit Int 输入
- 转换错误计数，超过阈值停止处理
- Buffer 溢出保护

### 4. 多显示器支持
Overlay 显示在鼠标所在的活跃屏幕，而非固定主屏幕。

### 5. 网络异常处理
- NWPathMonitor 实时监测网络状态
- 离线时提前拒绝请求
- 网络恢复后自动清除 token 缓存
- 区分错误类型（离线、超时、连接失败）
- 使用 `isRetriable` 分类决定是否重试
- 重试次数增加到 3 次

### 6. HTTP 400/401 恢复
- Speech API 返回 400/401 时清除 token 缓存
- 重试时自动获取新 token
- 连续失败 3 次自动重置全部服务状态
- 菜单栏提供手动重置按钮

### 7. 开机启动
- 使用 SMAppService.mainApp 管理（macOS 13.0+）
- 设置页面开关 + 应用启动时同步

### 8. 进程资源清理
- 应用退出时完整清理音频资源
- 释放 Event Tap
- 释放 AVCaptureSession

## 常见任务

### 添加新的 API 端点

1. 在 `SpeechResult.swift` 添加请求/响应模型
2. 在 `FeishuAPIService.swift` 添加新方法
3. 使用现有的 token 缓存机制

### 添加新的设置项

1. 在 `AppSettings.swift` 添加属性
2. 在 `SettingsView.swift` 添加 UI
3. 使用 `@AppStorage` 同步 UserDefaults

### 添加新的状态

1. 在 `RecordingState.swift` 添加 case
2. 更新 `icon`、`color`、`text` 计算属性
3. ViewModel 中切换状态

### 添加新的热键状态

1. 在 `HotKeyState.swift` 添加 case
2. 更新 `isActive`、`shouldShowOverlay` 计算属性
3. 在 `HotKeyService` 中处理状态转换
4. 在 `MainViewModel` 中响应新状态

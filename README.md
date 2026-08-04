# FeishuSpeech

macOS 本地语音输入工具，使用飞书语音识别 API。

## 功能

- 🎤 按住 **Fn 键** 0.3 秒开始流式识别
- ⌨️ 按住 Fn 时持续输出：每个符合条件的 journal packet index 只拥有一次原始响应值，本地按响应顺序拼接为不断增长的 UTF-16 frontier，再交给本次交互的唯一输出 owner
- 🔄 按键期间的可恢复流式失败不会立即报错；应用在松开 Fn 前持续使用新会话重试，并保留已录音频的有序回放
- 🎯 松开 **Fn 键** 会在排空前关闭响应/重试/输出准入，只封口按键期间已拥有的 frontier
- 🔒 安全输入和密码框会拒绝输出；捕获目标路径验证原 PID 和精确 AX 元素，无 AX 目标路径在可检测的进程切换时停止，但无法感知同 PID 内的光标移动

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode 15.0 或更高版本

## 快速开始

### 1. 创建飞书应用

1. 访问 [飞书开放平台](https://open.feishu.cn/app)
2. 创建「企业自建应用」
3. 在「权限管理」中开通以下权限：
   - `speech_to_text:speech` - 语音识别
4. 发布应用版本

### 2. 构建

```bash
# 克隆项目
git clone https://github.com/KaolaBrother/FeishuSpeech.git
cd FeishuSpeech

# 用 Xcode 打开
open FeishuSpeech.xcodeproj

# 或命令行构建
xcodebuild -scheme FeishuSpeech -configuration Release build
```

### 3. 安装

```bash
# 复制到 Applications
cp -R build/Build/Products/Release/FeishuSpeech.app /Applications/
```

### 4. 授予权限

首次运行时需要授予：

1. **辅助功能权限** - 系统设置 → 隐私与安全性 → 辅助功能 → 添加 FeishuSpeech
2. **麦克风权限** - 首次录音时系统会自动请求

### 5. 配置 API

点击菜单栏图标 → 设置 → 填入飞书 App ID 和 App Secret

## 使用方法

1. 将光标放在任意输入框中
2. 按住 **Fn 键** 0.3 秒（菜单栏图标变红）
3. 继续按住并说话；每个可用 packet 响应在本次 generation 内按 journal index 只被拥有一次。原始标量会被按响应顺序本地拼接（即使值相同、不相交或修订也一样），生成增长的 UTF-16 frontier。支持 AX 范围的输入框接收该 frontier 的可验证范围替换；已捕获的 final-only 目标绑定原 PID/精确 AX 元素，无 AX 目标则绑定当时的前台 PID，并只投递 frontier 的未见后缀
4. 松开 **Fn 键**，等待“正在完成识别…”结束
5. 松开 Fn 后只封口已有 held frontier。应用会在停止录音和等待网络排空前先关闭响应、重试和输出准入；`action=2`、在途 packet 与任何晚到 partial/final 只能完成既有 owner，不能首次输出、追加、改写、Cmd+V 或复制。发布时一次性/final-only/手动剪贴板回退已全部移除

“自动输入”关闭、文本不安全或无法取得 owner 时仍会记录“已有可用 held 识别”，但不会把“没有输出 frontier”误报为“未识别到内容”或流式失败；这些路径仍然零输入、零改写、零复制。运行时诊断只记录长度、形状、journal index 所有权和类型化结果，不显示或哈希识别文本，也不记录音频、凭据、token、stream ID、目标控件内容或剪贴板内容。

> 最新 build-5 实机证据在 13.55 秒内记录了 66 个 HTTP-200 transaction，而可见输出在一个词后停滞。这证明音频/传输没有在首词后停止，但不能证明响应标量内容、输出所有权结果或目标已接受。飞书与 KaolaTerminal 都只暴露不透明标量，累积/delta/revision 语义仍未验证。本地 272/272 测试通过不代表安装版可见输出成功；`CGEventPostToPid` 没有目标接受确认，Release owner UAT 仍是必需门槛。

## 常见问题

### 辅助功能权限无法授权

系统设置 → 隐私与安全性 → 辅助功能，找到 FeishuSpeech 并开启。如果已开启但仍提示需要授权，尝试先关闭再重新开启，或删除应用重新添加。

### 录音失败 / 未检测到麦克风

确认系统设置 → 隐私与安全性 → 麦克风中已允许 FeishuSpeech 访问麦克风。如果使用外接麦克风，确保设备已连接且在系统偏好设置中被选为输入设备。

### HTTP 400 错误 / 识别持续失败

通常是 API 凭据错误或 token 过期导致。尝试以下步骤：
1. 点击菜单栏图标 → **重置服务**
2. 检查设置中的 App ID 和 App Secret 是否正确
3. 确认飞书应用已开通 `speech_to_text:speech` 权限并已发布

若显示固定提示“认证失败，请检查应用凭据”，说明租户 token 获取阶段已被飞书拒绝；
应用不会把飞书返回的凭据、正文或后端错误详情显示到界面或日志。最新一次记录的 Release
UAT 并非停在该阶段：它已成功取得 token、发送首个 `action=1` 请求并收到 HTTP 200，随后由
旧版客户端的过严响应契约同步拒绝。当前版本已移除该客户端拒绝条件，但仍须由安装版继续
实机确认真正的识别文本、后续 action/final 和目标应用输出。

应用会在连续失败 3 次后自动重置服务状态。

### 识别卡在「识别中」很久

生产热键流程在每个飞书会话内保持严格串行，且任何时刻只有一个活动会话。可恢复失败时，应用保留同一录音与入口，结束失败会话，退避后创建新会话，再从有序音频日志开头串行回放。回放追上实时前沿前不会把每个历史 partial 重复写入目标。这不是整段文件识别回退，也不会并发发送分片。松开 Fn、60 秒上限、重置或睡眠/唤醒会停止新重试的准入。

仅不可恢复的 provider/流式失败会在 Fn 按住期间立即进入终止路径。可恢复失败只写隐私安全的分类诊断，不设置错误状态、不隐藏/重显浮窗，也不发送系统通知。终止性失败会先隐藏屏幕中央的录音浮窗，再对当前会话执行一次清理；
相同错误状态不会重复发布并重新进入清理。安装版仍出现浮窗不消失时，请确认测试的是本次修正后的 Release。

### 没有实时显示文字

部分应用不提供可验证的 Accessibility 选区与范围读取能力。只要能捕获明确的非安全目标，应用就会把原 PID 和精确 `AXUIElement` 绑定到本次按键，并在每次 Unicode 后缀投递前后复核 Secure Input、PID 和该元素；无法捕获/确认 AX 目标时，首个非空 packet 响应会再尝试一次 AX 绑定，仍不可用时绑定当时最前台 PID。两种 append 路径接收的都是协调器按 journal index 一次拥有并拼接的本地增长 frontier，因此 sink 只需发送其未见 UTF-16 后缀。重放不会重新拥有历史 index；先前失败的 index 可在首次成功时拥有一次。切换应用、安全状态、精确元素变化或交付不确定会永久停止后续自动输出，且不删除、不重发、不切换 writer、不复制。无 AX 路径仍无法观测同一 PID 内的光标移动。`CGEventPostToPid` 没有目标接受回执，因此安装版 Release owner UAT 仍是必需门槛；当前只有 272/272 的不启动应用生命周期本地测试通过，不声明真实控件已接受文字。

### 开机启动

设置 → 通用 → 开启「开机启动」开关。也可以在系统设置 → 通用 → 登录项中管理。

## 项目结构

```
FeishuSpeech/
├── App/
│   ├── FeishuSpeechApp.swift    # 入口
│   └── AppDelegate.swift        # 权限检查
├── Models/
│   ├── AppSettings.swift        # 设置
│   ├── RecordingState.swift     # 状态
│   ├── StreamingSpeechModels.swift # 流式事件与音频入口模型
│   └── CursorTextModels.swift   # 光标目标与范围模型
├── Services/
│   ├── HotKeyService.swift      # Fn 键监听
│   ├── AudioRecorder.swift      # 录音与流式 PCM 输出
│   ├── ByteBoundedAudioIngress.swift # 精确字节上限的音频入口
│   ├── FeishuStreamingSession.swift # 严格串行的飞书流
│   ├── AccessibilityClient.swift # 原始目标捕获与安全校验
│   ├── CursorTextSession.swift  # 暂定文本范围替换
│   ├── CurrentFocusAppendSession.swift # 无 AX 范围时的同 PID UTF-16 后缀输出
│   ├── FeishuAPIService.swift   # token 与 HTTP 传输
│   ├── LoginItemService.swift   # 开机启动
│   ├── PermissionManager.swift  # 权限管理
│   └── TextInputSimulator.swift # 文字输入
├── ViewModels/
│   └── MainViewModel.swift      # 状态管理
├── Views/
│   ├── MenuBarView.swift        # 菜单栏
│   ├── PermissionView.swift     # 权限状态
│   └── SettingsView.swift       # 设置
└── Resources/
    └── Assets.xcassets          # 图标
```

## 技术栈

- **语言**: Swift 5.9+
- **UI**: SwiftUI + Menu Bar App
- **音频**: AVCaptureSession + AVAudioConverter（PCM 16kHz mono Int16）
- **全局快捷键**: CGEventTap
- **API**: 飞书流式语音识别 API

## 许可证

MIT

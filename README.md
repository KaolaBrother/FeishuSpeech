# FeishuSpeech

macOS 本地语音输入工具，使用飞书语音识别 API。

## 功能

- 🎤 按住 **Fn 键** 0.3 秒开始流式识别
- ⌨️ 按住 Fn 时持续输出：可验证的 Accessibility 目标会整体替换暂定范围；无法取得 AX 范围时，会在同一前台进程内尽力输出严格递增的 UTF-16 后缀
- 🔄 按键期间的可恢复流式失败不会立即报错；应用在松开 Fn 前持续使用新会话重试，并保留已录音频的有序回放
- 🎯 松开 **Fn 键** 后停止新的重试，完成当前流或保留最后一份可用结果
- 🔒 安全输入和密码框会拒绝输出；AX 路径验证焦点/光标，无 AX 范围路径在可检测的进程切换时停止，但无法感知同 PID 内的光标移动

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
3. 继续按住并说话；支持 AX 范围的输入框会在原始光标处实时替换暂定结果，无 AX 范围时则在 Secure Input 关闭且前台 PID 稳定的前提下尽力追加严格递增的后缀
4. 松开 **Fn 键**，等待“正在完成识别…”结束
5. 已捕获但不支持实时替换的非安全输入框，会在原目标仍然有效时通过粘贴板/Cmd+V 输入一次最终结果。若完全无法捕获或确认 AX 光标/焦点，首个非空结果会再尝试一次 AX 绑定；仍无法建立 live AX 范围时，在同一前台 PID 且 Secure Input 持续关闭的前提下，通过直接 Unicode 事件输出首值及之后未见的 UTF-16 后缀。这个降级路径不能观测同一进程内的光标移动，也不能安全改写已输出文字，因此缩短或分歧的假设会被抑制；全程不删除文字、不写粘贴板。已确认的密码框或 Secure Event Input 始终拒绝输出

“自动输入”关闭时仍会进行流式识别，但不会修改目标输入框或粘贴板。浮窗和日志只显示状态与分类错误，不显示识别文本、音频、凭据、token、stream ID、目标控件内容或剪贴板内容。

> 最新实机证据记录到一个会话先接受两个 HTTP-200 包，随后在 `action=0, sequence=2` 收到 HTTP 200 / 业务码 `10024`；之后的新会话也收到同一业务码。飞书当前公开文档与官方 SDK 没有定义 `10024` 的含义，不应把它断言为限流、包频率或流泄漏。当前修复将它作为本地可恢复策略：已建立的失败流尽力发送一次 `action=3`，按住 Fn 时使用 250 ms 起步、4 s 封顶的指数退避创建新流，并有序回放本次按键已录音频。该新行为尚未完成安装版 owner UAT，不声明真实端到端成功或广泛兼容。

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

部分应用不提供可验证的 Accessibility 选区与范围读取能力。若应用仍能捕获一个明确的非安全目标，会显示“正在聆听，松开后输入…”，并只在原 PID/元素仍有效时通过粘贴板/Cmd+V 尝试一次最终输入；目标失效或交付不确定时改为 copy-only 手动恢复。若连 AX 光标或焦点元素也无法捕获/确认，首个非空 partial 会先再尝试一次 AX 绑定。若仍不可用，应用将当时最前台 PID 绑定到本次按键，先输出整个首值，之后只在新假设的 UTF-16 严格以已输出值开头时发送未见后缀。每次发送前和发送后检查 Secure Input 与前台 PID，切换应用、安全状态或交付不确定会永久停止本次按键的后续自动输出。该路径无法观测同一 PID 内的光标移动；为避免误删，缩短或分歧假设会被抑制，不后退删除、不选择旧文字、不写粘贴板。“自动输入”关闭时完全不输出。

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

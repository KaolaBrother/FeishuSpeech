# FeishuSpeech

macOS 本地语音输入工具，使用飞书语音识别 API。

## 功能

- 🎤 按住 **Fn 键** 0.3 秒开始流式识别
- ⌨️ 在支持安全范围替换的输入框中，识别结果会在说话时更新到按键开始时的光标位置
- 🎯 松开 **Fn 键** 后完成流并提交最终结果；不支持实时替换的输入框使用一次性最终输入
- 🔒 安全输入和密码框会拒绝启动；焦点或光标发生变化时停止自动写入，避免把文字送到错误位置

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
3. 继续按住并说话；支持的输入框会在原始光标处实时替换暂定结果
4. 松开 **Fn 键**，等待“正在完成识别…”结束
5. 已捕获但不支持实时替换的非安全输入框，会在原目标仍然有效时通过粘贴板/Cmd+V 输入一次最终结果；若完全无法捕获或确认 Accessibility 光标/焦点，录音和流式识别仍会继续，并在松开 Fn 后双重检查 Secure Input 与最前台 PID，再通过不接触粘贴板的 Unicode 键盘事件向届时焦点只尝试输入一次，不确认光标位置。普通发送失败或 PID 变化会把结果复制到粘贴板供手动恢复；含控制字符的结果也只复制、不自动输入；已确认的密码框或 Secure Event Input 始终拒绝输出

“自动输入”关闭时仍会进行流式识别，但不会修改目标输入框或粘贴板。浮窗和日志只显示状态与分类错误，不显示识别文本、音频、凭据、token、stream ID、目标控件内容或剪贴板内容。

> UAT 后修正已取代最初“必须先确认 AX 目标才开始录音”的严格门控：无法取得 AX 目标不再阻塞录音或流式识别。后续实机证据已确认首个 `action=1` 请求到达飞书并收到 HTTP 200，但当时客户端因过严校验响应中的 `data`、`stream_id` 和 `sequence_id` 而同步终止。当前版本已按 KaolaTerminal 的已跑通契约放宽响应解析；真实成功识别、后续 action/final 行为，以及不同应用的 Accessibility 差异仍需安装版 Release 继续 owner UAT，尚不声明端到端成功或广泛兼容。

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

生产热键流程使用严格串行的飞书流式请求。建立流后不会重放音频、回退到整段文件识别或并发发送分片；取消、睡眠/唤醒、重置和失败都会先使当前会话代次失效，再清理录音、网络和光标会话。若持续异常，请使用菜单栏的“重置服务”，并检查网络、凭据和飞书应用权限。

终止性的 provider/流式失败会先隐藏屏幕中央的录音浮窗，再对当前会话执行一次清理；
相同错误状态不会重复发布并重新进入清理。安装版仍出现浮窗不消失时，请确认测试的是本次修正后的 Release。

### 没有实时显示文字

部分应用不提供可验证的 Accessibility 选区与范围读取能力。若应用仍能捕获一个明确的非安全目标，会显示“正在聆听，松开后输入…”，并只在原 PID/元素仍有效时通过粘贴板/Cmd+V 尝试一次最终输入；目标失效或交付不确定时改为 copy-only 手动恢复。若连 AX 光标或焦点元素也无法捕获/确认，录音和流式识别不会被拒绝：应用保留不透明响应，松开后对 Secure Input 和最前台 PID 各采样两次，稳定且安全时用直接 Unicode CGEvent 向当时焦点发送非空 final 一次，不使用粘贴板，也不做光标位置确认。普通事件发送失败或 PID 不稳定时改为 copy-only；C0/C1 控制字符同样只复制，并显示固定 2 秒提示。安全状态拒绝时保持 fail-closed，不发送也不复制；“自动输入”关闭时则完全不输出。

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

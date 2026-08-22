# FeishuSpeech

macOS 本地语音输入工具，使用飞书语音识别 API。

## 功能

- 🎤 按住 **Fn 键** 0.3 秒开始流式识别
- 👀 默认开启「输入前预览」：按住 Fn 时，同一预览面板以只读方式显示完整、不透明的流式 snapshot；相同 snapshot 不重复刷新，变长、缩短或修订都整体替换预览
- 🔄 可恢复流式失败不会立即报错；应用在 Fn 按住期间及松开后的 bounded drain 内持续使用新会话重试，并保留已录音频的有序回放
- ✏️ 松开 **Fn 键** 后同一面板保持只读并显示「正在完成识别…」；只有权威 `action=2` 已结算且录音队列屏障通过后，它才转为可编辑草稿
- ✅ 只有点击「输入」或按 **Command+Return** 才会将未裁剪的编辑结果写回开始录音时捕获的原目标；「取消」、Escape 或关闭窗口不写入
- 🔒 审阅路由会绑定原应用身份、精确 AX 元素与原选区；安全输入、密码框、目标漂移或交付不确定均 fail closed，不重定向、不自动重试
- ⚙️ 关闭「输入前预览」可保留原有按住期间连续输出路由；「自动插入文字」的旧语义只在该兼容模式生效
- 🌐 流式识别的租户 token 与 `stream_recognize` 走绑定物理网卡的 keep-alive（bound UDP DNS + `IP_BOUND_IF`），跳过 VPN/TUN；连接失败不再回退系统 URLSession。整文件识别仍走系统 URLSession

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
3. 继续按住并说话；「输入前预览」面板会以只读方式显示最新完整 snapshot，不会在原输入框中边听边改字
4. 松开 **Fn 键**；面板保持同一个实例并转为「正在完成识别…」。松开只关闭采集，录音队列屏障后的尾包、在途请求、可恢复重连和 `action=2` 仍属于同一 generation
5. 权威 `action=2` 结算后，同一面板转为多行编辑器。如果 final 为空但已有可用 snapshot，它会作为草稿并标注「可能不完整」；两者都无内容时不打开空编辑器
6. 编辑后点击「输入」或按 **Command+Return**；普通 Return 只编辑换行。点击「取消」、按 Escape 或关闭窗口会放弃草稿而不写入，纯空白草稿不能确认

默认审阅路由在开始音频/网络工作前捕获原应用和精确输入位置；确认时只尝试向该目标发送一次进程定向 Cmd+V。任何身份、激活、焦点、选区、Secure Input 或交付不确定都不会转向当前焦点或自动重试；非取消失败会将冻结草稿精确复制一次，供用户手动恢复。成功粘贴前会保存剪贴板全部 item/type 数据，只在粘贴后的有界机会内且 `changeCount` 仍属于本次写入时恢复；第三方剪贴板变化永不会被覆盖。

审阅 UI 是独立的第三条异步轴：只读渲染为可取消的 fire-and-forget 主线程观察，不会让录音采集/音频 journal 等待界面，也不会让识别 consumer/重试/回放等待窗口。录音状态浮层仍然只显示状态，没有改成文字预览或编辑器。

如果关闭「输入前预览」，则完整保留 issue #27 的连续输出兼容路由：支持 AX 范围的目标替换本次 hold 拥有的文字；通用键盘路由只替换已输出的 grapheme 尾部，并拒绝 LF/action controls。该模式才使用「自动插入文字」设置；无输出资格时仍然零输入、零改写、零复制。运行时诊断不显示或哈希识别文本，也不记录音频、凭据、token、stream ID、目标控件或剪贴板内容。

> build 6 的隐私安全诊断已确认重复来自把每个新 packet index 的完整 snapshot 错当成 delta 拼接，而非 replay、重连或 transport 失败。当前契约改为完整 snapshot 替换；`CGEventPostToPid` 仍没有目标接受确认，Release owner UAT 仍是必需门槛。

Issue #38 最终候选已通过聚焦测试 59/59，完整套件执行 408 个测试（其中 1 个跳过、0 失败），并通过 strict SwiftLint 与 Debug/Release 构建。这些自动化结果不替代真实麦克风、凭据、WindowServer、Accessibility 恢复和第三方应用 Cmd+V 接收 UAT。

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

### 开了 VPN 后识别不稳定

流式识别在运行时 wifi/wired 网卡上解析 `open.feishu.cn`（bound UDP/53，跳过 `198.18.0.0/15`），再用 `IP_BOUND_IF` 直连，不绑定 `en0`，无 CDN IP 列表。factory/packet/finish 在直连失败时不会 hop 到系统 URLSession（URLSession 会走 VPN DNS 与 TUN）。没有可用物理路径的企业 `includeAllNetworks` VPN 仍可能失败。整文件识别仍走系统 URLSession。

### 识别卡在「识别中」很久

生产热键流程在每个飞书会话内保持严格串行，且任何时刻只有一个活动会话。麦克风采集线不等待飞书 factory：按住期间 PCM 先写入本次 hold 的 `HoldPacketJournal`，识别线再从 journal 发送。可恢复失败时，应用保留同一录音与入口，结束失败会话，退避后创建新会话，再从有序音频日志开头串行回放。回放追上实时前沿前不会把每个历史 partial 重复写入目标。这不是整段文件识别回退，也不会并发发送分片。每次 packet ACK（包括 replay ACK）会把连续失败退避重置到 250 ms；factory、packet send 和 finish 各有 30 秒 watchdog。

松开 Fn 后，录音停止并跨过真实音频回调屏障；从屏障完成起，当前 generation 最多再用 60 秒排空、恢复和取得权威 final。这个预算到期、不可恢复失败或安全/生命周期失效时，会先关闭准入并使 generation 失效，再保留已可靠提交的文字；不确定交付会显示中性保留提示，没有安全输出时才显示固定流式失败。到期后的迟到结果不能再改字。重置、睡眠/唤醒、权限或 Secure Input 变化仍会立即撤销 authority。

仅不可恢复的 provider/流式失败会在 Fn 按住期间立即进入终止路径。可恢复失败只写隐私安全的分类诊断，不设置错误状态、不隐藏/重显浮窗，也不发送系统通知。终止性失败会先隐藏屏幕中央的录音浮窗，再对当前会话执行一次清理；
相同错误状态不会重复发布并重新进入清理。安装版仍出现浮窗不消失时，请确认测试的是本次修正后的 Release。

### 预览框没有实时显示文字

先确认设置 → 录音中的「输入前预览」已开启。审阅路由不会在原输入框里边听边写；它只会在独立预览面板中整体替换最新完整 snapshot。如果开始前无法安全捕获精确原目标，本次审阅交互会在启动音频/网络前 fail closed，而不对后来的当前焦点进行猜测。

关闭「输入前预览」后，应用使用 issue #27 兼容路由。支持 AX 的目标会绑定原 PID 和精确 `AXUIElement`，并直接替换本次 hold 拥有的范围；无法建立 AX 范围时，固定 PID 键盘 owner 以 grapheme-counted Backspace 加 replacement suffix 替换自己已输出的尾部。任何物理输入、目标/安全状态变化或交付不确定均会永久中止该 owner，不回滚、不重发、不复制。

### 启动时弹出钥匙串授权

凭据仍在 login keychain（issue #18 / #36）。开机启动开关只读 UserDefaults，启动时不为此读取钥匙串。#35 的 data-protection 路径已撤回。

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
│   ├── CursorTextModels.swift   # 光标目标、原应用身份与范围模型
│   └── TranscriptionReviewState.swift # 审阅第三轴状态
├── Controllers/
│   ├── OverlayWindowController.swift # 原有状态浮层
│   └── ReviewWindowController.swift # 同一面板的只读/可编辑权限
├── Services/
│   ├── HotKeyService.swift      # Fn 键监听
│   ├── AudioRecorder.swift      # 录音与流式 PCM 输出
│   ├── ByteBoundedAudioIngress.swift # 精确字节上限的音频入口
│   ├── FeishuStreamingSession.swift # 严格串行的飞书流
│   ├── AccessibilityClient.swift # 原始目标捕获与安全校验
│   ├── CursorTextSession.swift  # 暂定文本范围替换
│   ├── CurrentFocusAppendSession.swift # 无 AX 范围时的同 PID snapshot 键盘替换
│   ├── ReviewDestinationDelivery.swift # 原目标捕获、恢复和审阅确认交付
│   ├── FeishuAPIService.swift   # token 与 HTTP 传输
│   ├── LoginItemService.swift   # 开机启动
│   ├── PermissionManager.swift  # 权限管理
│   └── TextInputSimulator.swift # 文字输入
├── ViewModels/
│   └── MainViewModel.swift      # 状态管理
├── Views/
│   ├── MenuBarView.swift        # 菜单栏
│   ├── PermissionView.swift     # 权限状态
│   ├── RecordingOverlayView.swift # 原有录音状态
│   ├── TranscriptionReviewView.swift # 流式预览和多行草稿
│   └── SettingsView.swift       # 审阅/兼容设置
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

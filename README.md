# FeishuSpeech

macOS 本地语音输入工具，使用飞书语音识别 API。

## 功能

- 🎤 按住 **Fn 键** 0.3 秒开始流式识别
- 👀 每次 accepted Fn 交互都进入同一「输入前预览」：面板以只读方式显示完整、不透明的流式 snapshot；相同 snapshot 不重复刷新，变长、缩短或修订都整体替换预览。`reviewBeforeInsert` 的两个历史值都进入此路线
- 🔄 可恢复流式失败不会立即报错；应用在 Fn 按住期间及松开后的 bounded drain 内持续使用新会话重试，并保留已录音频的有序回放。drain 到期时若仍有同 generation、非空、safe 且不超 16,384 UTF-16 的预览（包括 LF），会在清理前保留原面板和精确文本为 durable、非权威的 `ReviewReadOnlyPhase.recovery` 只读恢复面；它没有 Send/qualified Return、编辑或 delivery authority，只有权威 `action=2` 加 recorder barrier 才能进入 `.editable`；不做 append、AX/Unicode/clipboard 输出、retry 或 retarget
- ✏️ 松开 **Fn 键** 后同一面板保持只读并显示「正在完成识别…」；只有权威 `action=2` 已结算且录音队列屏障通过后，它才直接转为可编辑草稿。捕获/录音和识别/provider 是独立异步根，均不等待面板或编辑器
- ✅ 草稿成型后「发送」和符合规则的 **Return/Enter** 立即可用；**Command+Return** 仍是显式快捷键，**Shift+Return/Shift+Enter** 只插入一个换行，输入法组合文本（marked text）中的 Return 交给输入法。「取消」、Escape 或关闭窗口不写入。只有这些真实 UI 确认手势才能开始一次交付
- 🔒 审阅路由优先绑定原应用身份、精确 AX 元素与原选区；普通非安全 AX miss 使用开始交互时捕获的完整原应用和固定 PID。确认前没有 AX setter、目标键盘/CGEvent、pasteboard 读写、copy/paste、直接插入、重试或 retarget；提交 gate 先在短临界区外完成 binding-specific 身份/信任/Secure Input/frontmost 校验，再按 activation→input 顺序只重查 live epoch 与 Command/Shift/Control/Option/Fn/Caps Lock modifiers，最后发送已准备好的 Unicode pair；安全输入、密码框、身份不完整/漂移或交付不确定仍 fail closed
- 🛡️ accessory-app 激活和编辑器 focus 只是 advisory presentation telemetry，不能隐藏或禁用 Send/Return，也不能触发交付。交付使用一个带来源校验、无修饰键的 Unicode down/up 文本对，最多 16,384 个 UTF-16 code units；操作系统没有目标消费确认，因此结果保持可编辑并标记为 submitted-unverified，不能声称目标已经接受文字
- 🖼️ 流式预览与多行编辑器共用 18pt transcript 字体；面板初始尺寸仍为 520×320，最小/最大尺寸仍为 420×240 / 760×600，不因增大字体而放大。只读正文不使用 full-size content view，保持在标题栏和交通灯按钮下方
- ⚙️ 设置中的旧 `reviewBeforeInsert` / `autoInsert` 值仅为 Codable 迁移保留，不能关闭预览或恢复连续/直接输出
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
6. action 2 与 recorder barrier 后，同一面板立即进入 `.editable`，并安装编辑、发送和 Return/Enter 回调；编辑器是否及时成为 first responder 只作为 presentation telemetry，不是确认门槛。用户可点击「发送」、按符合规则的 Return（含数字键盘 Enter）或按 Command+Return 确认。Shift+Return/Shift+Enter 插入一个换行，输入法组合文本（marked text）中的 Return 交给输入法；交付失败或不确定也保留精确草稿，只有用户再次显式确认才会产生新的投递，纯空白草稿不能确认

审阅路由在开始音频/网络工作前捕获完整原应用身份，并优先捕获精确 AX 元素与原选区。普通非安全目标若严格 AX 光标捕获缺失，仍可绑定这个原应用；确认时重新激活该应用，执行两次连续复合 preflight，每次都按 Secure Input（开始）→ raw 捕获 PID → running/frontmost 完整身份 → Secure Input（结束）顺序检查，再只向捕获 PID 发送一个完整 Unicode 文本 down/up 对。此 fallback 证明的是原应用，不是原控件或插入点；任何身份、激活、焦点、选区、Secure Input 或交付不确定都不会转向其他应用、自动复制或自动重试。审阅交付完全不读取、写入或恢复系统剪贴板，也不发送 Cmd+V；目标消费没有操作系统确认，提交后只报告 submitted-unverified 并保留草稿。

审阅 UI 是独立的第三条异步轴：只读渲染为可取消的 fire-and-forget 主线程观察，不会让录音采集/音频 journal 等待界面，也不会让识别 consumer/重试/回放等待窗口。录音状态浮层仍然只显示状态，没有改成文字预览或编辑器。设置不能关闭此路线；旧布尔值仅用于解码/保存迁移，运行时诊断不显示或哈希识别文本，也不记录音频、凭据、token、stream ID、目标控件或剪贴板内容。

> build 6 的隐私安全诊断已确认重复来自把每个新 packet index 的完整 snapshot 错当成 delta 拼接，而非 replay、重连或 transport 失败。当前契约改为完整 snapshot 替换。此前安装候选的图片残留进一步定位到旧 review pasteboard/Cmd+V 恢复竞态：目标没有消费确认，延迟事件可能在恢复图片后才读取剪贴板；受影响候选已停止，剪贴板没有被本次诊断清理或改写。v4 已删除这条交付路径。R4 最终 focused matrix 为 265 passed / 0 skipped / 0 failed，`StreamingMainViewModelTests` 为 105/105，完整 macOS 测试为 483 passed、另有 1 个与产品无关的 live-TCP 环境 skip；这些都不替代真实目标应用 UAT。v3 安装候选仍是失败/open，尚未安装 v4 Release。

Issue #39 最终候选的 40/40 聚焦、423 个执行/1 个跳过/0 个失败，以及 Issue #40 v2/v3 候选结果均为历史证据；当前 R4 的 265 focused / 0 skipped / 0 failed、`StreamingMainViewModelTests` 105/105、完整 483 passed + 1 个无关 live-TCP skip 也不替代真实麦克风、凭据、WindowServer、Accessibility 恢复和第三方应用 Unicode pair 接收 UAT。

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
应用不会把飞书返回的凭据、正文或后端错误详情显示到界面或日志。历史 Release UAT 曾成功
取得 token、发送首个 `action=1` 请求并收到 HTTP 200，随后被旧版客户端的过严响应契约拒绝；
这不是当前 v4 安装版成功声明。当前客户端已移除该拒绝条件，但 replacement Release 仍须由
安装版实机确认真正的识别文本、后续 action/final 和目标应用输出。

应用会在连续失败 3 次后自动重置服务状态。

### 开了 VPN 后识别不稳定

流式识别在运行时 wifi/wired 网卡上解析 `open.feishu.cn`（bound UDP/53，跳过 `198.18.0.0/15`），再用 `IP_BOUND_IF` 直连，不绑定 `en0`，无 CDN IP 列表。factory/packet/finish 在直连失败时不会 hop 到系统 URLSession（URLSession 会走 VPN DNS 与 TUN）。没有可用物理路径的企业 `includeAllNetworks` VPN 仍可能失败。整文件识别仍走系统 URLSession。

### 识别卡在「识别中」很久

生产热键流程在每个飞书会话内保持严格串行，且任何时刻只有一个活动会话。麦克风采集线不等待飞书 factory：按住期间 PCM 先写入本次 hold 的 `HoldPacketJournal`，识别线再从 journal 发送。可恢复失败时，应用保留同一录音与入口，结束失败会话，退避后创建新会话，再从有序音频日志开头串行回放。回放追上实时前沿前不会把每个历史 partial 重复写入目标。这不是整段文件识别回退，也不会并发发送分片。每次 packet ACK（包括 replay ACK）会把连续失败退避重置到 250 ms；factory、packet send 和 finish 各有 30 秒 watchdog。

松开 Fn 后，录音停止并跨过真实音频回调屏障；从屏障完成起，当前 generation 最多再用 60 秒排空、恢复和取得权威 final。这个预算到期、不可恢复失败或安全/生命周期失效时，会先关闭准入并使 generation 失效；已有预览/草稿仍保留在同一面板中，交付不确定显示中性固定反馈，不自动复制、直接输出、重试或换目标。到期后的迟到结果不能再改字；只有用户显式丢弃或生命周期清理才撤销草稿 authority。重置、睡眠/唤醒、权限或 Secure Input 变化仍会立即撤销当次交付 authority，但不以瞬时失败销毁可编辑草稿。

仅不可恢复的 provider/流式失败会在 Fn 按住期间立即进入终止路径。可恢复失败只写隐私安全的分类诊断，不设置错误状态、不隐藏/重显浮窗，也不发送系统通知。终止性失败会先隐藏屏幕中央的录音浮窗，再对当前会话执行一次清理；
相同错误状态不会重复发布并重新进入清理。安装版仍出现浮窗不消失时，请确认测试的是本次修正后的 Release。

### 预览框没有实时显示文字

审阅路由始终开启，不再提供关闭开关。它不会在原输入框里边听边写；只会在独立预览面板中整体替换最新完整 snapshot。它优先捕获精确 AX 目标；若目标是普通非安全控件但严格 AX 光标能力缺失，会绑定开始交互时的完整原应用并继续预览，不会把后来的当前焦点当成新目标。

### 审阅启动时提示「无法确认输入位置」

如果只是普通非安全的历史 final-only/可编辑 AX 目标无法提供严格光标、选区或 settable 属性，当前版本不应再因该能力缺失而显示此提示：审阅应使用绑定原应用的 current-focus fallback。该提示仍可能正确地表示 Secure Input、密码/安全 AX role、辅助功能信任丢失、应用身份字段不完整、PID 重用或身份漂移；这些情况保持 fail closed。fallback 只证明原应用，不证明原控件或 caret；v4 使用固定 PID 的单次 Unicode 文本对，并不声称目标已消费文字，安装版 UAT 仍是确认可见结果的唯一证据。

旧版文档中的“关闭输入前预览”兼容路由属于历史候选行为，当前设置无法恢复它。任何物理输入、目标/安全状态变化或交付不确定都保持 fail closed；当前交互只允许用户在同一审阅面板中编辑、再次显式确认或丢弃，绝不自动重试、复制、粘贴或换目标。

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
│   ├── CursorTextSession.swift  # 保留的 AX 范围替换服务（Issue #40 路由不直接调用）
│   ├── CurrentFocusAppendSession.swift # 固定 PID / 输入干扰 epoch 与事件来源校验
│   ├── ReviewDestinationDelivery.swift # 原目标捕获、安全校验和显式审阅确认交付
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
│   └── SettingsView.swift       # 审阅说明与通用设置（旧路由键仅迁移保留）
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

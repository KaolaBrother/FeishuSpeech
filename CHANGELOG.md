# Changelog

## [Unreleased]

### Added
- 新增完整 snapshot reconciliation：packet replay ownership 与识别状态分离；任意当前焦点目标以 Swift `Character` 最长公共前缀计算恰好所需的 Backspace，再输入 replacement suffix（issue #27）
- 新增按键内韧性流式会话：可恢复的网络/超时/部分 HTTP 和业务码 `10024` 失败会在 Fn 仍按住时以 250 ms 起步、4 s 封顶的指数退避创建新串行会话；同一录音/入口持续捕获，已录分片通过有序 journal 从头回放，已拥有的历史 index 不重复输出（issue #26）
- 新增 generation-scoped 响应输出 ledger：每个符合条件的 journal packet index 只拥有一次原始标量，并按响应顺序拼接为增长的 UTF-16 frontier。相同、不相交和修订值都会作为不同 index 的本地输出策略拼接，不代表已证明飞书供应商语义（issue #26）
- 按住 Fn 0.3 秒后进入光标绑定的飞书流式识别：每次交互由唯一 generation 共同拥有录音、精确字节上限且可感知消费进度的音频入口、严格串行的 Feishu session，以及绑定原始 `AXUIElement` 的文字会话；松开 Fn 或达到 60 秒进入 sealing 并只完成一次（issue #26）
- 已捕获 final-only 和无 AX 目标均在 Fn held 期间接收本地增长 frontier；重放不再重新拥有历史 index，但先前失败的 index 可在首次成功响应时拥有一次（issue #26）
- 本地不启动应用生命周期的完整 XCTest bundle 记录为 272/272 通过；覆盖响应所有权、回放、release 准入、PID/AX/Secure Input/不确定投递和无重发边界（issue #26）
- 热键监控状态现在可被观察：新增 `MonitoringState`（`.stopped` / `.active` / `.failed`），菜单栏可实时反映 Event Tap 是否正常运行（issue #5）
- 安全输入检测：终端、1Password 等程序启用安全键盘时，菜单栏显示橙色提示"安全输入已启用，热键暂不可用"（issue #10）
- 新增 `FeishuAPIServiceTests` 单元测试目标，覆盖直连 HTTP 解析、token 过期时间和取消重试路径（issues #11/#12/#21）
- 扩展 API 与状态机测试覆盖：新增直连 HTTP 异常解析、重试退避、token 缓存复用、Speech 400/401 token 刷新，以及 MainViewModel 与 HotKeyService 协调层重复转录/陈旧错误防护测试（issue #20）
- 新增 `MainViewModelTests` 覆盖 `MonitoringState` 失败映射、恢复清除和 cleanup 订阅释放路径（issues #22/#23/#24）

### Fixed
- 收窄任意目标的键盘替换安全边界：LF/newline 与其他 C0/C1/DEL action controls 在 generic keyboard route claim/post 前被拒绝，避免 Return/submit/execute；verified AX range 仍可把 multiline text 作为数据替换。现有 HID event tap 以锁保护 interference epoch 提供同步权威，并在 arming、事务前、每个 Backspace 之间检查；AppKit local/global monitors 仅作补充且 arm 失败即 fail closed（issue #27）
- 修复 Release 1.0 build 6 在 Fn 按住期间重复识别词：飞书响应现按完整不透明 snapshot 替换，不再按新 journal index 拼接；不同 packet index 返回相同 snapshot 时不产生输出（issue #27）
- 修复较短与中途修订 snapshot 的任意目标输出：AX writer 直接替换其已验证 owned range；键盘 writer 只替换本次 hold 已输出的尾部。固定 PID、外部输入/Secure Input/目标漂移永久 suspension、无 rollback/no resend、无光标确认或运行时权限提示以及 Fn release 零 mutation 边界保持不变（issue #27）
- 修复 build 5 的“只输出一个词”下游停滞：实机日志已证明最新一次 hold 在 13.55 秒内完成 66 个 HTTP-200 transaction，因此本地不再用原始响应字符串的相等/前缀关系决定响应身份，而是以 journal index 所有权拼接 held frontier（issue #26）
- release 现在在录音、会话排空之前同步关闭响应 ledger 与重试准入。`action=2`、在途包和晚到 partial/final 均不能创建、追加、改写或复制文本；旧的 release-time 一次性/final-only/Cmd+V/手动剪贴板回退已移除（issue #26）
- 识别可用性与输出资格分离：`autoInsert=false`、不安全文本或无 owner 时，可用 held 识别不再被误报为空结果/流式失败，同时仍保持零输出与零复制（issue #26）
- 修复 final-only 目标把所有 partial 延迟到 Fn release 的路由：初始与首 partial 重绑定的 final-only 现在会立即建立绑定 PID 的连续 owner，并在每次 mutation 前后复核 live Secure Input、捕获 token 的安全状态、原 PID 与 `CFEqual` 精确 AX 元素。Unicode 输出使用同一 `.privateState` source，先完整构造相同 UTF-16 payload/空 flags 的 key-down 与 key-up，再做最终 Secure Input 采样并相邻 `CGEventPostToPid`；任一构造失败零投递，任一投递尝试或不确定性都永久禁止完整重发、Cmd+V、其他目标或剪贴板回退。完成反馈改为中性、无 transcript 的“不确定/无可用 final”提示（issue #26）
- 修复“首次识别后持续显示流式失败”的客户端策略：已接受音频的失败会话现在在未成功完成 `action=2` 时尽力发送一次 `action=3`，然后由协调器决定是否使用新会话重试。可恢复失败在 Fn 按住期间不再发布错误状态或系统通知；松开 Fn 先关闭新重试和响应输出准入，再完成当前尝试（issue #26）
- 实机证据已将后续失败收窄到 HTTP 200 内的飞书业务码 `10024`：它先出现在一个已接受两包的会话，又出现在新会话的首包。当前飞书公开文档和官方 SDK 未定义 `10024`，因此本地将它列为可恢复是产品韧性策略，不是对限流、包频率、并发配额或未结束流的官方解释（issue #26）
- 修复真实凭据 UAT 中首个 `action=1` 已获 HTTP 200 后仍立即失败的问题：客户端不再要求 code-zero 响应回显匹配的 `stream_id` / `sequence_id`，也不再把缺少 `data` 视为畸形响应；解析现与 KaolaTerminal 已跑通实现一致，优先接受 `recognition_text`、兼容 `text`，无文本时产生空 partial。非零飞书业务码和无法解码的 JSON 仍使当前传输会话失败；协调器随后根据类型决定在同一 Fn 按键内重试或终止。请求侧 stream identity、action/sequence、首次 token 刷新、generation 安全和隐私诊断边界保持不变（issue #26）
- 根据首轮 UAT 取消过严的 Accessibility 启动门控：无法捕获或确认 AX 光标/焦点不再阻塞录音和流式识别。已捕获但不支持范围替换的目标使用绑定原 PID/精确 AX 元素的连续 owner，无 AX 目标使用同 PID owner；所有 release-time final-only/一次性/Cmd+V/剪贴板回退已移除。安全拒绝仍不输入、不复制，`autoInsert=false` 仍为零输出（issue #26）
- 修复第二轮 UAT 中终止性 provider/流式失败反复回灌同一热键错误、导致浮窗隐藏动画永远无法完成的问题：失败会先使 generation 失效并隐藏浮窗，再且仅再清理一次；相同 `HotKeyService` 错误不再重复发布。租户 token 认证失败只显示固定提示“认证失败，请检查应用凭据”，不暴露凭据、识别文本或飞书后端详情（issue #26）
- 睡眠/唤醒、手动重置、权限变化、录音/网络失败和进程清理现在先使流式 generation 与光标所有权失效，再终止入口、录音、网络任务和计时器；迟到事件不能恢复旧会话或写入新的焦点（issue #26）
- 音频入口按实际排队和待组包字节精确计数，消费后立即复用容量；停止录音会越过真实音频回调队列屏障后再决定是否保留尾包，溢出显式失败而不丢包或乱序（issue #26）

- 飞书认证和语音识别请求改为直接通过 `open.feishu.cn` 的系统 DNS/URLSession 路径发送，移除会因 CDN IP 轮换耗尽 30 秒预算的硬编码 IP 主路径；30 秒总超时统一由 `FeishuAPIService` 管理并向底层请求传播取消。
- 飞书 App ID / App Secret 不再写入 UserDefaults 设置载荷：新保存使用 macOS Keychain，旧版 `FeishuSpeechSettings` 或独立 `appId` / `appSecret` 默认值会在可安全读写 Keychain 后迁移并清理；迁移或读写失败时保留旧凭据回退（issue #18）
- 系统睡眠/唤醒后会取消陈旧转录、清理录音和 overlay 状态、重置热键状态，并刷新飞书 token / 网络错误缓存；唤醒时还会检查并重启丢失或禁用的 Event Tap（issue #19）
- Event Tap 从主线程移至专用后台线程，避免与 AVCaptureSession 争用主 RunLoop 导致热键丢失（issue #9）
- Event Tap 创建失败或辅助功能权限未授予时，自动按指数退避重试（最长间隔 30 秒），不再硬限 3 次后放弃（issue #5）
- 录音停止后重置 Fn 键状态，防止重启监控时残留的按键状态触发误录（issue #9）
- 录音过程中遇到 AVCapture 运行错误、系统中断、麦克风断开或音频转换连续失败时，会立即清理录音并显示对应错误，不再继续走停止转录路径（issue #15）
- 运行中每 2 秒无提示刷新麦克风授权状态，与辅助功能和安全输入状态保持同步（issue #15）
- 剪贴板还原不再与合成 Cmd+V 产生竞争：完整保存/还原所有粘贴板类型，通过 changeCount 轮询确认目标应用已读取后再还原；超时未确认时回退到通知（issue #13）
- 语音识别返回空结果时，不再静默无响应，而是将可观察的 `overlayMessage` 设为提示文字（issue #14）
- 录音最大时长计时器（maxDurationTimer）改用 `.common` 运行循环模式，菜单栏菜单打开时也能正常触发（issue #16）
- Overlay 隐藏动画不再与后续 show() 产生竞争：引入 generation 计数器，过期的 hide 完成回调不会关闭新弹出的 overlay（issue #17）
- 飞书 API 直连 HTTP 现在会在 `Content-Length` 或 chunked body 完整时立即完成，超时时会先解析已完整缓冲的响应；token 缓存遵守飞书 `expire` 字段并保留 300 秒安全余量；取消任务不再继续重试、轮询后续直连 IP 或进入 DNS 回退（issues #11/#12/#21）
- 热键监控恢复为 `.active` 时自动清除过期的热键失败提示但保留其他错误；`cleanup()` 复用 `stopHotKeyMonitoring()` 释放订阅，`forceState(_:)` 限定为 Debug 测试辅助方法（issues #22/#23/#24）

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

### Verification pending
- 最新 build-5 安装版 UAT 已证明一次 13.55 秒 hold 内有 66 个 HTTP-200 transaction，但可见输出在一个词后停滞；这将故障收窄到传输之后，不能证明响应内容形态或目标接受。新的 journal-index ledger、重放一次所有权、release 禁止输出与隐私安全 receipt 仍需安装版 Release owner UAT，不声明真实端到端成功。
- `CGEventPostToPid` 没有目标控件接受确认；本地 `.posted` 仅证明完整 PID-bound replacement transaction 已提交，不能证明目标完成了可见替换。当前修正仍须安装版 owner UAT，若无可见输出应报告 PARTIAL，不能通过全局 HID、重复事件、回滚或不确定后的剪贴板回退扩展行为。
- 真实飞书凭据下的后续 action、终止请求空音频编码、首次 token 刷新同序列重试、PCM/tail 兼容性和慢网行为仍需安装版 Release UAT。issue #26 的本地拼接策略已由 build 6 证据否定；issue #27 将响应按可相同、变长、缩短或修订的完整不透明 snapshot 替换，仍不推断稳定词或做文本归一化。
- TextEdit/原生控件、浏览器、Electron、终端和富文本编辑器的 Accessibility 范围、焦点干扰、Unicode 与 undo 行为仍需跨应用实机 UAT；当前不声明广泛兼容性。

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

# Documentation Index

- [Architecture](architecture.md)
- [API](api.md)
- [Streaming speech and review-first implementation/design](streaming-speech-design.md) — issue #38 默认以同一面板展示只读 streaming/sealing snapshot，action 2 与 recorder barrier 后才可编辑并显式确认；issue #39 规定未修饰 Return/数字键盘 Enter 确认、Shift+Return/Enter 换行、marked text 的 Return 交给输入法；issue #40 保留 exact AX 优先并为普通非安全 AX 严格光标缺失增加绑定原应用当前焦点的 fallback；审阅 UI 作为第三异步轴不阻塞 capture/journal 或 recognition/retry/replay；关闭设置仍使用 issue #27 兼容路由
- [Capture/recognition split and direct-connect fallback (confirmed design)](designs/capture-recognition-split-direct-connect.md) — issues #28–#31; owner-confirmed 2026-08-20; implemented; streaming transport order later superseded by D-32-01, then D-34-01 for hop/DNS
- [Conventions](conventions.md)
- [Decisions](decisions/)
  - [D-18-01: Feishu credential Keychain storage](decisions/D-18-01.md) — issue #18；#35 AppDelegate 不再 load 凭据；#36 恢复 login-keychain 读写
  - [D-25-01: Cursor-bound streaming speech contract](decisions/D-25-01.md) — 历史合同；输出冲突处由 D-27-01 取代，no-preview 结论仅在审阅模式下由 D-38-01 取代
  - [D-26-01: Journal-indexed held-response output](decisions/D-26-01.md) — 历史 issue #26 合同；拼接与禁止 Backspace 条款已被取代
  - [D-27-01: Opaque snapshot replacement with owned keyboard reconciliation](decisions/D-27-01.md) — 两种模式共享 snapshot/release-drain；固定目标连续输出是关闭审阅时的兼容合同
  - [D-28-01: Capture/recognition split and preferNoProxies fallback](decisions/D-28-01.md) — issues #28–#31；streaming 传输顺序由 D-32-01 取代
  - [D-32-01: Keep-alive primary and skip VPN/TUN](decisions/D-32-01.md) — issue #33；owner 2026-08-21 推翻 Q2-B：keep-alive 为 primary，禁止 `.other`，不绑定 `en0`；URLSession hop / fake-ip 范围由 D-34-01 取代
  - [D-34-01: Bound physical DNS and no URLSession hop](decisions/D-34-01.md) — issue #34；bound UDP/53 + `IP_BOUND_IF` TLS；factory/packet/finish 不 hop URLSession；无 IP 字面量
  - [D-38-01: Review-first live preview and explicit original-target delivery](decisions/D-38-01.md) — issue #38；默认开启、安全迁移、同一面板预览/编辑、exact-once fail-closed 原目标交付与剪贴板 `changeCount` 恢复门
  - [D-39-01: Review editor Return confirmation policy](decisions/D-39-01.md) — issue #39；仅调整审阅编辑器键盘语义，D-38（由 D-40 修订的目标权限）、剪贴板生命周期、capture/journal、recognition/retry/replay 与第三异步轴保持不变
  - [D-40-01: Review fallback bound to the original application after a non-secure AX miss](decisions/D-40-01.md) — issue #40；exact AX 优先，普通非安全严格 AX 缺失时绑定开始交互时的完整原应用并在确认时使用其当前焦点；安全输入、身份不完整或漂移仍 fail closed
- [Changelog](../CHANGELOG.md)

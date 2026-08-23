# Documentation Index

- [Architecture](architecture.md)
- [API](api.md)
- [Streaming speech and review-first implementation/design](streaming-speech-design.md) — Issue #40 v2/v3 makes every accepted interaction converge through one same-panel streaming/sealing/editablePending/editable preview; capture/recording and recognition/provider remain independent asynchronous roots; action 2 plus the recorder barrier freezes a durable draft; the preview/editor use 18pt typography in the unchanged 520×320 panel (min/max unchanged); pending UI has no visible 「重试编辑」 and only `.editable` exposes explicit Send or Return/Enter (Shift+Return/Enter inserts LF); exact AX remains preferred and an ordinary non-secure strict-AX miss uses the captured application's fixed-PID current-focus fallback; activation request is advisory but actual readiness predicates fail closed; readiness/delivery failures retain the exact draft with no copy, direct output, automatic retry, or retarget; legacy settings are decode-only. Installed UAT v3 remains failed/open.
- [Capture/recognition split and direct-connect fallback (confirmed design)](designs/capture-recognition-split-direct-connect.md) — issues #28–#31; owner-confirmed 2026-08-20; capture/recognition/transport ownership remains applicable; output-boundary notes are historical after Issue #40 v2; streaming transport order later superseded by D-32-01, then D-34-01 for hop/DNS
- [Conventions](conventions.md)
- [Decisions](decisions/)
  - [D-18-01: Feishu credential Keychain storage](decisions/D-18-01.md) — issue #18；#35 AppDelegate 不再 load 凭据；#36 恢复 login-keychain 读写
  - [D-25-01: Cursor-bound streaming speech contract](decisions/D-25-01.md) — 历史合同；输出冲突处由 D-27-01 取代，no-preview/直接输出结论再由 D-40-01 v2 的单一路线取代
  - [D-26-01: Journal-indexed held-response output](decisions/D-26-01.md) — 历史 issue #26 合同；拼接与禁止 Backspace 条款已被取代
  - [D-27-01: Opaque snapshot replacement with owned keyboard reconciliation](decisions/D-27-01.md) — 历史兼容输出合同；保留 snapshot/release-drain/安全拓扑事实，固定目标连续输出不再是可选路线
  - [D-28-01: Capture/recognition split and preferNoProxies fallback](decisions/D-28-01.md) — issues #28–#31；streaming 传输顺序由 D-32-01 取代
  - [D-32-01: Keep-alive primary and skip VPN/TUN](decisions/D-32-01.md) — issue #33；owner 2026-08-21 推翻 Q2-B：keep-alive 为 primary，禁止 `.other`，不绑定 `en0`；URLSession hop / fake-ip 范围由 D-34-01 取代
  - [D-34-01: Bound physical DNS and no URLSession hop](decisions/D-34-01.md) — issue #34；bound UDP/53 + `IP_BOUND_IF` TLS；factory/packet/finish 不 hop URLSession；无 IP 字面量
  - [D-38-01: Review-first live preview and explicit original-target delivery](decisions/D-38-01.md) — issue #38 historical base；由 D-40-01 v2 修订为唯一预览/输出路线；保留 exact AX 优先、capture/recognition 独立拓扑与剪贴板 `changeCount` 门
  - [D-39-01: Review editor Return confirmation policy](decisions/D-39-01.md) — issue #39；Return/Enter 确认、Shift+Return/Enter 换行、IME marked text 保持不变；D-40-01 v2 只补充草稿持久权威与失败保留
  - [D-40-01: One durable review preview and application-bound delivery after a non-secure AX miss](decisions/D-40-01.md) — issue #40 current authority（含 v3 UI correction）；两种 legacy setting 值均进入同一 preview；exact AX 优先，普通非安全严格 AX 缺失时绑定开始交互时的完整原应用并在确认时使用固定 PID 当前焦点；advisory activation 不放宽实际 readiness predicates；readiness/delivery 失败保留原草稿且 fail closed；installed UAT v3 仍 failed/open
- [Changelog](../CHANGELOG.md)

# Documentation Index

- [Architecture](architecture.md)
- [API](api.md)
- [Cursor-bound streaming speech implementation and design](streaming-speech-design.md) — issue #27 以完整不透明 snapshot 替换取代 issue #26 拼接策略；Fn-up 关闭采集后继续 bounded drain、replay recovery 与 action-2 terminal reconciliation；安装版真实凭据 Release owner UAT 仍待继续
- [Capture/recognition split and direct-connect fallback (confirmed design)](designs/capture-recognition-split-direct-connect.md) — issues #28–#31; owner-confirmed 2026-08-20; implemented; streaming transport order later superseded by D-32-01, then D-34-01 for hop/DNS
- [Conventions](conventions.md)
- [Decisions](decisions/)
  - [D-18-01: Feishu credential Keychain storage](decisions/D-18-01.md) — issue #18；#35 AppDelegate 不再 load 凭据；#36 恢复 login-keychain 读写
  - [D-25-01: Cursor-bound streaming speech contract](decisions/D-25-01.md) — 历史合同；冲突处由 D-27-01 取代
  - [D-26-01: Journal-indexed held-response output](decisions/D-26-01.md) — 历史 issue #26 合同；拼接与禁止 Backspace 条款已被取代
  - [D-27-01: Opaque snapshot replacement with owned keyboard reconciliation](decisions/D-27-01.md) — 当前 issue #27 snapshot、release-drain 与固定目标输出合同
  - [D-28-01: Capture/recognition split and preferNoProxies fallback](decisions/D-28-01.md) — issues #28–#31；streaming 传输顺序由 D-32-01 取代
  - [D-32-01: Keep-alive primary and skip VPN/TUN](decisions/D-32-01.md) — issue #33；owner 2026-08-21 推翻 Q2-B：keep-alive 为 primary，禁止 `.other`，不绑定 `en0`；URLSession hop / fake-ip 范围由 D-34-01 取代
  - [D-34-01: Bound physical DNS and no URLSession hop](decisions/D-34-01.md) — issue #34；bound UDP/53 + `IP_BOUND_IF` TLS；factory/packet/finish 不 hop URLSession；无 IP 字面量
- [Changelog](../CHANGELOG.md)

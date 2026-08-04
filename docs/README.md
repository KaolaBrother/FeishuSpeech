# Documentation Index

- [Architecture](architecture.md)
- [API](api.md)
- [Cursor-bound streaming speech implementation and design](streaming-speech-design.md) — issue #27 以完整不透明 snapshot 替换取代 issue #26 拼接策略；Fn-up 关闭采集后继续 bounded drain、replay recovery 与 action-2 terminal reconciliation；安装版真实凭据 Release owner UAT 仍待继续
- [Conventions](conventions.md)
- [Decisions](decisions/)
  - [D-25-01: Cursor-bound streaming speech contract](decisions/D-25-01.md) — 历史合同；冲突处由 D-27-01 取代
  - [D-26-01: Journal-indexed held-response output](decisions/D-26-01.md) — 历史 issue #26 合同；拼接与禁止 Backspace 条款已被取代
  - [D-27-01: Opaque snapshot replacement with owned keyboard reconciliation](decisions/D-27-01.md) — 当前 issue #27 snapshot、release-drain 与固定目标输出合同
- [Changelog](../CHANGELOG.md)

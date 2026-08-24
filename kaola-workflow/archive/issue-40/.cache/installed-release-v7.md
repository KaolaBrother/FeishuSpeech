# Issue #40 v7 installed Release receipt

timestamp: 2026-08-24T19:39:07+08:00
uat_status: pending_owner
issue_state: open
github_evidence_comment: https://github.com/KaolaBrother/FeishuSpeech/issues/40#issuecomment-5394674002

## Source and artifact

- production commit: `614fb38329547fcd07af4609040f179a6f2a9792`
- documentation head: `4126740d71b2a8df7e42c80196160d69b0719a6b`
- installed path: `/Applications/FeishuSpeech.app`
- bundle ID: `Siji.FeishuSpeech`
- executable SHA-256: `656e08864e28885e5de58433b04005628e59a66b8e7c1f0b3efcf6a69774763b`
- CDHash: `add6c5a34b4f0f02a20558749ec37ccf2c977e4e`
- signature: `Apple Development: Yanlei Chen (C2D65N458L)`
- TeamIdentifier: `D5KY7PZC5N`
- `codesign --verify --deep --strict`: pass
- built-versus-installed `diff -qr`: pass before temporary build removal

## Runtime and sole-copy audit

- running PID: `98547`
- executable path: `/Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech`
- Accessibility and microphone both logged true
- `/Applications` and `~/Applications`: one copy, `/Applications/FeishuSpeech.app`
- project DerivedData and workspace: zero additional app bundles
- all v7 test/build DerivedData roots under `/private/tmp` removed after installation
- Spotlight bundle-ID audit: only `/Applications/FeishuSpeech.app`

Owner UAT remains required before Issue #40 can close.

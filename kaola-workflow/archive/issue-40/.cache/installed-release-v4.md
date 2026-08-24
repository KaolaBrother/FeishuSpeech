# Issue #40 v4 installed Release receipt

- Date: 2026-08-24 (Asia/Shanghai)
- Commit: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305`
- Remote branch proof: `origin/workflow/issue-40` resolved to the same full SHA before build.
- Install path: `/Applications/FeishuSpeech.app`
- Bundle identifier: `Siji.FeishuSpeech`
- Bundle version: `1.0`
- Executable SHA-256: `4a5bc6b1d76d3b56c52e133db8e6b26b9f9a9ac3c8d15ccf898c92a231618fdb`
- Relative-path content-manifest SHA-256: `84fcd7885430e17e0c3e4c2b82d0e2dbe4a2caa32974d0369048d2adfc1ad5a3`
- Codesign verification: valid on disk; satisfies its Designated Requirement.
- Sole-copy audit: Spotlight returned only `/Applications/FeishuSpeech.app`; the prior `/Applications` candidate, Debug DerivedData copy, Release DerivedData copy, and temporary build copy were removed after exact bundle validation.
- Runtime proof: exactly one `FeishuSpeech` process launched; PID `69481`; executable resolved to `/Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech`.

## Bound automated evidence

- R4 selectors: 3/3 passed.
- Streaming coordinator: 105/105 passed, zero skipped.
- Focused v4 matrix: 265/265 passed, zero skipped.
- Full macOS target: 483 passed, zero failed, one unrelated live-TCP environment skip.
- Debug and Release builds, strict SwiftLint, diff, Markdown links, protected async topology, and forbidden pasteboard/Cmd+V/output scans passed.
- Correctness: `.cache/code-review-v4-r4-final.md` PASS, zero blocker/high/medium.
- Security: `.cache/security-review-v4-r4-final.md` PASS, zero blocker/high.
- Final validation: `.cache/validation-v4-r4-final.md` PASS.

## Owner acceptance state

`owner_uat: failed_v4_send_deadlock`

Owner UAT failed on 2026-08-24: clicking Send changed the preview to “正在发送…” and the application stopped responding; Return was not reliably received because the editor was not guaranteed to be the key first responder. A live sample of PID `99976` proved a same-thread non-recursive epoch-lock deadlock before `postPair()` and before any Unicode down/up event. The app was stopped after evidence capture; no FeishuSpeech process remains and combined-session modifier flags were `0`.

Runtime evidence: `.cache/runtime-diagnosis-v5.md`; sample `/tmp/FeishuSpeech_2026-08-24_084734_25BZ.sample.txt`, SHA-256 `d2e8399687c8001ba1e3bc92b7df8ca81e4f3b2390421fcb40319735b9ebd6a0`.

This installed commit is rejected. No target-consumption, GUI acceptance, issue closure, merge, or release success claim is valid.

# Issue #40 v7 diagnosis: authorized capture still reported `无法确认输入位置`

Date: 2026-08-24 (Asia/Shanghai)

## Runtime evidence

- macOS wrote the current Apple Development designated requirement into Accessibility TCC at
  19:27:46. The application then logged `Accessibility trusted: true` and continuously refreshed
  Accessibility as true.
- The installed v6 process nevertheless reported four target-capture failures at 19:27:55,
  19:28:18, 19:28:20, and 19:28:22. Every failure was typed `securityRejected` and mapped to
  `无法确认输入位置`.
- These failures occurred after transition to streaming and recorder startup. The log therefore rules
  out missing Accessibility authorization, lifecycle-observer installation, hot-key monitoring,
  microphone permission, and recorder startup as the cause.
- A privacy-safe read-only probe against the current Codex target ran five times. Each system-wide
  focused-element read returned AX error `-25204` (`kAXErrorCannotComplete`). Each read from the already
  captured original application AX root succeeded and returned the same PID with role `AXTextArea`.
  No text value, selection text, or clipboard content was read.

## Design flaw

Initial capture froze a complete original application identity but then asked
`AXUIElementCreateSystemWide()` for an ambient focused element. That second authority can fail
independently or expose an element outside the fixed target. It was inconsistent with the accepted
fixed-original-application contract and with the existing confirmation validation, which already reads
current focus from `target.applicationElement`.

## Inline v7 repair

Production commit: `614fb38329547fcd07af4609040f179a6f2a9792`

- Initial focused-element capture now reads `kAXFocusedUIElementAttribute` from the frozen original
  application's AX root.
- It no longer constructs or consults a system-wide focus root during capture.
- Role/subrole classification, Secure Input, live Accessibility trust, PID, complete process identity,
  exact-selection preference, application-bound fallback, cancellation, deadline, and confirmation-time
  security gates remain unchanged.
- Production now logs every AX step and result as public enum identifiers only. It never logs target text,
  transcript, selection, application content, or clipboard data.
- No output capability is created before explicit Send or qualified Return. The recording and recognition
  roots remain independently asynchronous.

## Validation and installed boundary

- Focused matrix: 324 executed, 0 failed, 0 skipped.
- Full serialized target: 537 executed, 0 failed, 1 expected Issue #34 live-TCP skip.
- Debug and Apple Development-signed Release builds: pass.
- SwiftLint strict: 0 violations in 36 files.
- Signed v7 is installed as the sole application copy and running from `/Applications/FeishuSpeech.app`.
- Owner UAT is pending. The live log stream did not receive a new Fn event before this receipt was written.

## v6 authorized UAT log diagnosis and v7 original-app focus repair

The new log disproved the earlier remaining-permission hypothesis:

- Accessibility TCC updated for the Apple Development requirement at **19:27:46**.
- The app logged `Accessibility trusted: true`.
- Four later Fn target captures still failed as typed `securityRejected` and showed
  `无法确认输入位置`.

A privacy-safe five-run probe against the live Codex target then isolated the authority flaw:

| AX root | Result in 5/5 runs |
|---|---|
| ambient system-wide focus | `kAXErrorCannotComplete` (`-25204`) |
| frozen original application | success, same PID, `AXTextArea` |

No target text, selection text, or clipboard content was read.

Production commit: [`614fb38`](https://github.com/KaolaBrother/FeishuSpeech/commit/614fb38329547fcd07af4609040f179a6f2a9792)

- Initial focus capture now reads only from the complete original-application AX root already frozen at
  Fn acceptance.
- Ambient `AXUIElementCreateSystemWide()` focus is no longer a capture authority.
- Secure Input, live trust, role/subrole, PID, full process identity, exact selection, fixed-app fallback,
  deadline/cancellation, final security sandwich, and exact-once confirmation gates are unchanged.
- Privacy-safe production diagnostics now log only AX step/result enum identifiers.
- Recording and recognition remain independent async roots; no pre-confirm output path was added.

Validation is green: **324/324 focused**, **537 full with one expected Issue #34 skip**, Debug and signed
Release builds, strict SwiftLint, and diff check. The signed v7 Release is installed as the sole app copy:

- SHA-256 `656e08864e28885e5de58433b04005628e59a66b8e7c1f0b3efcf6a69774763b`
- CDHash `add6c5a34b4f0f02a20558749ec37ccf2c977e4e`
- TeamIdentifier `D5KY7PZC5N`

Issue #40 remains OPEN pending owner UAT of streaming preview, durable editable freeze, zero editing side
effects, and exactly one original-target attempt after preview-local Send or qualified Return.

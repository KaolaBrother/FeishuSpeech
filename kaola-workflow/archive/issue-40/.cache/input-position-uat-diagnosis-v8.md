# Issue #40 v8 installed capture diagnosis

Date: 2026-08-24

## Installed v7 evidence

- PID `98547` was the sole `/Applications/FeishuSpeech.app` process.
- Accessibility and microphone permission heartbeats were both `true`.
- Fresh owner attempts at `19:38:16.945` and `19:38:23.566` failed as
  `Review target capture failed: securityRejected`, followed by `无法确认输入位置`.
- The failure occurs before audio/provider startup and before any output path.
- V7 emitted AX step/result diagnostics at debug level; those values were not
  retained by the Release unified log, so `securityRejected` still represented
  several fail-closed branches.

## v8 diagnostic repair

- Commit: `f9ed961` (`fix: persist review target capture diagnostics`).
- Production capture behavior is unchanged.
- Original-application identity, frontmost PID, Secure Input, Accessibility
  trust, and subsequent AX operations now all use the existing value-only
  observer categories.
- The production observer logs only enum step/result names at info level. It
  receives no AX object, transcript, target text, selection value, or draft.
- Two new tests prove Secure Input and lost Accessibility trust are identified
  before any AX message.

## Validation and install

- Focused security/application-fallback suites: pass.
- Full serialized macOS target: 538 passed, 0 failed, 1 expected live-TCP skip.
- SwiftLint strict: 0 violations in 36 files.
- Release build: pass.
- Installed signature: `Apple Development: Yanlei Chen (C2D65N458L)`.
- Team: `D5KY7PZC5N`.
- CDHash: `915738a4a0305504721b518b685eac1c8c4bc933`.
- Executable SHA-256: `0830d5c5301137a92fa2d11b0f6a4af80e599f661eb2a1989c9927520f71e7d4`.
- Installed PID: `56051`.
- Built-versus-installed app diff: identical.
- Sole-copy audit: `/Applications/FeishuSpeech.app` only (the repeated audit
  line came from independent filesystem and Spotlight checks).
- Temporary v7 replacement backup and all v8 build app copies were deleted
  after successful verification; those deleted temporary copies are not
  recoverable, while the source commit and installed v8 application remain.

## Remaining gate

One fresh owner Fn attempt is required. The next log will identify the exact
step/result branch while preserving zero output before explicit confirmation.

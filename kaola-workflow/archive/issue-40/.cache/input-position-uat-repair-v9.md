# Issue #40 v9 input-position repair

Date: 2026-08-24

GitHub evidence: https://github.com/KaolaBrother/FeishuSpeech/issues/40#issuecomment-5395110907

## Evidence and root cause

- The installed v7 attempts at `19:38:16.945` and `19:38:23.566` failed before
  preview startup as `securityRejected`, followed by `无法确认输入位置`.
- V8 persisted value-only capture diagnostics without recording an AX object,
  transcript, target text, draft, selection, or clipboard value.
- The current privacy-safe foreground probe reproduced the relevant target
  shape in Safari: PID `1617`, bundle `com.apple.Safari`, Secure Input `false`,
  Accessibility trust `true`, focused-element read success, role `AXWebArea`,
  subrole `kAXErrorNoValue`, and selected-range settable `false`.
- The raw v7/v8 role policy mapped every successfully read role outside
  `AXTextField` / `AXTextArea` to `.unverifiable`. That collapsed an ordinary
  browser/Electron AX capability miss into `securityRejected`, so the existing
  frozen-application fallback never received the target.

## v9 repair and preserved boundaries

- Commit: `584e09d` (`fix: admit non-native AX roles to review preview`).
- `ReviewAXEditableRolePolicy` classifies native text roles separately and maps
  non-native roles such as `AXWebArea` to `.ordinaryCapabilityMiss`.
- Capture and confirmation therefore reuse the existing application-bound
  current-focus path for the exact frozen application identity.
- Secure Input, Accessibility trust, running identity, frontmost PID,
  cancellation, deadline, modifier/interference, and lifecycle lease checks
  remain fail closed.
- Recording/capture and recognition/provider remain independent asynchronous
  roots. Fn release only seals capture. No output, clipboard access, Cmd+V,
  activation, or retarget occurs before panel-local Send or qualified Return.
  A confirmed draft still authorizes at most one Unicode down plus mandatory up
  attempt and never retries after the boundary.

## TDD and validation

- RED: the new focused test failed to compile because the role policy did not
  exist.
- GREEN: `test_v9NonNativeFocusedRolesUseOrdinaryApplicationFallback` passes for
  `AXWebArea`, `AXButton`, `AXTextField`, and `AXTextArea` classifications.
- Focused security/delivery suites: 100 passed, 0 failed, 0 skipped.
- Full serialized macOS target: 539 passed, 0 failed, 1 expected live-TCP skip.
- SwiftLint strict: 0 violations in 36 files.
- Release build and strict/deep code-sign verification: pass.

## Installed Release

- Path: `/Applications/FeishuSpeech.app`.
- PID: `21271`.
- Signature: `Apple Development: Yanlei Chen (C2D65N458L)`.
- Team: `D5KY7PZC5N`.
- CDHash: `5bbecdf0c1f33a1cb2e477021c98a75ee32392bd`.
- Executable SHA-256:
  `c2e9f2797c86789e69394e68dbd8c308767f5bd5cbb971d839e2213cd681d0ea`.
- Built-versus-installed app diff: identical.
- Startup: Accessibility `true`, microphone `true`, hot-key monitoring active.

## Remaining gate

Owner UAT must still prove Fn hold -> streaming preview -> Fn release -> durable
editable draft -> panel-local Send/Return. Issue #40 remains open until that
installed path succeeds; no target-consumption or broad compatibility claim is
made before then.

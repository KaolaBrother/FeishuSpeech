# Finalization — Summary: issue-27

## Delivered

- Feishu streaming responses are treated as complete opaque snapshots rather than concatenated packet text.
- Packet replay ownership is independent from snapshot equality and content admission; historical packets cannot mutate output after retry.
- Duplicate snapshots are no-ops, while changed snapshots replace the provisional output owned by the active Fn hold.
- Verified AX targets replace one owned range directly, including multiline data.
- Generic current-focus targets reconcile snapshots with grapheme-counted Backspaces plus the replacement suffix, bound to one PID.
- The existing HID event tap provides synchronous physical-input interference authority through a shared atomic epoch gate held across each complete synthetic key pair.
- Generic keyboard output rejects LF and other action-capable controls; Fn release seals admission and late/final callbacks never mutate text.
- Repository-default Release metadata is 1.0 build 7.

## Files Changed

- Production: `MainViewModel.swift`, `CurrentFocusAppendSession.swift`, `TextInputSimulator.swift`, `HotKeyService.swift`.
- Tests: `CurrentFocusAppendSessionTests.swift`, `FinalTextOutputSecurityTests.swift`, `StreamingMainViewModelTests.swift`.
- Configuration: `FeishuSpeech.xcodeproj/project.pbxproj`.
- Documentation: README, changelog, documentation index, architecture, API, streaming design, D-25-01, D-26-01, and new D-27-01.

## Test Coverage

- Regression-first tests prove build-6 repetition, duplicate snapshots, changed complete snapshots, retry replay, and release sealing.
- Replacement tests cover extension, shorter, divergent, full replacement, emoji ZWJ sequences, combining marks, flags, CJK, RTL, and newlines by supported route.
- Security tests cover event construction before posting, exact Backspace counts, fixed PID, secure input, same-app and external interference, monitor-arm failure, tap-disable loss of observability, atomic arm baseline, check-to-post ordering, and guarded insertion.
- Production-boundary tests directly exercise `SystemFinalTextCurrentFocusEventPoster` with the real shared interference gate.
- Final lifecycle-free XCTest result: 300/300 passed; focused results: 35/35 CurrentFocus, 19/19 output security, 77/77 streaming coordinator.

## Validation

- Consumer validation receipt: PASS, bound to the issue-27 worktree candidate hash `e536b41d6ebc105595460072c577d6d8bff78a46036c683db79eaebce6934539`.
- Strict SwiftLint: 27 files, 0 violations.
- Build-for-testing: succeeded.
- Debug build: succeeded.
- Release build: succeeded.
- Built metadata: `CFBundleShortVersionString=1.0`, `CFBundleVersion=7`.
- Strict deep code-sign verification: valid ad-hoc local signature; no Developer ID/notarization claim.
- Documentation-only commit `c207334` landed after the independent code/test/build gate; no production, test, or configuration bytes changed after that gate.

## Changed Paths

- `CHANGELOG.md`
- `FeishuSpeech.xcodeproj/project.pbxproj`
- `FeishuSpeech/Services/CurrentFocusAppendSession.swift`
- `FeishuSpeech/Services/HotKeyService.swift`
- `FeishuSpeech/Services/TextInputSimulator.swift`
- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`
- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`
- `README.md`
- `docs/README.md`
- `docs/api.md`
- `docs/architecture.md`
- `docs/decisions/D-25-01.md`
- `docs/decisions/D-26-01.md`
- `docs/decisions/D-27-01.md`
- `docs/streaming-speech-design.md`

## Documentation Docking

- `verdict: DOCKED` in `.cache/doc-docking.md`.
- Final documentation audit `verdict: PASS` in `.cache/doc-updater.md`.
- Current decisions and user-facing docs describe snapshot replacement, atomic HID interference authority, AX-only multiline data, generic keyboard action-control rejection, build 7, and the automated validation boundary.

## Release Installation

- Installed `/Applications/FeishuSpeech.app` as Release 1.0 build 7.
- Strict deep code-sign verification passed on the installed bundle.
- `/Applications` contains exactly one matching `FeishuSpeech.app` bundle.
- The prior build-6 bundle was moved recoverably to `/Users/ylpromax5/.Trash/FeishuSpeech-build6-pre-issue27-20260804T141751.app`.
- The isolated Release build directory was moved recoverably to `/Users/ylpromax5/.Trash/feishuspeech-issue27-release-build-20260804T141751`.
- FeishuSpeech was not launched after installation; no matching process was running at verification.

## Post-Finalize Reconciliation

- The keep-open finalize transaction reported the issue-27 roadmap source missing.
- Restored `kaola-workflow/.roadmap/issue-27.md` with owner Release-UAT as the next step, regenerated `ROADMAP.md`, and passed roadmap validation before the sink.

## Run gaps

None swept. Every correctness/security finding R1-R9 was reproduced, fixed, independently re-reviewed, and closed in this run.

## Follow-Up Items

- Owner credential-bearing Release UAT remains pending for visible output in real target applications, reconnect/replay, physical caret interference, and Fn-release races.
- GitHub issue #27 remains open in `comment_keep_open` mode until the owner records that UAT result.
- Notarization and Developer ID distribution signing were not part of this local Release.

## Status: ARCHIVED AFTER FINAL GIT GATE

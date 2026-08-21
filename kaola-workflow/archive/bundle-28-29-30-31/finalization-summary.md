# Finalization — Summary: bundle-28-29-30-31

## Delivered

- Capture line journals PCM into `HoldPacketJournal` without waiting on Feishu factory; recognition is one send loop from index 0 (issue #28).
- In-attempt transport cancel is recoverable timeout while retry is open; generation cancel stays terminal (issue #29).
- Per-attempt `URLSession` with transport-owned slice timers; streaming drops the `NWPathMonitor` hard gate (issue #30).
- No-HTTP URLSession miss hops once to keep-alive `preferNoProxies` / SNI `open.feishu.cn`; leftover is the raw framed message end (issue #31).
- Menu extra is icon-only so it is not lost in the MacBook notch.
- Release builds disable coverage instrumentation.

## Files Changed

See Changed Paths. Local follow-up on PR #32: remainder parser, remainder tests, overflow wait, retry source contract, URLProtocol finish API, icon-only extra, Release `ENABLE_CODE_COVERAGE=NO`, docs docking.

## Test Coverage

- Full `xctest` bundle: 345 tests, 0 failures (remainder + overflow + retry + URLProtocol tree).
- `swiftlint --strict`: 0 violations on `ce8e3d2`.
- `xcodebuild -configuration Release ENABLE_CODE_COVERAGE=NO build`: succeeded; installed binary has no `__llvm_prf` / `__LLVM_COV` sections.

## Validation

- Consumer receipt: `verdict: pass` in `kaola-workflow/bundle-28-29-30-31/.cache/final-validation.md`.
- Bound hash: `97779ab271d17f4365bd361b2f6ff029646138fbbca1c366b494ce79671f4194`.
- Command recorded on the live tree: swiftlint 0; xctest 345/0 on the behavioral follow-up tree; uninstrumented Release build then unique install.
- Reuse boundary: xctest 345/0 was taken before the docs-only and coverage-flag commit bytes were combined at `ce8e3d2`; Release rebuild after icon-only + coverage-off confirmed no coverage sections.

## Changed Paths

- `.cursor/environment.json`
- `.cursor/install.sh`
- `.cursor/start.sh`
- `CHANGELOG.md`
- `FeishuSpeech.xcodeproj/project.pbxproj`
- `FeishuSpeech/App/FeishuSpeechApp.swift`
- `FeishuSpeech/Models/StreamingSpeechModels.swift`
- `FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift`
- `FeishuSpeech/Services/FeishuAPIService.swift`
- `FeishuSpeech/Services/FeishuStreamingSession.swift`
- `FeishuSpeech/Services/HoldPacketJournal.swift`
- `FeishuSpeech/Services/TransportAttemptContext.swift`
- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift`
- `FeishuSpeechTests/FeishuAPIServiceTests.swift`
- `FeishuSpeechTests/FeishuStreamingSessionTests.swift`
- `FeishuSpeechTests/HoldPacketJournalTests.swift`
- `FeishuSpeechTests/StreamingDrainPolicyTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`
- `FeishuSpeechTests/TransportAttemptContextTests.swift`
- `README.md`
- `docs/README.md`
- `docs/api.md`
- `docs/architecture.md`
- `docs/decisions/D-28-01.md`

## Mission List

All five items in `mission-list.md` are `done`: capture journal, cancel mapping, per-attempt URLSession, preferNoProxies remainder, local suite + unique Release install.

## Documentation Docking

- `verdict: DOCKED` in `.cache/doc-docking.md`.
- `verdict: PASS` in `.cache/doc-updater.md`.

## Run gaps

## Follow-Up Items

None. GitHub PR #32 is the existing review request; this finalize sinks by merge and closes #28–#31.

## Status: ARCHIVED AFTER FINAL GIT GATE

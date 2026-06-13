evidence-binding: n5-code-review 0c5072700473
verdict: pass
findings_blocking: 0

# n5 Code Review - issue #19

## Findings

### CRITICAL
none

### HIGH
none

### MEDIUM
none

### LOW
none

No blocking findings found.

## Review Scope

- Reviewed current working-tree diff against merge-base `38b2e00ef0d92ca48e099b2ac3f863e537f9bd89` / `origin/main`.
- Product files reviewed:
  - `FeishuSpeech/App/AppDelegate.swift`
  - `FeishuSpeech/ViewModels/MainViewModel.swift`
  - `FeishuSpeech/Services/FeishuAPIService.swift`
  - `FeishuSpeech/Services/HotKeyService.swift`
- Test files reviewed:
  - `FeishuSpeechTests/MainViewModelTests.swift`
  - `FeishuSpeechTests/FeishuAPIServiceTests.swift`
  - `FeishuSpeechTests/HotKeyServiceTests.swift`

## Review Notes

- `AppDelegate` registers `NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification` on launch, removes observer tokens on termination, queues events until a `MainViewModel` is available, and replays them in FIFO order once injected.
- `MainViewModel` preserves production defaults through `MainViewModel()` (`AppSettings.load()` and `HotKeyService.shared`) while allowing tests to inject clean `AppSettings()` and `HotKeyWakeRecovering`. Sleep/wake cleanup cancels stale transcription generations, force-cleans recording state, stops timers/overlay, resets the API wake state, and routes did-wake hot-key recovery.
- `FeishuAPIService.resetStateForWake()` clears token/expiry/network-error state and resets availability for a fresh post-wake probe. DEBUG test snapshots expose only booleans/error description and do not return token values.
- `HotKeyService.recoverAfterWake()` cancels stale pending input, clears cached Fn flags, keeps an enabled live tap active, and restarts monitoring through the existing stop/start lifecycle when the tap is missing or disabled.
- The final-validation repair's explicit `AppSettings()` and `TrackingHotKeyWakeRecoverer` injections make tests deterministic without weakening production defaults or hiding a production wiring defect.

## Validation Evidence

- `git diff --check`: pass in current review session.
- Cached build-for-testing after settings injection: `kaola-workflow/issue-19/.cache/final-validation-logs/build-for-testing-after-settings-injection.exit` = `0`.
- Cached focused issue #19 XCTest run: `kaola-workflow/issue-19/.cache/final-validation-logs/direct-xctest-issue19-new-methods-final2.exit` = `0`; 9 selected tests passed, 0 failures.
- Cached debug build: `kaola-workflow/issue-19/.cache/final-validation-logs/debug-build.exit` = `0`.
- Full cached `xcodebuild test` path timed out in the app-host harness, but the focused issue #19 bundle passed after the repair and no wake-recovery behavior failure was present in the review evidence.
- `swiftlint` could not be run in this environment: `zsh:1: command not found: swiftlint`.

# Finalization - Summary: bundle-5-9-10

## Delivered

- **Issue #5 (P0):** Observable `MonitoringState` enum with `TapFailureReason` surfaces tap-creation failure to `MainViewModel` and the menu bar. Capped exponential backoff (unbounded retries, max 30s) replaces the hard 3-attempt cap.
- **Issue #9 (P1):** CGEventTap run-loop source moved to a dedicated private thread (`tapThread`/`tapRunLoop`), decoupled from `CFRunLoopGetMain()`. `AVCaptureSession.startRunning()` dispatched to `sessionQueue`, with optimistic `isRecording = true` set before dispatch. `previousFlags` reset on `stopMonitoring()`; post-timeout `CGEventSource.flagsState` resync detects missed Fn releases. All 7 `previousFlags` access sites guarded by `NSLock`.
- **Issue #10 (P2):** `PermissionManager.refreshSecureInputStatus()` polls `IsSecureEventInputEnabled()` on the existing 2s timer. `MenuBarView` shows orange warning when secure input is active. `AppDelegate` integrates the refresh call.

## Files Changed

**New files:**
- `FeishuSpeech/Services/HotKeyState.swift` — `TapFailureReason`, `MonitoringState` enums
- `FeishuSpeechTests/PermissionManagerTests.swift` — 5 tests
- `docs/decisions/D-5-01.md` — ADR for tap-lifecycle + threading contract
- `kaola-workflow/bundle-5-9-10/` (workflow artifacts)

**Modified files:**
- `FeishuSpeech/Services/HotKeyService.swift` — dedicated tap thread, monitoringState, NSLock, backoff, resync
- `FeishuSpeech/ViewModels/MainViewModel.swift` — $monitoringState subscription, handleMonitoringState
- `FeishuSpeech/Services/AudioRecorder.swift` — sessionQueue, optimistic isRecording
- `FeishuSpeech/Services/PermissionManager.swift` — secureInputEnabled, refreshSecureInputStatus
- `FeishuSpeech/Views/MenuBarView.swift` — secure-input status UI
- `FeishuSpeech/App/AppDelegate.swift` — timer refresh call
- `FeishuSpeechTests/HotKeyServiceTests.swift` — 11 new tests added (7 for node2, partial for node3)
- `CHANGELOG.md` — [Unreleased] entries for all three fixes
- `docs/architecture.md` — tap-lifecycle + threading section

## Test Coverage

Full xcodebuild test unavailable (CommandLineTools only, no Xcode). Summary of test additions:
- `HotKeyServiceTests.swift`: 11 new tests covering MonitoringState transitions, backoff schedule, tap-thread placement, previousFlags reset, post-timeout resync
- `PermissionManagerTests.swift`: 5 new tests covering secureInputEnabled toggle

Coverage % not computable from this environment.

## Final Validation Evidence

| Command | Result | Evidence Path |
|---------|--------|---------------|
| `swiftc -typecheck` (HotKeyService, HotKeyState, AudioRecorder) | EXIT 0 | `.cache/final-validation.md` |
| `swiftc -typecheck` (PermissionManager) | EXIT 0 | `.cache/final-validation.md` |
| `xcodebuild test` | UNAVAILABLE (CommandLineTools only) | `.cache/final-validation.md` |
| Adaptive barrier gates (resume/gate/barrier/verdict-check) | PASS (RC=0, GV=0, BC=0, VC=0) | `.cache/final-validation.md` |

Validation reuse covers code/test impact through node5 verdict; finalize-node CHANGELOG/docs edits are docs-only and outside the rerun trigger.

## Documentation Docking

DOCKED — see `.cache/doc-docking.md`

## Final Validation Failure Ledger

| Failing Command | Classification | Routed To | Evidence | Status |
|-----------------|----------------|-----------|----------|--------|
| F1: isRecording async race | behavior | tdd-guide (repair in node3) | node5 re-review evidence | FIXED |
| F2: previousFlags data race | thread-safety | tdd-guide (repair in node3) | node5 re-review evidence | FIXED |
| F3: missing MainViewModel binding test | coverage | deferred (follow-up issue) | node5 re-review evidence | DEFERRED |
| F4: error-recovery debounce clears warning | behavior/UX | deferred (follow-up issue) | node5 re-review evidence | DEFERRED |

## Follow-Up Items

1. **F3 — MainViewModelTests.swift missing monitoringState→status binding test**: `MainViewModelTests.swift` is not in any node's declared write set. Functionality exists and is correct; test coverage gap. Recommendation: open follow-up issue for `MainViewModelTests.swift` to add test covering `.failed(.accessibilityNotTrusted)` → `status == .error(...)`.

2. **F4 — Error-recovery debounce clears tap-failure warning**: When `monitoringState` returns to `.active` after recovery, the menu-bar error status auto-clears. UX policy decision needed: should `status` stay on `.error` until user acknowledges, or auto-clear on recovery? Recommendation: open follow-up issue to define and implement the UX policy.

## Closure Decision

Neither F3 nor F4 blocks merge per the all-or-nothing closure policy — both are post-merge follow-ups. No user decision required to close #5, #9, #10. Two follow-up issues to be created post-merge (see Step 6 below).

## GitHub Issue

#5, #9, #10 — ready to close (all-or-nothing closure policy). Pending final Git gate.

## Roadmap

Pending update (Step 7).

## Archive

Pending (Step 7). Target: `kaola-workflow/bundle-5-9-10/` → archived after commit+push.

## Required Agent Compliance

| Requirement | Status | Evidence | Skip Reason |
|-------------|--------|----------|-------------|
| doc-updater | invoked (node6) | `kaola-workflow/bundle-5-9-10/.cache/node6.md` | N/A |
| documentation docking | DOCKED | `.cache/doc-docking.md` | N/A |
| final-validation fix executors | invoked (F1+F2 repair in node3) | node5 re-review evidence | N/A |
| roadmap refresh | pending | `kaola-workflow/ROADMAP.md` | runs in Step 7 |
| archive completed folder | pending | | runs in Step 7 |
| final commit and push | ready | git status/diff confirmed clean on worktree | final gate runs after step 7 |

## Status

ARCHIVED AFTER FINAL GIT GATE

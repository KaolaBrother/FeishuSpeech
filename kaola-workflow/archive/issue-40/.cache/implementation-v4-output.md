# Issue #40 v4 OUTPUT/SECURITY implementation evidence

Date: 2026-08-23
Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
Assigned lane: OUTPUT/SECURITY production implementation

## Scope and result

Implemented the review output/security lane in the assigned production files:

- `FeishuSpeech/Services/TextInputSimulator.swift`
  - Removed review pasteboard snapshot/read/write/restore/change-count scheduling and Cmd+V output.
  - Added a review-only, modifier-free Unicode keyDown/keyUp transaction carrying the exact full UTF-16 draft, including LF, with the 16,384-unit cap.
  - Added source/tag/phase/flags/payload/target-PID/own-source-PID/same-source readback before the first post; missing readback capability fails closed.
  - Added explicit not-started versus submission-boundary-crossed results, deterministic construction/cancellation/fault hooks, mandatory key-up after key-down, and submitted-unverified outcomes.
  - Added the synchronous pair-gate needed by the delivery critical section.
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift`
  - Routed exact and application-bound review delivery through the prepared Unicode pair.
  - Added pre-activation physical-input and activation monitoring, post-activation modifier stabilization, activation-then-input critical-section ordering, final live validation, and postflight epoch/modifier checks.
  - Removed the post-output cancellation override; post-boundary uncertainty is never retried.
  - Renamed the successful review delivery result to `submittedUnverified` rather than `inserted`; legacy output results are mapped conservatively at the review boundary and never reported as consumed.
- `FeishuSpeech/Services/CurrentFocusAppendSession.swift`
  - R5 self-event exemption now requires both the fixed tag and `eventSourceUnixProcessID == getpid()` in the event-tap and AppKit paths; tap-disabled events still advance first and unconditionally.
  - Added the activation/input monitor capability needed for fail-closed review epoch arming.
- `FeishuSpeech/Models/CursorTextModels.swift`
  - Added `FinalTextInsertionResult.submittedUnverified` for the local non-consumption claim.

`HotKeyService.swift` already routed every tap event through `CurrentFocusInputInterferenceEpoch.observePreDispatch`; no additional production edit was required there.

## Verification tier

`tests-green` was not achieved because the focused test command stops while compiling unrelated, still-migrating test files. `build-green` was achieved for the complete Debug production target; no production compiler errors remain in this lane.

## Before verification

Baseline command, run before production edits:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-output-baseline-derived test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v4-output-baseline.log
```

Exit: `65`.

Observed baseline: 483 tests, 52 skipped, 181 failures. The baseline still used review pasteboard/Cmd+V output, had no 16,384-unit/readback/provenance gate, and had tag-only R5 exemptions.

## After verification

Strict lint (all 35 production files):

```text
swiftlint lint --strict
```

Exit: `0`, `0` violations. The six TextInputSimulator violations were resolved by removing all rule suppressions, using a single readback expectation value, and splitting pair preparation/submission. ReviewDestinationDelivery's complexity was also split into activation, insertion, and result helpers; no new lint suppression remains in the assigned lane.

Diff and forbidden-output check:

```text
git diff --check
rg -n "NSPasteboard|postCommandV|changeCount|restoreReviewPasteboard|captureReviewPasteboard" FeishuSpeech/Services/TextInputSimulator.swift FeishuSpeech/Services/ReviewDestinationDelivery.swift
```

Exit: `0`; no forbidden output symbols were found in the assigned output files.

Additional accepted-path scan included `Cmd+V`/`command-V`; no matches were found. `git diff --check` exited `0`.

Protected-scope check:

```text
git diff --name-only -- FeishuSpeech/Services/TextInputSimulator.swift FeishuSpeech/Services/ReviewDestinationDelivery.swift FeishuSpeech/Services/CurrentFocusAppendSession.swift FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/Models/CursorTextModels.swift | rg -n 'MainViewModel|Views|Controllers|Tests|docs|workflow'
```

Exit: `0` with no forbidden owned-diff paths. Concurrent protected-path changes were observed separately in the shared worktree and preserved.

Subset Swift typecheck (production files excluding the concurrent app/UI/coordinator roots) reached the assigned output/security files with no errors. The command exited `1` because the intentionally excluded UI type `RecordingOverlayView` is referenced by `OverlayWindowController.swift`; the log is `/tmp/issue40-v4-output-subset-typecheck3.log`.

Full Debug build after the implementation:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-output-debug-final-derived build 2>&1 | tee /tmp/issue40-v4-output-debug-final.log
```

Exit: `0` (`** BUILD SUCCEEDED **`). The parent/UI and coordinator integration now compiles through the assigned output/security files.

Focused output/current-focus/security/pasteboard/delivery test command:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-output-focused-derived -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests test 2>&1 | tee /tmp/issue40-v4-output-focused.log
```

Exit: `65` during test-target compilation. The unowned shared test target still contains legacy `ReviewDeliveryResult.inserted`, old `SystemFinalTextOutput` initializer arguments, old review-state API references, and missing `NSHostingView` import/context. `FinalTextOutputSecurityTests` now has the readback/target-PID seam, but its older success assertions still expect `.inserted` and the pre-readback trace. This is a test-author/UI migration blocker; no test files were edited by this lane.

## Remaining blocker

The test-author/UI lanes must finish migration of the stale test target and update v4 result/trace expectations. After those shared-tree repairs, rerun the v4 output/current-focus/security/pasteboard/delivery focused matrix and the full build/test command. Production files changed by this lane: `TextInputSimulator.swift`, `ReviewDestinationDelivery.swift`, `CurrentFocusAppendSession.swift`, and `CursorTextModels.swift`; `HotKeyService.swift` required no edit. No test files, UI files, or workflow files were modified by this implementation lane.

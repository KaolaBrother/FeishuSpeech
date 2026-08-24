# Issue #40 v4 R1 production repair evidence

Date: 2026-08-23 (Asia/Shanghai)
Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`

## Assigned repair

Repair the R1 modifier/physical-input race in the review output lane without
changing tests, UI, controller/state, documentation, or workflow files.

The binding-specific exact AX validation and application-current-focus identity,
trust, Secure Input, and frontmost validation now run before the submission
gate is entered. The subsequent fixed-order activation-then-input critical
section performs only the live activation/input epoch checks, the final
combined-session Command/Shift/Control/Option/Fn/Caps Lock sample, and the
mandatory prepared Unicode down/up pair. A physical or activation transition
during validation is therefore visible to the short gate and prevents the
first down event. Post-boundary pair semantics remain unchanged.

## Files

R1 repair changes:

- `FeishuSpeech/Services/TextInputSimulator.swift`
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift`

Previously implemented output/security lane files were preserved and rechecked:

- `FeishuSpeech/Models/CursorTextModels.swift`
- `FeishuSpeech/Services/CurrentFocusAppendSession.swift`

`FeishuSpeech/Services/HotKeyService.swift` was not modified in this repair.

## Verification tier

`tests-green` for the focused authored R1/R3 and output/security suites.

## Before and after verification

Before repair, the R1 RED receipt reported 20 failures in 32
`FinalTextOutputSecurityTests` tests: all exact/application plus
Command/Shift/Control/Option/Fn combinations posted one down/up pair and
returned `deliveryUncertain` instead of the required pre-boundary
`deliveryFailed` with zero posts. The prior baseline full test command also
exited 65 with 483 tests, 52 skipped, and 181 failures while the concurrent v4
lanes were still migrating.

After repair:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-r1-r3-finaltext \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test \
  2>&1 | tee /tmp/issue40-v4-r1-r3-finaltext.log
```

Exit 0. `FinalTextOutputSecurityTests`: 32 executed, 0 failures. The R1
modifier-transition oracle and both executable R3 hook/cancellation oracles
passed.

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-r1-focused-derived \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests \
  -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
  -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests test \
  2>&1 | tee /tmp/issue40-v4-r1-focused.log
```

Exit 0. Focused suites: 90 executed, 0 failures (CurrentFocus 38,
FinalTextOutputSecurity 32, ReviewDestinationDelivery 13,
ReviewPasteboardLifecycle 7).

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-r1-debug-derived build \
  2>&1 | tee /tmp/issue40-v4-r1-debug.log
```

Exit 0; `** BUILD SUCCEEDED **`.

```text
set -o pipefail; swiftlint lint --strict 2>&1 | tee /tmp/issue40-v4-r1-swiftlint.log
```

Exit 0; 0 violations, 0 serious.

```text
git diff --check
```

Exit 0.

The accepted review-output path scan for `NSPasteboard`, `postCommandV`,
`changeCount`, review pasteboard snapshot/restore helpers, and Cmd+V returned
no matches in `TextInputSimulator.swift` or `ReviewDestinationDelivery.swift`.

## R1-R5 recheck

- R1 payload cap/readback/provenance and LF/non-BMP behavior remain in the
  prepared pair implementation; focused security tests pass.
- R2 cancellation and post-boundary mandatory-up semantics remain phase-aware;
  executable R3 tests pass.
- R3 exact/application output remains one prepared modifier-free Unicode pair;
  focused output and pasteboard suites pass.
- R4 monitor arming, activation-then-input lock ordering, epoch drift gates,
  and postflight uncertainty remain active. Binding-specific validation is now
  outside the short epoch lock per the R1 repair contract; the short lock has
  no blocking AX/application validation.
- R5 self-event filtering and tap-disabled epoch advancement remain intact;
  CurrentFocus tests pass.

No test, UI, controller/state, docs, workflow, or unrelated concurrent file
was edited by this repair.

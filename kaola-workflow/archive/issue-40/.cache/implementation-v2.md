# Issue #40 v2 implementation receipt

## Task

Implement the v2 review-first production path for Issue #40: every transcription
uses one editable preview; the coordinator owns a durable draft; only explicit
Send or bare Return may deliver; presenter readiness and delivery failures retain
the exact draft for explicit retry/discard; no automatic recovery copy or direct
output is allowed; readiness telemetry is privacy-safe; and existing exact,
application-bound, fixed-PID, security, and exactly-once delivery checks remain
in force.

## Verification tier

`build-green`

The production target builds successfully. The focused review-first suite was
run before and after the implementation; four remaining failures are stale test
oracle assertions that contradict the v2 contract (details below). Tests were
not edited.

## Before

Command:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
```

Result: exit `65`; 26 tests executed with 51 assertion failures. Red receipt:
`kaola-workflow/issue-40/test-red-v2.md`.

## After

Build command:

```text
xcodebuild -scheme FeishuSpeech -configuration Debug build
```

Result: exit `0`; `** BUILD SUCCEEDED **`.

Focused test command (serialized):

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
```

Result: exit `65`; 22 passed, 4 failed, 0 skipped out of 26. Result bundle:
`/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_15-21-25-+0800.xcresult`.

The four failures are old-oracle conflicts, not unverified behavior:

1. Cancellation expects `idle`, while v2 requires retaining the exact draft with
   `deliveryCancelled` feedback for an explicit retry/discard.
2. Delivery-failure tests expect no feedback, while v2 requires fixed,
   privacy-safe failure feedback (`deliveryFailed` or `activationFailed`).
3. One legacy fake presenter expects the old synchronous readiness callback;
   production now uses the typed asynchronous readiness surface and deliberately
   does not runtime-cast to the legacy protocol.

Additional checks:

```text
git diff --check
swiftlint
```

Results: both exit `0`. SwiftLint reports two existing non-serious warnings in
`MainViewModel.swift` (cyclomatic complexity and parameter count); it reports no
serious violations.

Protected topology check: `git diff --name-only` over the capture, journal,
provider, retry, replay, and audio surfaces returned no paths. The capture-drain
and recognition-consumer loop bodies were not changed.

## Production files changed

- `FeishuSpeech/Models/TranscriptionReviewState.swift`
- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeech/Controllers/ReviewWindowController.swift`
- `FeishuSpeech/Views/TranscriptionReviewView.swift`
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift`
- `FeishuSpeech/Services/TextInputSimulator.swift`
- `FeishuSpeech/Views/SettingsView.swift`

`FeishuSpeechTests/ReviewFirstMainViewModelTests.swift` was already modified by
the test custodian and was read/run but not edited by the implementer.

## Contract notes

Legacy `AppSettings` keys remain Codable/decode-compatible, but their route
values are runtime-inert and no bypass controls are exposed in Settings. The
review presenter protocol requires the typed `renderDraft`/
`requestEditableReadiness` path; there is no synchronous or default readiness
adapter. The old automatic copy/direct-output recovery path was removed from
the review flow.

## Repair receipt (R1/R2 and ambient security retention)

### Scope and outcome

The correctness-review repairs are complete in the seven production surfaces
listed above. No test, capture, journal, transport/provider, retry/replay, or
audio file was edited by the implementer.

- R1: `ReviewEditableTransitionResult` now has only `.ready` and typed
  `.pending(...)`; the synchronous editable adapter, default readiness adapter,
  and `ReviewEditableReadinessPresenting` compatibility surface are removed.
  The coordinator retains `editablePending` for activation, application, panel,
  editor, first-responder, cancellation, timeout, and invalidation outcomes, so
  no unproven presenter result can become confirmable.
- R2: an accepted draft edit creates a new authority/surface revision and
  clears feedback attached to the prior frozen delivery attempt. A
  presentation-only readiness retry carries the existing draft and feedback
  unchanged.
- Ambient security: after a usable draft is frozen, Secure Input, permission
  revocation, and a resulting hot-key monitoring failure update the retained
  draft with privacy-safe `securityRejected` feedback, re-render the same panel,
  and produce no output, copy, or dismissal. Active pre-audio gates and
  explicit reset/sleep/cleanup remain terminal as specified.

### Repair verification

Tier: `tests-green` (focused serialized review suites).

Commands and results:

```text
xcodebuild -scheme FeishuSpeech -configuration Debug build
exit 0 — ** BUILD SUCCEEDED **

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
exit 0 — 28 passed, 0 failed, 0 skipped
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_15-59-16-+0800.xcresult

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
exit 0 — 12 passed, 0 failed, 0 skipped
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_15-59-25-+0800.xcresult

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
exit 0 — 7 passed, 0 failed, 0 skipped
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_15-58-52-+0800.xcresult

swiftlint
exit 0 — one non-serious cyclomatic-complexity warning at MainViewModel.swift:1816.

git diff --check
exit 0 — no output.

git diff --name-only -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Services/StreamingSpeechProvider.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift FeishuSpeech/Services/TransportAttemptContext.swift
exit 0 — no output; protected topology is unchanged.
```

The full test target was not used as the repair gate; the three serialized
review suites above cover the repaired coordinator, production AppKit readiness
boundary, fallback/independence behavior, and ambient security lifecycle.

Out-of-gate oracle note: `TranscriptionReviewViewTests` currently exits `65`
only because its source-string assertion at line 64 still requires the removed
`renderEditable` API. This is test-custodian-owned and was not edited by the
implementer; the production build and all three repair-focused suites are
green.

## Security repair receipt (R1: live Accessibility trust in application fallback)

### Production change

`AccessibilityTrustProviding` is now an injected, live permission boundary. The
production `MacAccessibilityClient` exposes `AccessibilityRuntime.isProcessTrusted`,
and the system fallback provider reads `AXIsProcessTrusted()` at the point of
use. `SystemReviewDestinationDelivery` requires that provider before activating
an application-current-focus destination, then samples trust at the beginning
and end of each of the two consecutive fallback preflight composites and again
in the postflight composite. Exact AX restore/validation, fixed PID, complete
application identity, Secure Input checks, and the single pasteboard/Cmd+V
transaction remain unchanged.

If trust is lost after fallback capture, explicit confirmation now returns
`.securityRejected` before activation, pasteboard snapshot/write, or Cmd+V.
The existing coordinator failure fence restores the exact frozen draft and
allows only later explicit retry/discard; no automatic retarget, retry, or copy
path was added.

### Security repair verification

```text
xcodebuild -scheme FeishuSpeech -configuration Debug build
exit 0 — ** BUILD SUCCEEDED **

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test
exit 0 — 28 passed, 0 failed, 0 skipped
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-17-34-+0800.xcresult

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests test
exit 65 — 7 passed, 5 failed, 0 skipped
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-16-04-+0800.xcresult

swiftlint lint --config .swiftlint.yml
exit 0 — one existing non-serious cyclomatic-complexity warning at MainViewModel.swift:1816.

git diff --check
exit 0 — no output.

git diff --exit-code 60090c955fbd57d4b6e875acb8a9bdc42d61f032 -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Services/StreamingSpeechProvider.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift FeishuSpeech/Services/TransportAttemptContext.swift
exit 0 — no output; protected capture/recognition/transport/retry/replay/audio topology is unchanged.
```

The five fallback-suite failures are legacy test fixtures that construct
`SystemReviewDestinationDelivery` without an injected trust provider; the test
host reports live AX trust as false, so the repaired production gate correctly
returns `.securityRejected` before activation and output. The fixtures require
the test custodian's mutable trust fake for the new post-capture revocation
regression; production was not weakened to make these stale fixtures pass.

Security-repair production files changed in this section:

- `FeishuSpeech/Services/AccessibilityClient.swift`
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift`

## Lint repair receipt (finishReviewTransition structural split)

The final-tree strict-lint finding at `MainViewModel.swift:1816` was in
`finishReviewTransition(...)`. The function now delegates only the typed
`ReviewEditableTransitionResult` to `editableReviewState(...)`, which constructs
the same `.editable` or `.editablePending` state. Callback revision fencing,
authority checks, readiness telemetry, presenter order, and transition cleanup
remain in the original function; no lint threshold or rule was changed.

Verification after this production-only refactor:

```text
swiftlint lint --strict --config .swiftlint.yml
exit 0 — 0 violations, 0 serious, 35 Swift files linted.

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
exit 0 — 29 tests passed, 0 failures.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-48-31-+0800.xcresult

xcodebuild -scheme FeishuSpeech -configuration Debug build
exit 0 — ** BUILD SUCCEEDED **

git diff --check
exit 0 — no output.

git diff --exit-code 60090c955fbd57d4b6e875acb8a9bdc42d61f032 -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Services/StreamingSpeechProvider.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift FeishuSpeech/Services/TransportAttemptContext.swift
exit 0 — no output; protected capture/recognition/transport/retry/replay/audio topology is unchanged.
```

Additional production file changed by this repair:

- `FeishuSpeech/ViewModels/MainViewModel.swift`

## Implementation v3 receipt (review surface and AppKit readiness)

### Scope and design

The v3 production repair is limited to `FeishuSpeech/Views/TranscriptionReviewView.swift`
and `FeishuSpeech/Controllers/ReviewWindowController.swift`; no tests, workflow
documents, or protected capture/recognition/transport/retry/replay/audio files
were edited by this implementer.

- `TranscriptionReviewTypography.transcriptFontSize` is one internal shared
  18pt constant. It is applied to non-empty streaming/sealing transcript text
  and the native editable `NSTextView`; `updateNSView` does not reset the font,
  and status/button typography is unchanged.
- Pending UI has no visible `重试编辑` control or text. `发送` is rendered only
  when the review state is genuinely confirmable (`canConfirm`), while Return
  remains fenced by the existing exact `.editable` confirmation guard. No
  automatic retry, direct output, copy, retarget, or security bypass was added.
- A false accessory-app activation request is advisory. The same panel is
  materialized/keyed and readiness continues polling actual application-active,
  panel-key, editor materialized/attached, and first-responder predicates;
  unmet predicates remain typed pending/timedOut.
- `.fullSizeContentView` was removed and the panel retains the exact existing
  dimensions (`520x320`, min `420x240`, max `760x600`). The `.closable` style
  remains stable while closability is controlled by the close-button visibility,
  preserving one panel identity and titlebar-safe geometry across states.

The v3 RED receipt recorded four focused UI tests with six failures: transcript
font measured 13pt instead of the required 18pt, `重试编辑` remained visible,
and streaming content intersected traffic-light controls. The unchanged panel
size test passed; the coordinator baseline was already green.

### v3 verification

Tier: `tests-green` (focused serialized v3 behavior, readiness, coordinator,
security, and lifecycle suites).

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_transcriptFontIsMateriallyLargerInStreamingAndEditableSurfaces \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_frozenDraftExposesSendAndReturnWithoutRetryEditingControl \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_streamingReviewContentDoesNotIntersectTrafficLightControls \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_reviewPanelRetainsExistingSizeAcrossStreamingAndEditableStates \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
exit 0 — 4 passed, 0 failures.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_17-42-44-+0800.xcresult

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_realProductionSurfaceMakesFrozenDraftConfirmableWithoutRetryEditing \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
exit 0 — 1 passed, 0 failures.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_17-42-56-+0800.xcresult

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
exit 0 — 10 passed, 0 failures, including activation-advisory, delayed-predicate,
and never-ready typed-timeout cases.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_17-43-13-+0800.xcresult

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
exit 0 — 30 passed, 0 failures.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_17-43-25-+0800.xcresult

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
exit 0 — 16 passed, 0 failures, including live-trust loss after capture and
pre/postflight fail-closed delivery cases.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_17-43-32-+0800.xcresult

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
exit 0 — 23 passed, 0 failures.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_17-45-05-+0800.xcresult

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
exit 0 — 7 passed, 0 failures.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_17-45-11-+0800.xcresult

swiftlint lint --strict --config .swiftlint.yml
exit 0 — 0 violations, 0 serious; 35 Swift files linted.

xcodebuild -scheme FeishuSpeech -configuration Debug build
exit 0 — ** BUILD SUCCEEDED **

git diff --check
exit 0 — no output.

git diff --exit-code 60090c955fbd57d4b6e875acb8a9bdc42d61f032 -- \
  FeishuSpeech/Services/AudioRecorder.swift \
  FeishuSpeech/Services/ByteBoundedAudioIngress.swift \
  FeishuSpeech/Services/HoldPacketJournal.swift \
  FeishuSpeech/Services/FeishuStreamingSession.swift \
  FeishuSpeech/Services/FeishuAPIService.swift \
  FeishuSpeech/Services/StreamingSpeechProvider.swift \
  FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift \
  FeishuSpeech/Services/TransportAttemptContext.swift
exit 0 — no output; protected topology unchanged.
```

## v3 feedback-copy repair receipt

Production-only repair in `FeishuSpeech/Views/TranscriptionReviewView.swift`:

- `.deliveryUncertain` now explicitly warns that another explicit send may
  duplicate prior output: `输入状态不确定；再次发送可能造成重复输入。`
- `.activationFailed` now accurately identifies target-application activation
  failure and preserves the explicit-send boundary:
  `无法激活目标应用；请确认后再发送。`
- No retry-editing button, action, or `重试编辑` text was reintroduced; all
  existing UI, readiness, delivery, and security behavior is unchanged.

Before repair, the two new feedback tests failed with three assertions (the
uncertain copy lacked duplicate-output warning; activation copy both omitted
the target application and incorrectly claimed editor preparation).

Verification:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_deliveryUncertainFeedbackWarnsAboutPossibleDuplicateSendWithoutRetryEditing \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_activationFailedFeedbackNamesTargetApplicationWithoutPreparationOrRetryText \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
exit 0 — 2 passed, 0 failures.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_18-00-59-+0800.xcresult

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
exit 0 — 10 passed, 0 failures.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_18-01-06-+0800.xcresult

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_nonCancellationDeliveryFailureReturnsFrozenDraftToEditableWithoutRecoveryCopy \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
exit 0 — 1 passed, 0 failures.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_18-01-30-+0800.xcresult

swiftlint lint --strict --config .swiftlint.yml
exit 0 — 0 violations, 0 serious; 35 Swift files linted.

git diff --check
exit 0 — no output.
```

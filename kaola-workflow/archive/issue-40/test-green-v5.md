# Issue #40 v5 test receipt

Baseline: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305` (the production facade/control-plane/raw executor tree was already present in the worktree; production files were not edited by this test lane).

## Test custody

Changed only these test artifacts:

- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`
- `FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift`
- `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift`
- `FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift`
- `FeishuSpeechTests/TranscriptionReviewViewTests.swift`

The exhaustive switches now account for `.preparingSubmission` and `.submittedUnverifiedTerminal`. The new composition oracles use the actual `ReviewSubmissionControlPlane`/`ReviewSubmissionExecutor` APIs and a production-facade coordinator spy; no test calls the legacy `ReviewDestinationDelivering` path for the v5 coordinator case.

## Focused commands

All commands were serialized with `-parallel-testing-enabled NO`.

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_11-49-38-+0800.xcresult`

49 tests executed: 48 passed, 1 failed test with 20 assertions. The failing legacy v4 selector is `test_v4BindingSpecificFinalValidationModifierTransitionIsPreBoundaryForExactAndApplicationRoutes`; current production returned `destinationInvalid`/`deliveryUncertain` instead of the old `deliveryFailed`, and the application-bound route posted its pair. The new v5 executor/control-plane selectors all passed, including deadline/descriptor preservation, admission-before-start zero raw work, cancellation phases, stale handles, mandatory key-up, gate recheck, occupied executor heartbeat, and physical-input ordering.

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_11-52-10-+0800.xcresult`

14 tests executed, 14 passed. The activation-request advisory tests now assert the v5 non-activating panel does not request FeishuSpeech activation (`activationRequestCount == 0`) while real application/key/editor/attachment/first-responder predicates remain authoritative telemetry.

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_11-52-03-+0800.xcresult`

13 tests executed, 13 passed. This includes shared 18pt transcript sizing, unchanged 520x320 panel size, traffic-light separation, explicit Send/no default key equivalent, no retry-editing control, duplication warning, activation-failure copy, and opaque Return qualification source oracles.

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_11-52-46-+0800.xcresult`

1 test executed, 1 failed with the intended production handoff oracle:

```text
XCTAssertEqual failed: (preparingSubmission(draft: "PRIVATE_FACADE_RETRY", ...)) is not equal to (submittedUnverifiedTerminal(draft: "PRIVATE_FACADE_RETRY", ..., feedback: deliveryUncertain))
```

Before that terminal assertion, the test passes the concrete composition checks: one issued handle per explicit confirmation, one admission per revision, action-2/recorder barrier before editable, exact draft retention after cancellation, explicit retry creates exactly one new handle/envelope, and the target is released with no legacy delivery. The failure identifies that `MainViewModel.handleReviewSubmissionTerminal(.submittedUnverified)` renders the terminal state through the presenter but does not publish `.submittedUnverifiedTerminal` to `transcriptionReviewState`.

The migrated three-selector legacy confirmation snapshot was also run:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_actionTwoFinalTransitionsSameSurfaceToEditableAndOnlyConfirmDelivers -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_confirmationFreezesExactCurrentNonWhitespaceDraftAndDeliversOnce -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_repeatedBareReturnFromNativeEditorDeliversExactDraftOnce test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_11-55-08-+0800.xcresult`

3 tests executed, 3 failed on the same exact state mismatch (`preparingSubmission` versus required `submittedUnverifiedTerminal`). The old presenter fixture now mints the opaque `qualifiedPreviewReturn` intent after materializing a real editor; it does not use a zero-argument coordinator bypass.

Full `ReviewFirstMainViewModelTests` snapshot after the fixture migration: result bundle `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_11-53-52-+0800.xcresult`, 32 tests executed, 28 passed, 4 failed. All four failures are the same submitted-unverified state publication oracle (three legacy snapshots plus the v5 facade test).

`git diff --check` passed. No production, project, architecture, mission-list, or workflow source was changed by this lane; the only non-test write is this canonical receipt.

Keyboard/confirm lane:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_11-59-16-+0800.xcresult`

16 tests executed, 16 passed. The migrated fixture now mints the opaque qualified-Return intent only for bare non-repeat main/keypad Return; Shift/IME/Option/Control/Command/repeat paths remain zero-intent or LF pass-through, and whitespace drafts remain inert.

Combined presentation/keyboard rerun:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_11-59-45-+0800.xcresult`; 29 tests executed, 29 passed.

## Physical-observer fixture correction

The `test_physicalInputAtGateOrdersAfterCompleteMandatoryPair` fixture no
longer calls `CurrentFocusCombinedInterferenceEpoch.shared.advance()` from the
injected `postDown` thread. It starts a separate deterministic
`.userInteractive` serial queue during down; the callback attempts the real
epoch advance while the commit reservation is held. The fixture records that
the callback did not complete before `postUp`, waits for its completion after
the reservation releases, and retains the exact `[.prepare, .down, .up]`
mandatory-pair oracle. This exercises a cross-thread observer and does not
require a recursive epoch lock.

Focused selector:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_physicalInputAtGateOrdersAfterCompleteMandatoryPair test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_12-23-59-+0800.xcresult`

1 test executed, 1 failed. The cross-thread ordering assertions pass:
physical callback attempted during down, `physicalEpochAdvancedBeforeUp ==
false`, callback completion is observed after the reservation, and operations
remain `[.prepare, .down, .up]`. The production postflight receipt is still
`postflightStable == true`, so the required uncertainty assertion fails at
`FinalTextOutputSecurityTests.swift:606`:

```text
XCTAssertFalse failed: observation.postflightStable
```

This is a production handoff: the callback is already contending on the real
epoch primitive from another queue, but the executor can complete its
postflight sample before that queued observer advances the epoch. The fixture
does not add a fake lock handoff or relax the uncertainty oracle.

Full serialized security rerun after the fixture correction:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_12-24-50-+0800.xcresult`

49 tests executed, 48 passed, 1 failed. The sole failure is the corrected
physical-observer selector above; all other FinalTextOutputSecurityTests,
including both exact/application-bound output, deadline, cancellation,
provenance, stale-handle, mandatory-up, and no-pasteboard oracles, passed.

`git diff --check` passed after the fixture correction. No production or
project file was edited.

## v5 correctness-review R1-R7 RED handoff

The seven blocking findings in `.cache/code-review-v5.md` were converted to
named acceptance oracles and run against baseline
`b321ac5d6c04c91ced9afeb2240f9566d9b8d305`. The source-contract assertions are
deliberately strict: they fail while the current production surface lacks the
required seam, and they do not substitute a fake for the missing production
composition.

Focused RED command (serialized):

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5ExactCursorCaptureOwnsOriginalFocusAndSelectionThroughSubmission \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5ExecutorStabilizesRelevantModifiersAndRechecksAtFinalGate \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5FacadeComposesLifecycleObserversAndFinalCapturedTargetSample \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5RawCaptureDistinguishesOrdinaryAXMissFromSecureOrUnverifiableFailure \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests/test_focusReadinessRequiresTheExactCapturedApplicationIdentity \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_v4OnlyOpaqueIntentFromQualifiedNativeReturnCanAuthorizeDelivery \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_v5IntentConstructionIsConfinedToRealSendOrPanelReturnGestureSites test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_13-00-06-+0800.xcresult`

7 tests executed, 11 assertion failures (the intended RED):

- R1 `FinalTextOutputSecurityTests.test_v5ExactCursorCaptureOwnsOriginalFocusAndSelectionThroughSubmission`: exact raw target lacks `originalSelection`/captured focused-element custody (2 failures).
- R2 `...test_v5ExecutorStabilizesRelevantModifiersAndRechecksAtFinalGate`: no combined modifier sample, `.modifierInstability` fail-closed result, or final-gate modifier recheck (3 failures).
- R3 `...test_v5FacadeComposesLifecycleObserversAndFinalCapturedTargetSample`: accepted facade does not arm lifecycle/observer-loss coverage (1 failure).
- R4 `...test_v5RawCaptureDistinguishesOrdinaryAXMissFromSecureOrUnverifiableFailure`: ordinary AX timeout is not explicitly separated from typed secure/unverifiable rejection (1 failure).
- R6 `ReviewWindowControllerReadinessTests.test_focusReadinessRequiresTheExactCapturedApplicationIdentity`: request/readiness lacks captured stable application identity comparison (2 failures).
- R7 `TranscriptionReviewViewTests.test_v4OnlyOpaqueIntentFromQualifiedNativeReturnCanAuthorizeDelivery` and `...test_v5IntentConstructionIsConfinedToRealSendOrPanelReturnGestureSites`: Return factory is still module-internal rather than fileprivate to the real gesture sites (2 failures).

R5 executable RED command and signature:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_13-02-31-+0800.xcresult`

1 test executed, 3 failures. After a real production-composition capture,
action-2/recorder barrier, editable draft, and explicit opaque confirmation,
the terminal receipt leaves the ordinary preview alive:

```text
XCTAssertEqual: submittedUnverifiedTerminal(draft: "PRIVATE_FACADE_RETRY", ...) != idle
XCTAssertEqual: "PRIVATE_FACADE_RETRY" != ""
XCTAssertNil failed: retained ReviewPanel != nil
```

The same test still proves one handle/admission per explicit confirmation,
exact draft retention before the terminal, no resend control, target release,
and zero legacy delivery calls. The RED is specifically the required
submitted-unverified dismiss/idle cleanup.

The complete serialized focused matrix was then run with the seven R1-R7
selectors, the readiness/view/keyboard suites, R5, the migrated non-activating
delivery oracle, and the two trust/fallback retention oracles:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend \
  -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests/test_systemReviewDelivery_nonactivatingTargetPreservesCapturedFrontmostAndDoesNotRetarget \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests/test_reviewFirst_applicationBoundConfirmationFailureReturnsExactDraftWithoutCopy \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests/test_reviewFirst_trustRevokedAfterCaptureRetainsExactDraftAndAuthorityWithoutOutput test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_13-03-12-+0800.xcresult`

102 tests executed, 14 failures. The 14 failures are exactly the 11 R1-R4/R6/R7
source-contract assertions plus the 3 R5 terminal-cleanup assertions above.
The non-blocking acceptance/safety lanes passed: 15 readiness tests apart
from the 2 R6 assertions, 16 native keyboard tests, 12 other review-view
tests, the migrated non-activating delivery test, and both fallback/trust
retention tests. No production file was changed by this test lane.

`git diff --check` passed after the R1-R7 and R5 oracle additions. Production
repair is required for the 7 RED blockers; this lane does not implement it.

## R5-R7 API migration (parse-only checkpoint)

The production R5-R7 repair moved `ReviewConfirmationIntent`, its initializer,
and both fileprivate factories into `ReviewWindowController.swift`; the
SwiftUI view now accepts only a no-argument Send gesture callback. Tests were
migrated without running xcodebuild while the output lane was still editing:

- direct `TranscriptionReviewView` fixtures in `TranscriptionReviewViewTests`
  and streaming/coordinator fixtures now use no-argument callbacks;
- coordinator/fallback/native presenters now exercise a real production
  `ReviewWindowController`/`ReviewPanel` Send or qualified Return route rather
  than manufacturing an intent in test code;
- the R7 source oracle now requires no intent/factory in the SwiftUI view,
  fileprivate initializer/factories in the controller, and no minting path in
  `MainViewModel`;
- readiness fixtures now inject exact live `StableApplicationIdentity` values
  and cover captured-A success plus other-app and same-PID relaunched-A
  rejection, while retaining the existing terminal idle/dismiss oracle.

Parse-only validation (no test execution by request):

```text
swiftc -parse FeishuSpeechTests/FinalTextOutputSecurityTests.swift FeishuSpeechTests/ReviewDestinationDeliveryTests.swift FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift FeishuSpeechTests/ReviewFirstMainViewModelTests.swift FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift FeishuSpeechTests/StreamingMainViewModelTests.swift FeishuSpeechTests/TranscriptionReviewViewTests.swift
git diff --check
```

Both checks passed. This is a fixture-migration checkpoint, not a GREEN
verdict; the next lane must run the focused matrix after production edits
settle.

## Callback-arity fixture correction

The first compile-only handoff identified one remaining arity mismatch at
`TranscriptionReviewViewTests.swift:249`: this call is
`ReviewWindowController.renderDraft`, whose `onConfirm` remains the typed
`ReviewConfirmationIntent` callback. It was restored to `{ _ in }`; direct
SwiftUI `TranscriptionReviewView` fixtures remain no-argument callbacks.

The seven-file `swiftc -parse` command and `git diff --check` were rerun after
that test-only correction; both passed. No xcodebuild/test execution was run
in this checkpoint.

## Optional panel fixture correction

The next compile-only handoff identified
`ReviewFirstMainViewModelTests.swift:2352`: the migrated native presenter was
passing `panel?.contentView` to a helper requiring `NSView`. The fixture now
binds the retained `ReviewPanel` and materialized editor separately, clears a
stale editor value, and only calls `editableTextView(in:)` with the bound
nonoptional content view. A repository scan found no other matching optional
content-view calls.

The seven-file `swiftc -parse` command and `git diff --check` passed again.
No xcodebuild/test execution was run in this checkpoint.

## Captured-target submission validation and real gesture reconciliation (2026-08-24)

Baseline remains `b321ac5d6c04c91ced9afeb2240f9566d9b8d305`; this lane changed
tests only. The new acceptance oracle
`FinalTextOutputSecurityTests/test_v5SubmissionValidationUsesCapturedCursorOrApplicationElementWithoutAmbientFocusLookup`
reads the real production validation routines and requires the exact binding
to restore `target.focusedElement` plus `target.originalSelection` directly,
and the application-bound binding to query the captured
`target.applicationElement`/`kAXFocusedUIElementAttribute`. Both validation
slices must not call `AXUIElementCreateSystemWide`, which would incorrectly
replace the captured target with ambient focus after the review panel becomes
key.

Focused source/security command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5SubmissionValidationUsesCapturedCursorOrApplicationElementWithoutAmbientFocusLookup \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5RawCaptureDistinguishesOrdinaryAXMissFromSecureOrUnverifiableFailure test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_13-59-41-+0800.xcresult`

`2 tests executed, 0 failures`. The semantic source oracle initially failed on
the baseline/current production slice ordering (`FinalTextOutputSecurityTests.swift:57`,
`submission validation must keep distinct exact-cursor and application-bound routines`);
the test fixture was corrected to follow the actual declaration order and then
the oracle passed. This is source evidence, not a claim that the full product
matrix is green.

The two migrated fallback tests were rerun through the real production
controller's Send mouse bridge (not a fabricated confirmation intent):

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests/test_reviewFirst_applicationBoundConfirmationFailureReturnsExactDraftWithoutCopy \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests/test_reviewFirst_trustRevokedAfterCaptureRetainsExactDraftAndAuthorityWithoutOutput test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_13-52-58-+0800.xcresult`

`2 tests executed, 0 failures`; the assertions retain the exact draft and
authority and prove zero clipboard/AX/keyboard output under fallback and trust
revocation.

The real-controller readiness class was rerun serialized:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-00-08-+0800.xcresult`

`17 tests executed`; 16 test cases passed. The single real Send/qualified
Return integration case remains blocked by the XCTest accessory/headless host:
both focus attempts return `.notFocused(.timedOut(lastUnmet: .panelKey))`,
`panel.isKeyWindow == false`, `panel.firstResponder !== editor`, and the
qualified Return callback remains at `1` instead of `2`. The test deliberately
does not inject `panelIsKey`, call a callback directly, or mint an intent; the
real Send mouse route remains exercised. The other readiness tests, including
real editor materialization/attachment predicates and captured identity cases,
pass.

The production-composition MainViewModel facade selector was also run:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_13-57-25-+0800.xcresult`

The retry assertion fails at `ReviewFirstMainViewModelTests.swift:369-370`:
the explicit real Send retry does not create a second callback/admission
(`confirmGestureCount == 1`, expected `2`), followed by the bounded wait and
retry-admission guard failures. No direct confirmation bypass was added.

The real production-surface frozen-draft selector was run after adding a
bounded main-run-loop/sleep allowance:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_realProductionSurfaceMakesFrozenDraftConfirmableWithoutRetryEditing test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-01-45-+0800.xcresult`

It still times out at `ReviewFirstMainViewModelTests.swift:1596`: the real
focus probe is never called (`make/check == 0`). This is recorded as a
production-composition/test-host blocker rather than weakening the editor
first-responder oracle.

Finally, the seven-file parse check and `git diff --check` both pass. The
remaining failures above are explicit handoff evidence; this test lane does
not claim a full v5 GREEN verdict.

## Test-only recovery/identity fixture cleanup (2026-08-24)

Without running xcodebuild (the UI implementation lane was still editing),
the real production-surface readiness fixture was corrected to provide the
exact captured `StableApplicationIdentity` used by the deterministic delivery
fixture and `feishuSpeechIsActive == false`. This prevents the readiness loop
from failing at captured-application validation before it can invoke the
first-responder probe. The fixture remains test-only and retains production
editor lookup/attachment behavior.

Added selector:
`ReviewFirstMainViewModelTests/test_reviewFirst_realControllerRecoveryRendersEditableAgainAndRoutesSecondSend`.
It renders editable A, sends through the real controller/panel mouse bridge,
renders preparing then editable A with `deliveryUncertain`, edits the retained
same panel to B, and sends again through the same real bridge. It records both
opaque confirmation callbacks and exact A/B draft values; no intent is minted
by the test.

The older MainViewModel delivery expectations were migrated from retained
terminal transcript state to the required `.idle`/dismiss contract. After
successful delivery they now assert empty `reviewDraftText` and presenter
dismissal, while preserving exact text, no-copy, and exactly-once delivery
oracles. The production-facade terminal cleanup oracle remains unchanged.

Parse/diff-only validation for this cleanup:

```text
swiftc -parse FeishuSpeechTests/ReviewFirstMainViewModelTests.swift
git diff --check
```

Both checks passed. No xcodebuild command was run in this checkpoint, pending
the UI implementer's arbiter/testability decision for the accessory-host
`panel.isKeyWindow` limitation.

## UI-lane recovery reconciliation (2026-08-24)

The UI implementation lane confirmed that delivery feedback shifts the lower
control band upward and that the controller's Return arbiter samples the
injected `ReadinessEnvironment.panelIsKey` seam while the AppKit default still
uses `panel.isKeyWindow`. The test-only real Send probe now scans y positions
22 through 90 and stops immediately after the first observed opaque callback.
The deterministic helper injects only panel-key telemetry; it still drives
real panel mouse/key events and production editor lookup/attachment.

The captured-identity production-surface selector was rerun after adding the
exact fake delivery identity and `feishuSpeechIsActive == false`:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_realProductionSurfaceMakesFrozenDraftConfirmableWithoutRetryEditing test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-13-32-+0800.xcresult`

`1 test executed, 0 failures`; the real focus log reached `result=focused`,
and the materialized editor/attached-panel/first-responder and explicit Send
assertions passed.

The new real-controller recovery selector was run serially:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_realControllerRecoveryRendersEditableAgainAndRoutesSecondSend test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-13-22-+0800.xcresult`

`1 test executed, 0 failures`; real Send callbacks were exactly
`[PRIVATE_RECOVERY_A, PRIVATE_RECOVERY_B]` on the same retained ReviewPanel.

The migrated MainViewModel and terminal-cleanup selectors were rerun after
the native editor fixture gained deterministic layout/materialization:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_actionTwoFinalTransitionsSameSurfaceToEditableAndOnlyConfirmDelivers \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_confirmationFreezesExactCurrentNonWhitespaceDraftAndDeliversOnce \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_repeatedBareReturnFromNativeEditorDeliversExactDraftOnce \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-14-51-+0800.xcresult`

`4 tests executed, 0 failures`; exact draft/newline preservation, no-copy,
exact-once delivery, repeated native Return, cancellation recovery, and
submitted-unverified idle/dismiss cleanup all passed.

The real controller Send/Return readiness selector then passed with injected
panel-key telemetry:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests/test_controllerUsesRealPanelSendAndQualifiedReturnGestureRoutes test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-15-30-+0800.xcresult`

`1 test executed, 0 failures`. The test intentionally does not assert the
headless host's ambient `panel.isKeyWindow`; production's default remains
unchanged, while the native Send and qualified Return event paths each invoke
one opaque callback.

Full serialized readiness class after the helper update:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-15-40-+0800.xcresult`

`17 tests executed, 0 failures`. `swiftc -parse` for the changed test files
and `git diff --check` also pass. All changes remain test-only.

## ReviewFirst presenter control-band fixture correction (2026-08-24)

The 306-test focused matrix isolated its only failure to
`ReviewFirstMainViewModelTests/test_reviewFirst_deliveryFailureReturnsExactDraftToEditableWithoutFocusRetry`:
the legacy `Issue38ReviewSurfacePresenter.invokeConfirm` drove only y=30,
while recovery feedback moves the Send control band upward. The test fixture
now scans the same y=22…90 band as the production presenter, wraps the real
controller callback for an observed-count stop, and never manufactures an
intent. Once the first real mouse gesture reaches the callback, subsequent
coordinates are not sent.

Full serialized ReviewFirst class:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-18-40-+0800.xcresult`

`33 tests executed, 0 failures`. The focused delivery-failure recovery now
proves exact draft retention, editable retry, and exactly one second real Send
admission. Parse and `git diff --check` remain clean; production remains
untouched.

## Canonical final focused-matrix GREEN (2026-08-24)

This section supersedes the earlier intermediate RED/fixture-failure entries
for the focused v5 matrix. Root reran the complete serialized matrix after the
control-band fixture correction; the authoritative raw log is
`/tmp/issue40-focused-v5-r6.log`.

Exact command from the log:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests \
  -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test
```

Result bundle:
`/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-19-22-+0800.xcresult`

Authoritative result: `306 tests executed, 0 failures`; `** TEST SUCCEEDED **`.
The per-suite counts were CurrentFocusAppendSession 38, FinalTextOutputSecurity
54, ReviewDestinationDelivery 13, ReviewFirstApplicationFallback 16,
ReviewFirstMainViewModel 33, ReviewWindowControllerReadiness 17,
StreamingMainViewModel 105, TranscriptionReviewViewKeyboard 16, and
TranscriptionReviewView 14. This is the canonical focused v5 GREEN receipt;
previous single-test/intermediate failures are retained only as historical
diagnostics and are superseded by this final rerun.

## v5 security re-review RED: lifecycle lease overlap, persistent ordinary miss, and raw cancellation checkpoint (2026-08-24)

This is a new acceptance RED against the unchanged baseline
`b321ac5d6c04c91ced9afeb2240f9566d9b8d305` (the focused 306-test GREEN above
remains historical evidence for the earlier matrix). The added tests are
test-only and exercise the real `SystemReviewSubmissionFacade`/
`ReviewSubmissionExecutor` composition with injected raw/lifecycle/back-end
seams.

Exact serialized command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5LifecycleLeaseOverlapKeepsCaptureBArmedAndRejectsOnItsObserverEvent \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5LifecycleReleaseOfStaleTargetDoesNotDisarmNewerLease \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5RawValidationCancellationCheckpointStopsTheUninterruptedAXSequence \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5ApplicationBoundValidationDoesNotCollapseOrdinaryMissIntoTimeout \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5ApplicationBoundPersistentOrdinaryMissRemainsAllowedWhileSecurityFailuresFailClosed test
```

Result bundle:
`/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-39-17-+0800.xcresult`

The suite compiled and executed 5 tests with 10 failures. The ordinary-miss
executable table itself passed: the injected application-bound `nil` ordinary
validation reached one submitted receipt and `[prepare, down, up]`, while
typed timeout/security failures produced no backend operations. The paired
source contract test is intentionally RED against the current implementation:

```text
FinalTextOutputSecurityTests.test_v5ApplicationBoundValidationDoesNotCollapseOrdinaryMissIntoTimeout
XCTAssertFalse failed: ordinary noValue/unsupported focus must remain allowed;
only timeout or secure/unverifiable failures may reject
XCTAssertTrue failed: submission must preserve an explicit ordinary
capability-miss path
```

The lifecycle overlap oracle failed on the current single-lease facade:

```text
FinalTextOutputSecurityTests.test_v5LifecycleLeaseOverlapKeepsCaptureBArmedAndRejectsOnItsObserverEvent
activeTarget: nil != identityB
receipt: submittedUnverified(...) != notStarted(inputDrift)
backend operations: [prepare, down, up] != []
observerEpochAdvanceCount: 0 != 2

FinalTextOutputSecurityTests.test_v5LifecycleReleaseOfStaleTargetDoesNotDisarmNewerLease
activeTarget after release(A): nil != identityB
disarmCount: 1 != 0
disarmCount after release(B): 2 != 1
```

The raw cancellation checkpoint oracle also failed as intended:

```text
FinalTextOutputSecurityTests.test_v5RawValidationCancellationCheckpointStopsTheUninterruptedAXSequence
operations: [setFocused, setSelectedRange, readback] != [setFocused]
```

The terminal receipt was still the typed pre-boundary
`.notStarted(.cancellation)` and backend operations remained empty; the RED
is specifically the missing attempt-scoped cancellation checkpoint inside
the uninterrupted AX sequence. The implementing lane must repair the lease
identity/token ownership, persistent ordinary application-bound classifier,
and cancellation-aware raw validation before rerunning these selectors.

## v5 R2 blocker reconciliation GREEN (2026-08-24)

Production added the attempt-scoped
`ReviewSubmissionRawAccessibilityRuntime.validate(_:deadline:cancellationProbe:)`
seam. The test-only `V5CancellationCheckpointRawRuntime` now implements that
contract, samples the probe immediately after the suspended `setFocused`
checkpoint, returns typed `.cancellation`, and asserts both
`cancellationObservedAtCheckpoint == true` and the exact operation list
`[.setFocused]`. No production or non-test artifact was edited in this step.

Parse and diff checks:

```text
swiftc -parse FeishuSpeechTests/FinalTextOutputSecurityTests.swift
git diff --check
```

Both passed.

The five R2 blocker selectors were rerun serially:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5LifecycleLeaseOverlapKeepsCaptureBArmedAndRejectsOnItsObserverEvent \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5LifecycleReleaseOfStaleTargetDoesNotDisarmNewerLease \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5RawValidationCancellationCheckpointStopsTheUninterruptedAXSequence \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5ApplicationBoundValidationDoesNotCollapseOrdinaryMissIntoTimeout \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5ApplicationBoundPersistentOrdinaryMissRemainsAllowedWhileSecurityFailuresFailClosed test
```

Result bundle:
`/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-55-23-+0800.xcresult`

`5 tests executed, 0 failures`; `** TEST SUCCEEDED **`. This closes the
previous RED signatures: B retains its lifecycle lease and observer epoch,
releasing stale A leaves B armed, ordinary application-bound misses remain
allowed while timeout/security outcomes fail closed, and cancellation after
`setFocused` produces no selected-range/readback or pair operations.

The complete serialized `FinalTextOutputSecurityTests` suite was then run:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test
```

Result bundle:
`/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_14-55-32-+0800.xcresult`

`59 tests executed, 0 failures`; `** TEST SUCCEEDED **`.

## v5 real Send event anti-hang reconciliation GREEN (2026-08-24)

The test-only real-panel Send helper was repaired after
`.cache/send-click-test-hang-diagnosis.md` showed that synchronously sending a
mouse-down can enter an NSTextView tracking loop before the helper has a chance
to send mouse-up. The helper now posts the complete down/up pair to the real
AppKit queue and drains that queue with a 50 ms deadline. It still traverses
the retained `ReviewPanel` and SwiftUI Send control; the controller remains the
only minting path for `ReviewConfirmationIntent`, and the helper never calls a
confirmation closure or constructs an intent. Presenter fixtures scan the
materialized control band and stop only when the controller-wrapped callback
count changes.

Baseline failure evidence: commit
`b321ac5d6c04c91ced9afeb2240f9566d9b8d305` with the former synchronous
`panel.sendEvent(down); panel.sendEvent(up)` helper was bounded by a 40 s alarm
and terminated with exit `142` while AppKit was inside the NSTextView tracking
path (`_bellerophonTrackMouse...` / `nextEvent` / `mach_msg`). The helper had
not yet reached its mouse-up call. This is the failure signature that the
queue-paired, bounded event pump below falsifies; no intent or callback was
manufactured to bypass the route.

The focused coordinator selector was run five serialized times with a 40 s
per-run alarm bound:

```text
perl -e '$SIG{ALRM}=sub { exit 124 }; alarm 40; exec @ARGV' \
  xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath "$run_dd" \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend test
```

All five repetitions executed one test with zero failures and completed within
the bound:

| Run | Log | Result bundle | Duration |
| --- | --- | --- | --- |
| 1 | `/tmp/issue40-send-click-r2i-1.log` | `/tmp/issue40-send-click-r2i-1.mMOtNK/Logs/Test/Test-FeishuSpeech-2026.08.24_15-28-58-+0800.xcresult` | 2.728 s |
| 2 | `/tmp/issue40-send-click-r2i-2.log` | `/tmp/issue40-send-click-r2i-2.yFts1O/Logs/Test/Test-FeishuSpeech-2026.08.24_15-29-28-+0800.xcresult` | 2.719 s |
| 3 | `/tmp/issue40-send-click-r2i-3.log` | `/tmp/issue40-send-click-r2i-3.tzFFKB/Logs/Test/Test-FeishuSpeech-2026.08.24_15-29-50-+0800.xcresult` | 2.744 s |
| 4 | `/tmp/issue40-send-click-r2i-4.log` | `/tmp/issue40-send-click-r2i-4.XR7s60/Logs/Test/Test-FeishuSpeech-2026.08.24_15-30-13-+0800.xcresult` | 2.721 s |
| 5 | `/tmp/issue40-send-click-r2i-5.log` | `/tmp/issue40-send-click-r2i-5.MtDBen/Logs/Test/Test-FeishuSpeech-2026.08.24_15-30-36-+0800.xcresult` | 2.776 s |

Exact aggregate: `5 tests executed, 0 failures`; every log ended with
`** TEST SUCCEEDED **`.

The complete affected focused classes were then run serialized:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-send-click-reviewfirst-r2.JX22FN \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test
```

Result bundle:
`/tmp/issue40-send-click-reviewfirst-r2.JX22FN/Logs/Test/Test-FeishuSpeech-2026.08.24_15-35-07-+0800.xcresult`

`33 tests executed, 0 failures`; `** TEST SUCCEEDED **`.

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-send-click-readiness-r2.Erbuvn \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test
```

Result bundle:
`/tmp/issue40-send-click-readiness-r2.Erbuvn/Logs/Test/Test-FeishuSpeech-2026.08.24_15-34-42-+0800.xcresult`

`17 tests executed, 0 failures`; `** TEST SUCCEEDED **`. The readiness suite
therefore exercises the real panel Send/qualified Return routes without the
former synchronous coordinate-miss hang.

Validation also passed:

```text
swiftc -parse FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift
swiftc -parse FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift
swiftc -parse FeishuSpeechTests/StreamingMainViewModelTests.swift
swiftc -parse FeishuSpeechTests/ReviewFirstMainViewModelTests.swift
git diff --check
```

Changed custody remains test-only in the four test files
`ReviewWindowControllerReadinessTests.swift`, `ReviewFirstMainViewModelTests.swift`,
`ReviewFirstApplicationFallbackTests.swift`, and `StreamingMainViewModelTests.swift`.
No production source was edited for this repair.

## v5 R11 real-panel Return authority matrix RED (2026-08-24)

The R11 keyboard oracle was migrated from the test-local `confirmGesture` /
`shouldRouteQualifiedReturn` decision tree to a retained production
`ReviewWindowController` and its real `ReviewPanel.sendEvent` path. The fixture
observes only the controller's opaque callback, the real editor binding, and
discard state. Direct SwiftUI editor tests remain only for editing, undo,
accessibility, and layout behavior. The migrated matrix covers main Return and
keypad Enter, exact unmodified nonrepeat confirmation, Shift/Control/Option/
Command combinations, repeat events, marked-text IME input, wrong-window
events, non-key-panel events, whitespace/non-whitespace drafts, and Escape.

Baseline is the current uncommitted production tree rooted at
`b321ac5d6c04c91ced9afeb2240f9566d9b8d305`; no production file was changed by
this test migration.

The serialized keyboard selector was run with a 120 s alarm bound:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-r11-keyboard-red2.soXAAt \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests test
```

Result bundle:
`/tmp/issue40-r11-keyboard-red2.soXAAt/Logs/Test/Test-FeishuSpeech-2026.08.24_16-07-21-+0800.xcresult`

`19 tests executed, 2 failures`. The failures are the intended production
RED, not fixture skips:

```text
TranscriptionReviewViewKeyboardTests.test_editableReview_mainAndKeypadWhitespaceReturnNeverConfirm
XCTAssertEqual failed: ("[\" \\n\\t\"]") is not equal to ("[]")
```

Both main Return and keypad Enter delivered the whitespace-only draft
`" \\n\\t"` to the controller callback. The acceptance oracle requires zero
confirmation authority and unchanged editor text for a whitespace-only draft;
the current `ReviewPreviewReturnArbiter` admits it. All other migrated R11
routes passed, including wrong-window and non-key-panel zero-authority cases.
This is handed to the production owner as the precise R11 blocker; the test
was not weakened to match the defect.

The readiness companion suite was run serialized:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-r11-readiness.CsMtle \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test
```

Result bundle:
`/tmp/issue40-r11-readiness.CsMtle/Logs/Test/Test-FeishuSpeech-2026.08.24_16-08-08-+0800.xcresult`

`17 tests executed, 0 failures`; `** TEST SUCCEEDED **`.

The R11 test-only changes are in
`FeishuSpeechTests/TranscriptionReviewViewTests.swift`.

## v5 R3 pair/final-composite/expired-start RED handoff (2026-08-24)

Using `architecture-blueprint-v5-r3.md`, the test-only acceptance was extended
with executable production-composition oracles in
`FeishuSpeechTests/FinalTextOutputSecurityTests.swift`:

- exact-cursor focus/selection drift after pair preparation, without an epoch
  change, must destroy the prepared pair before down/up;
- application-bound responder/security drift after pair preparation must fail
  closed before down/up;
- Secure Input, Accessibility trust, running identity, and frontmost changes
  after pair preparation must fail closed, while a safe ordinary
  noValue/unsupported application-bound miss remains allowed;
- an admitted attempt whose immutable deadline expires before start must emit
  exactly one `.notStarted(.deadline)`, retire its record/active handle, and
  invoke no raw start handler.

The tests use the real `ReviewSubmissionExecutor`, real value-only
`ReviewSubmissionControlPlane`, injected raw runtime, and concrete prepared
pair backend. A backend `onPrepare` transition mutates the raw validation
result only after pair construction, so the current pre-final-validation
ordering cannot satisfy the oracle.

Baseline is the current uncommitted tree rooted at
`b321ac5d6c04c91ced9afeb2240f9566d9b8d305`.

Pair/final-composite selectors were run serialized:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-r3-pair-red3.ohv3B0 \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5ExactFocusOrSelectionDriftAfterPairWithoutEpochDestroysPairAndPostsNothing \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5ApplicationBoundResponderSecurityDriftAfterPairWithoutEpochDestroysPairAndPostsNothing \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5FinalCompositeTransitionsRejectSecureTrustIdentityAndFrontmostDriftButAllowSafeOrdinaryMiss test
```

Result bundle:
`/tmp/issue40-r3-pair-red3.ohv3B0/Logs/Test/Test-FeishuSpeech-2026.08.24_16-13-01-+0800.xcresult`

`3 tests executed, 24 failures`, all behavioral RED rather than compile or
skip failures. Representative exact signatures:

```text
test_v5ExactFocusOrSelectionDriftAfterPairWithoutEpochDestroysPairAndPostsNothing
submittedUnverified(mandatoryKeyUpAttempted: true, postflightStable: true)
  != notStarted(.targetIdentityChanged)
backend operations [prepare, down, up] != [prepare]

test_v5ApplicationBoundResponderSecurityDriftAfterPairWithoutEpochDestroysPairAndPostsNothing
submittedUnverified(...) != notStarted(.securityRejected)
backend operations [prepare, down, up] != [prepare]

test_v5FinalCompositeTransitionsRejectSecureTrustIdentityAndFrontmostDriftButAllowSafeOrdinaryMiss
Secure Input / Accessibility trust / running identity / frontmost rows each
submittedUnverified(...) and [prepare, down, up] instead of typed pre-boundary
failure and [prepare] only.
```

The admitted-then-expired start selector was run separately:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-r3-expired-start-red.TOWuq0 \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5AdmittedBeforeDeadlineStartAfterDeadlineEmitsOneTerminalAndNoRawWork test
```

Result bundle:
`/tmp/issue40-r3-expired-start-red.TOWuq0/Logs/Test/Test-FeishuSpeech-2026.08.24_16-14-00-+0800.xcresult`

Failure signature: `nil != .notStarted(.deadline)`, `activeHandle` remained
non-nil, and `records` remained non-empty. The start recorder remained empty,
confirming the defect is missing control-plane terminalization rather than
accidental raw output.

The coordinator composition selector was also run:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-r3-coordinator-expired-red.fcEXYA \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_v5CoordinatorExpiredStartPreservesExactDraftAndRequiresNewRealConfirmation test
```

Result bundle:
`/tmp/issue40-r3-coordinator-expired-red.fcEXYA/Logs/Test/Test-FeishuSpeech-2026.08.24_16-16-37-+0800.xcresult`

Failure signature: the coordinator remained
`.preparingSubmission(draft: "PRIVATE_EXPIRED_START_DRAFT_EDITED", feedback: nil)`
instead of restoring the exact editable draft with `.deliveryFailed`; the
second real Send therefore could not create a new handle. This pins the
matching coordinator recovery requirement without synthesizing a confirmation.

The lowest-level System AX checkpoint oracle from blueprint section 4 was not
faked or replaced with a source-string assertion: the current production tree
exposes only `ReviewSubmissionRawAccessibilityRuntime.validate`, with no
behavior-preserving System AX call table/value-only step observer for pausing
after `AXUIElementSetMessagingTimeout` returns. Adding a test against a local
stand-in would measure the stand-in, not `SystemReviewSubmissionAXRuntime`.
Production must expose that narrow seam before the cancellation/deadline-after-
timeout test can be authored as an executable subject oracle.

## v5-r3 final GREEN verification (2026-08-24)

Production now exposes value-only `ReviewAXStepID`/`ReviewAXResultCategory`
step observations and `ReviewAXSecuritySamples` on the real
`SystemReviewSubmissionAXRuntime`. The test-only oracle in
`FeishuSpeechTests/FinalTextOutputSecurityTests.swift` uses that runtime, not a
preclassified fake or source-string assertion:

- `test_v5SystemAXCancellationAfterMessagingTimeoutStopsBeforeAnyFocusOrReadbackStep`
  cancels at the observed messaging-timeout return and proves no focus setter,
  selected-range setter, readback, or Unicode pair follows;
- `test_v5SystemAXAbsoluteDeadlineAfterMessagingTimeoutStopsBeforeAnyFocusOrReadbackStep`
  lets the absolute deadline expire after the messaging-timeout return and
  proves the same zero-follow-up ledger.

Both new System AX selectors passed:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5SystemAXCancellationAfterMessagingTimeoutStopsBeforeAnyFocusOrReadbackStep \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5SystemAXAbsoluteDeadlineAfterMessagingTimeoutStopsBeforeAnyFocusOrReadbackStep \
  -resultBundlePath /tmp/issue40-v5-r3-system-ax-new-r2.xcresult
```

Result: `2 tests executed, 0 failures`; `** TEST SUCCEEDED **`.
Bundle: `/tmp/issue40-v5-r3-system-ax-new-r2.xcresult`.

The complete v5-r3 focused matrix passed serialized on the repaired
production tree:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r3-final-full \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test \
  -resultBundlePath /tmp/issue40-v5-r3-final-full.xcresult
```

Result: `65 tests executed, 0 failures`; `** TEST SUCCEEDED **`.
Bundle: `/tmp/issue40-v5-r3-final-full.xcresult`; log:
`/tmp/issue40-v5-r3-final-full.log`.
This includes exact/application-bound post-pair drift, security-transition
composites, expired-start executor cleanup, and the two real System AX
checkpoint selectors.

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r3-keyboard \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests test \
  -resultBundlePath /tmp/issue40-v5-r3-keyboard.xcresult
```

Result: `19 tests executed, 0 failures`; `** TEST SUCCEEDED **`.
Bundle: `/tmp/issue40-v5-r3-keyboard.xcresult`; log:
`/tmp/issue40-v5-r3-keyboard.log`.

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r3-readiness \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test \
  -resultBundlePath /tmp/issue40-v5-r3-readiness.xcresult
```

Result: `17 tests executed, 0 failures`; `** TEST SUCCEEDED **`.
Bundle: `/tmp/issue40-v5-r3-readiness.xcresult`; log:
`/tmp/issue40-v5-r3-readiness.log`.

The production-composition coordinator class was rerun after repairing only
its delayed-event test fixture. The initial fixture run exposed a bounded-test
timing defect: the 80ms delayed typed terminal event outlived the old
`Task.yield`-only polling window, with the exact signature
`.preparingSubmission(draft: "PRIVATE_EXPIRED_START_DRAFT_EDITED", feedback: nil)`
instead of `.editable(... feedback: .deliveryFailed)`. The fixture now waits
with a bounded 5ms polling interval and records the real typed terminal event;
the oracle and exact-draft/new-real-Send assertions are unchanged.

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r3-mainvm-final \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test \
  -resultBundlePath /tmp/issue40-v5-r3-mainvm-final.xcresult
```

Result: `34 tests executed, 0 failures`; `** TEST SUCCEEDED **`.
Bundle: `/tmp/issue40-v5-r3-mainvm-final.xcresult`; log:
`/tmp/issue40-v5-r3-mainvm-final.log`.
The isolated repaired selector also passed `1 test, 0 failures` in
`/tmp/issue40-v5-r3-expired-final.xcresult`.

The RED baseline for the R3 acceptance remains
`b321ac5d6c04c91ced9afeb2240f9566d9b8d305`; the earlier pair/security RED
signatures are retained above. The current turn changed tests only in
`FinalTextOutputSecurityTests.swift` and
`ReviewFirstMainViewModelTests.swift` (plus this receipt); no production file
was authored or changed by this test-custody turn. `git diff --check` passed.

## v5-r4 R9/R2 concrete System AX RED (2026-08-24)

The v5-r4 correctness and security reviews identify the remaining exact-focus
readback gap: `validateExactFocusReadback` reaches a later
`AXUIElementSetMessagingTimeout` immediately before the focused-element copy,
but the current call site does not pass the live cancellation probe into that
copy helper. The approved test-only oracle now uses a real materialized
`NSTextView`, the real `SystemReviewSubmissionAXRuntime`, and only its
value-only step observer; it does not use source strings or a preclassified
runtime fake.

Added:

- `test_v5SystemAXExactFocusReadbackCancellationAfterRestorationStopsBeforeCopy`
  restores focus and selection on the real editor, latches cancellation at the
  later readback timeout, and requires zero focused-element copy or any later
  AX/pair/down/up work;
- `test_v5SystemAXCancellationAndDeadlineCoverEveryReachableExactAndApplicationBoundStep`
  first records the concrete System runtime trace for each binding, then runs a
  bounded cancellation and absolute-deadline scenario at every observed
  step/occurrence. The matrix covers every `ReviewAXStepID` actually reachable
  on the exact and application-bound validation paths.

The focused readback RED was run against baseline
`b321ac5d6c04c91ced9afeb2240f9566d9b8d305`:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r4-readback-red3 \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5SystemAXExactFocusReadbackCancellationAfterRestorationStopsBeforeCopy test \
  -resultBundlePath /tmp/issue40-v5-r4-readback-red3.xcresult
```

Result: `1 test executed, 2 failures`; bundle
`/tmp/issue40-v5-r4-readback-red3.xcresult`; log
`/tmp/issue40-v5-r4-readback-red3.log`.

Exact failure signatures:

```text
XCTAssertEqual: observed step count 15 != expected 14 after the readback timeout
XCTAssertFalse failed: the focused-element copy was observed after cancellation
```

The typed result itself was `.cancellation`; the RED is specifically the
unauthorized post-cancellation AX copy, proving this is not a classification or
output-posting false positive.

The all-reachable-step matrix was then run serialized:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r4-step-matrix-red \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5SystemAXCancellationAndDeadlineCoverEveryReachableExactAndApplicationBoundStep test \
  -resultBundlePath /tmp/issue40-v5-r4-step-matrix-red.xcresult
```

Result: `1 test executed, 0 failures`; bundle
`/tmp/issue40-v5-r4-step-matrix-red.xcresult`; log
`/tmp/issue40-v5-r4-step-matrix-red.log`. This green matrix is retained as
coverage evidence; the R4 lane remains RED because the focused readback
selector above catches the current production omission. `swiftc -frontend
-parse FeishuSpeechTests/FinalTextOutputSecurityTests.swift` and `git diff
--check` both passed. Production files remain untouched by this test-custody
delta.

The same RED was exercised through the real `ReviewSubmissionExecutor` using a
test-only delegating adapter whose validation calls remain the concrete System
runtime. This version additionally asserts the typed cancellation receipt and
an empty Unicode backend ledger:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r4-executor-red2 \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5SystemAXExactFocusReadbackCancellationStopsExecutorBeforePairOrPosts test \
  -resultBundlePath /tmp/issue40-v5-r4-executor-red2.xcresult
```

Result: `1 test executed, 1 failure`; bundle
`/tmp/issue40-v5-r4-executor-red2.xcresult`; log
`/tmp/issue40-v5-r4-executor-red2.log`. Exact signature:
`observed step count 15 != expected 14`; the typed terminal receipt was
`.notStarted(.cancellation)` and backend operations were already `[]`, so the
remaining RED is precisely the unauthorized focused-element copy after the
readback timeout.

## v5-r5 R9 fixed-inventory matrix (2026-08-24)

This section supersedes the self-shrinking R4 matrix above. The test-only
matrix now defines a fixed exhaustive inventory of all 15 production
`ReviewAXStepID` cases before creating scenarios. It classifies only
`isAttributeSettable` as capture-only and asserts fixed binding-specific
validation traces. Exact validation uses a real attached editable text view
whose test-only accessibility surface exposes `AXStandard`, and reaches the
complete successful trace, including post-copy, selected-range readback,
`readAXValue`, role/subrole, final captured-PID readback, and the trailing
security composite. Application-bound validation uses a concrete application
root with an ordinary no-value/unsupported focused-element miss and retains
the application PID and trailing security composite. Cancellation and
absolute-deadline scenarios are generated from these fixed expected arrays,
not from a possibly early-terminated baseline.

Baseline: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305` (the production repair
tree was present as the uncommitted implementation under test; no production
file was edited by this test-custody delta).

The fixed-matrix command was run serialized:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r5-step-matrix-d \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5SystemAXCancellationAndDeadlineCoverEveryReachableExactAndApplicationBoundStep test \
  -resultBundlePath /tmp/issue40-v5-r5-step-matrix-d.xcresult
```

Result: `1 test executed, 9 failures`; bundle
`/tmp/issue40-v5-r5-step-matrix-d.xcresult`; log
`/tmp/issue40-v5-r5-step-matrix-d.log`. The exact and application-bound
successful baseline traces and every cancellation scenario passed. The nine
failures are production deadline-classification defects exposed by the new
late-occurrence oracle: deadline injection after exact
`messagingTimeout#5`, `copyAttribute#1`, `messagingTimeout#6`,
`getSelectedRange#1`, `readAXValue#1`, `messagingTimeout#7`, `role#1`,
`messagingTimeout#8`, and `subrole#1` returned
`.securityRejected` instead of the required typed
`.accessibilityTimeout`. The assertions remain intentionally strict; no
deadline failure was accepted as an equivalent security rejection.

The two retained late-readback selectors were rerun after the repair:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r5-readback-exact-e \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5SystemAXExactFocusReadbackCancellationAfterRestorationStopsBeforeCopy \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_v5SystemAXExactFocusReadbackCancellationStopsExecutorBeforePairOrPosts test \
  -resultBundlePath /tmp/issue40-v5-r5-readback-exact-e.xcresult
```

Result: `2 tests executed, 0 failures`; bundle
`/tmp/issue40-v5-r5-readback-exact-e.xcresult`; log
`/tmp/issue40-v5-r5-readback-exact-e.log`.

The complete serialized `FinalTextOutputSecurityTests` target was also run:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r5-final-f \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test \
  -resultBundlePath /tmp/issue40-v5-r5-final-f.xcresult
```

Result: `68 tests executed, 9 failures`; bundle
`/tmp/issue40-v5-r5-final-f.xcresult`; log
`/tmp/issue40-v5-r5-final-f.log`. All failures are the same nine fixed
late-deadline assertions above; the two late-readback selectors and the other
67 security tests passed. `xcrun swiftc -frontend -parse
FeishuSpeechTests/FinalTextOutputSecurityTests.swift` and `git diff --check`
passed.

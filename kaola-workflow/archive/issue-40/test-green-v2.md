# Issue #40 v2 test-author GREEN receipt

Date: 2026-08-23 CST

## Baseline RED evidence

The test oracle was first run against the unchanged implementation baseline
`60090c955fbd57d4b6e875acb8a9bdc42d61f032` (`60090c9`). The bounded serialized
command was:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
```

That run exited `65` after executing 26 tests with 51 failures. The exact
receipt and raw log are retained at:

- `kaola-workflow/issue-40/test-red-v2.md`
- `/tmp/issue40-v2-red-final.log`
- `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_14-34-00-+0800.xcresult`

Representative failure signatures were:

- `ReviewFirstMainViewModelTests.test_reviewFirst_editableReadinessFailureRetainsDraftAndAuthorityWithoutOutput`: `XCTAssertEqual failed: ("idle") is not equal to ("editable(draft: ...")`, with `dismissCallCount == 1` and `copyCalls == 1`.
- `ReviewFirstMainViewModelTests.test_reviewFirst_deliveryFailureReturnsExactDraftToEditableWithoutCopyOrAutomaticRetry`: `idle` instead of the exact editable draft and `copyCalls == 1` instead of `0`.
- `ReviewFirstMainViewModelTests.test_legacyReviewBeforeInsertValuesUseOnePreviewRouteWithoutPreConfirmationOutput`: the `reviewBeforeInsert=false` case stayed `idle`, rendered no read-only preview, and called direct `setSelectedText`.

These failures prove the new tests were RED against `60090c9`, rather than
being authored against an already-passing implementation.

## Test artifacts authored

- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`
  - typed readiness failures retain the exact draft, authority, stable panel,
    callbacks, and no copy/AX/keyboard/direct output;
  - delivery failure and cancellation return the exact draft to editable with
    typed feedback, no automatic copy/retry, and explicit retry/discard only;
  - both legacy `reviewBeforeInsert` values and both `autoInsert` values use
    one read-only preview route with zero pre-confirmation output;
  - multiline preview, capture/recognition/barrier independence, and
    post-freeze permission/Secure Input failure preserve the existing security
    oracles.
- `FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift`
  - uses the canonical `ReviewSurfacePresenting` seam and retains an exact
    draft on application-bound delivery uncertainty without copy or automatic
    dismissal.
- `FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift`
  - exercises the real `ReviewWindowController` with its injected
    `ReadinessEnvironment`: activation rejection, inactive app, non-key panel,
    editor materialization/attachment/first responder, timeout, cancellation,
    retry, same-panel/callback retention, and ready transition.
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`
  - injects canonical review-surface/delivery seams, audits legacy direct-output
    fixtures, rewrites multiline LF cases to read-only preview assertions, and
    retires only obsolete direct-output MainViewModel oracles. Low-level
    `ReviewDestinationDelivery`, pasteboard, final-output security, stale
    callback, exact-once, capture, recognition, and barrier tests remain
    exercised in their dedicated suites and in the retained MainViewModel
    cases.
- `FeishuSpeechTests/TranscriptionReviewViewTests.swift`
  - updates the structural oracle from the obsolete `renderEditable` seam to
    canonical `renderDraft` plus typed `requestEditableReadiness`.

No production, documentation, mission-list, or architecture file was edited
by the test-author work. Production changes visible in the shared worktree are
implementer-owned and were not modified here.

## GREEN commands and evidence

All commands below were serialized with one test worker.

1. `ReviewFirstMainViewModelTests`

   ```text
   xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
     -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test \
     -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
   ```

   Result: `Executed 28 tests, with 0 failures` (`** TEST SUCCEEDED **`).
   Result bundle:
   `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-00-00-+0800.xcresult`

2. `ReviewFirstApplicationFallbackTests`

   ```text
   xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
     -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests test \
     -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
   ```

   Result: `Executed 12 tests, with 0 failures` (`** TEST SUCCEEDED **`).
   Result bundle:
   `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_15-57-00-+0800.xcresult`

3. `ReviewWindowControllerReadinessTests`

   ```text
   xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
     -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test \
     -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
   ```

   Result: `Executed 7 tests, with 0 failures` (`** TEST SUCCEEDED **`).
   Result bundle:
   `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_15-57-15-+0800.xcresult`

4. `StreamingMainViewModelTests`

   ```text
   xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
     -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test \
     -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
   ```

   Result: `Executed 103 tests, with 51 tests skipped and 0 failures`.
   The skips are explicitly named retired direct-output MainViewModel
   expectations; they are not low-level delivery/security tests. The two
   multiline preview/security cases were rewritten and run, not skipped.
   Result bundle:
   `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-01-22-+0800.xcresult`

   The rewritten multiline cases were also run directly:

   ```text
   xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
     -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_multilineLFSnapshotStaysReadOnlyAndNeverReachesAccessibilityOutput \
     -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_multilineLFSnapshotNeverReachesKeyboardAndLaterSafeSnapshotUpdatesReadOnlyPreview \
     test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
   ```

   Result: `Executed 2 tests, with 0 failures`.
   Result bundle:
   `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-01-09-+0800.xcresult`

5. Low-level delivery, pasteboard, final-output security, settings, and review
   view suites were run together serialized:

   ```text
   xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
     -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
     -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests \
     -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
     -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
     -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests \
     -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests \
     test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
   ```

   The first run executed 76 tests; one obsolete structural assertion expected
   `renderEditable`. After updating that test to the canonical `renderDraft` /
   `requestEditableReadiness` contract, the serialized rerun executed 17 view
   tests with 0 failures; the other 59 tests had already passed unchanged.
   Final view result bundle:
   `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-03-47-+0800.xcresult`

Final `git diff --check` passed. A full unfiltered test suite was not run in
this bounded TDD pass; the focused coordinator, real-controller readiness,
fallback, streaming, low-level security/delivery, settings, and review-view
coverage above is the recorded GREEN evidence.

## R1 trust-boundary re-review evidence (2026-08-23 CST)

The R1 production seam now accepts an injected `AccessibilityTrustProviding`.
`ReviewFirstApplicationFallbackTests` uses a deterministic mutable provider,
trusted by default for non-trust tests, and explicitly drives trust revocation
for the new security regressions. This keeps the existing fixed PID/identity,
Secure Input, exact-once, and delivery/security oracles meaningful without
depending on the host's Accessibility permission state.

The focused trust-transition command was serialized:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-r1-trust-derived \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests/test_applicationBoundReviewDelivery_trustRevokedAfterCaptureRejectsBeforeAnyOutput \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests/test_reviewFirst_trustRevokedAfterCaptureRetainsExactDraftAndAuthorityWithoutOutput \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests/test_applicationBoundReviewDelivery_trustRevokedBetweenPreflightCompositeStartAndEndFailsClosed \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests/test_applicationBoundReviewDelivery_trustRevokedDuringPostflightReturnsUncertainAfterOneMutation \
  test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
```

Result: `Executed 4 tests, with 0 failures (0 unexpected)` (`** TEST
SUCCEEDED **`). Result bundle:
`/tmp/issue40-r1-trust-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_16-25-08-+0800.xcresult`.

The affected fallback, low-level delivery, and review-first coordinator
classes were then run together, still with one worker:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-r1-trust-derived-full \
  -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
```

Result: `ReviewDestinationDeliveryTests` 13/0, `ReviewFirstApplicationFallbackTests`
16/0, `ReviewFirstMainViewModelTests` 28/0; aggregate `Executed 57 tests, with
0 failures (0 unexpected)` (`** TEST SUCCEEDED **`). Result bundle:
`/tmp/issue40-r1-trust-derived-full/Logs/Test/Test-FeishuSpeech-2026.08.23_16-25-24-+0800.xcresult`.

The new oracles cover:

- a valid application-current-focus destination captured while trusted, then
  trust revoked before explicit confirm: `.securityRejected`, exact draft and
  authority retained through the coordinator, no activation/retarget/copy,
  no automatic retry, no pasteboard snapshot/read/write, and no Cmd+V or
  keyboard output;
- trust changing between the first preflight composite sample's start/end:
  `.securityRejected` before mutation, with the expected five trust reads and
  no output mutation;
- trust changing during postflight: `.deliveryUncertain` after exactly one
  pasteboard write and one Cmd+V, with no restore, retry, or second output;
- all existing application-bound fallback/delivery tests restored to their
  intended trusted fixture and remaining green.

For the required negative evidence, the first isolated R1 run before fixture
injection was against the worktree at baseline SHA
`60090c955fbd57d4b6e875acb8a9bdc42d61f032` (`60090c9`). It executed 53 tests
with 34 failures. The representative failure was
`test_applicationBoundReviewDelivery_reactivatesExactIdentityAndInsertsFrozenMultilineDraftOnce`:
`XCTAssertEqual failed: ("securityRejected") is not equal to ("inserted")`,
with zero expected security samples and zero output calls. That diagnostic
proved the host Accessibility state was contaminating the existing fixture;
the injected deterministic provider is the test-only repair.

Final `git diff --check` passed after the R1 test edits. No production,
documentation, mission-list, or architecture file was edited by the
test-author.

## R3/R4 correctness re-review evidence (2026-08-23 CST)

R3 now has a running-controller integration test in
`ReviewWindowControllerReadinessTests` that leaves the production
`ReadinessEnvironment.appKit.editorLookup` and `editorAttached` predicates
in place. It renders the real `TranscriptionReviewView` through the production
`ReviewPanel`/`NSHostingView`, finds the SwiftUI-created editable `NSTextView`,
asserts `editor.window === panel`, forces a deterministic first-responder
readiness timeout, then retries and asserts `.ready`, the same panel identity,
and the retained discard callback. The obsolete conditional `renderEditable`
source checks were replaced with unconditional canonical `renderReadOnly` /
`renderDraft` range assertions, so a missing API cannot silently skip coverage.

R4A extends the `.deliveryUncertain` coordinator case: presentation-only
readiness retry retains `.deliveryUncertain` feedback, then the current
accepted draft-change callback updates the exact text and clears feedback to
`nil`, with no second delivery, copy, AX, keyboard, or direct output.

R4B drives `handleMonitoringStateForTesting(.failed(.tapCreationFailed))`
after recognition has produced and edited an editable draft. The test asserts
the exact draft, `.securityRejected`, the same surface identity, no dismiss,
zero delivery/copy/AX/keyboard/direct output, and the expected monitoring
error status.

The new targeted cases were run serialized:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-r3r4-targeted-derived \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests/test_productionEditorMaterializesInRetainedPanelAndSurvivesReadinessRetry \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_nonCancellationDeliveryFailureReturnsFrozenDraftToEditableWithoutRecoveryCopy \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_monitoringFailureAfterRecognitionRetainsExactDraftAndPanelAuthorityWithoutOutput \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_reviewPanel_isOneNSPanelWithSafeReadOnlyAndEditableAuthorityModes \
  test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
```

Result: `Executed 4 tests, with 0 failures (0 unexpected)` (`** TEST
SUCCEEDED **`). Result bundle:
`/tmp/issue40-r3r4-targeted-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_16-33-52-+0800.xcresult`.

The requested controller, coordinator, review-view, and keyboard suites were
then run together serialized:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-r3r4-full-derived \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests \
  test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
```

Result: `ReviewFirstMainViewModelTests` 29/0,
`ReviewWindowControllerReadinessTests` 8/0,
`TranscriptionReviewViewKeyboardTests` 13/0,
`TranscriptionReviewViewTests` 4/0; aggregate `Executed 54 tests, with 0
failures (0 unexpected)` (`** TEST SUCCEEDED **`). Result bundle:
`/tmp/issue40-r3r4-full-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_16-34-05-+0800.xcresult`.

The first targeted build attempt exposed only a test import error,
`cannot find type 'NSHostingView' in scope`; importing SwiftUI in the test
file fixed it before the successful rerun. Existing unrelated Swift 6
concurrency/AppKit warnings remain advisory and were not changed.

Final `git diff --check` passed. Changes remain test-only plus this receipt;
no production, documentation, mission-list, or architecture file was edited.

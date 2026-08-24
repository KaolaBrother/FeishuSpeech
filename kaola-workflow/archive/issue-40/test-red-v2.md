# Issue #40 v2 test-author RED receipt

Date: 2026-08-23 CST

Baseline under test: `60090c955fbd57d4b6e875acb8a9bdc42d61f032` (`60090c9`), the current
`workflow/issue-40` HEAD before the v2 implementation.

Test command (serialized and bounded to the focused review coordinator suite):

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
```

Result: exit `65`; the suite compiled and launched, then executed 26 tests with 51 failures.
The final bounded RED run's Xcode result bundle is:

`/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_14-34-00-+0800.xcresult`

The raw final bounded run was captured at `/tmp/issue40-v2-red-final.log`.

## Failure signatures proving RED

- `ReviewFirstMainViewModelTests.test_reviewFirst_editableReadinessFailureRetainsDraftAndAuthorityWithoutOutput`
  fails with `XCTAssertEqual failed: ("idle") is not equal to ("editable(draft: ...")`.
  The same test observes `dismissCallCount == 1` and `copyCalls == 1`, and the draft-change
  callback cannot update `reviewDraftText`; the new oracle also requires one stable panel
  identity. This is the obsolete readiness-failure
  `copy/dismiss/revoke` path.
- `ReviewFirstMainViewModelTests.test_reviewFirst_deliveryFailureReturnsExactDraftToEditableWithoutCopyOrAutomaticRetry`
  fails with `XCTAssertEqual failed: ("idle") is not equal to ("editable(draft: ...")`, an
  empty `reviewDraftText` instead of the exact edited draft, and `copyCalls == 1` instead of 0.
- `ReviewFirstMainViewModelTests.test_reviewFirst_nonCancellationDeliveryFailureReturnsFrozenDraftToEditableWithoutRecoveryCopy`
  fails with `copyCalls == 1` instead of 0 and `idle` instead of the exact editable draft for
  every non-cancellation delivery result.
- `ReviewFirstMainViewModelTests.test_reviewFirst_deliveryFailureDraftCanBeDiscardedWithoutCopyOrSecondDelivery`
  reports `XCTFail: delivery failure must preserve an editable draft before discard`.
- `ReviewFirstMainViewModelTests.test_legacyReviewBeforeInsertValuesUseOnePreviewRouteWithoutPreConfirmationOutput`
  fails for `reviewBeforeInsert=false` with `idle` instead of `streaming(preview: "")`, zero
  read-only preview renders, and a direct `setSelectedText` call after the first packet.

The existing capture/recognition/barrier tests remain in the focused suite, including
`test_reviewFirst_journalAndActionTwoProgressWhileReviewSurfaceIsGated` and
`test_reviewFirst_releaseWaitsForRecorderBarrierBeforeEditableUIAndKeepsConsumerSeparate`.

## Test artifacts authored

- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`
  - replaces readiness-failure copy/dismiss expectations with durable-draft/authority assertions
    across activation, key-window, editor-materialization, first-responder, cancellation, and
    timeout failure seams;
  - replaces delivery-failure copy/dismiss expectations with exact-draft editable, explicit
    retry/discard, zero-copy, zero-target-mutation, and no-automatic-retry assertions;
  - replaces the legacy compatibility-mode direct-output test with a two-value
    `reviewBeforeInsert` preview/no-pre-confirmation-output oracle;
  - keeps the test-only presenter readiness seam and the existing exact/application-bound,
    multiline/keyboard, stale-callback, and async capture/recognition/barrier oracles intact.

`git diff --check` passed, and the worktree diff contains only the test path above. No production
file was edited.

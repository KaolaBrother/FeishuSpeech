# Issue #40 RED evidence

## Assigned scope

Test custody only for Issue #40. The acceptance surface is the review-first
non-secure strict-AX-miss fallback: bind the complete original application
identity before the panel/audio/provider starts; preserve the exact AX route
when available; reject Secure Input and incomplete or drifting identities;
deliver a frozen multiline draft once through the exact application using two
secure/PID/identity samples and a captured-PID Cmd+V; keep preview, capture,
recognition retry/replay, and the Return/Shift+Return editor contract
independent; and copy once for current non-cancellation failures.

No production or product documentation files were changed.

## Tests authored or updated

- `FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift`
  - Added typed exact-vs-application-current-focus capture coverage, identity-first
    ordering/revalidation, incomplete and drifting identity rejection, fixed-PID
    multiline delivery, secure/PID/identity fail-closed behavior, activation and
    post uncertainty, preview/retry independence while the presentation lane is
    gated, and one-copy manual recovery.
- `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift`
  - Updated existing review fixtures to typed capture outcomes and asserted exact
    binding preference plus secure/non-secure AX classification.
- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`
  - Updated the review delivery fixture to generation-aware typed capture and added
    secure startup rejection before surface/audio/provider/journal work.
- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
  - Added review-only current-focus multiline safety, fixed-PID Cmd+V, typed
    preflight rejection, and postflight identity uncertainty coverage while keeping
    compatibility Unicode tests unchanged.
- `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift`
  - Added fallback-route snapshot/restore and no-restore-after-uncertainty tests.

## Baseline

- Actual baseline commit run: `98e1eb53b6aaee369f6481303a289ca60b843262`
  (`chore: archive issue-39 [sink]`).
- The production tree was unchanged at the time of the RED run. The typed
  declarations and review-only insertion primitive are the implementation work
  that these tests are intended to falsify.

## RED command and result

Command:

```bash
xcodebuild -scheme FeishuSpeech \
  -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests test
```

Failure signature on the baseline:

```text
ReviewPasteboardLifecycleTests.swift:95:29: error: value of type 'SystemFinalTextOutput' has no member 'insertReviewAtCurrentFocusOnce'
ReviewPasteboardLifecycleTests.swift:125:29: error: value of type 'SystemFinalTextOutput' has no member 'insertReviewAtCurrentFocusOnce'
Testing cancelled because the build failed.
** TEST FAILED **
```

The failing test names are
`ReviewPasteboardLifecycleTests.test_successfulApplicationBoundReviewPasteUsesSameSnapshotAndRestoresMultilineDraft`
and
`ReviewPasteboardLifecycleTests.test_applicationBoundReviewPastePostflightUncertaintyDoesNotRestoreOrRetry`;
both fail to compile on the baseline because the required production primitive
does not exist. This is the expected RED boundary before implementation. The
build is cancelled before test execution; the remaining typed capture/delivery
assertions will become executable once the shared production declarations land.

The complete serialized output is recorded at
`/tmp/feishuspeech-issue40-red-final-v3.log`.

The xcodebuild result bundle is:
`/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_11-10-56-+0800.xcresult`.

## Additional checks

- `git diff --check` — passed.
- Production source and product documentation paths remain unchanged.
- A green suite is intentionally not reported: production implementation and
  the subsequent GREEN run belong to the implementing role.

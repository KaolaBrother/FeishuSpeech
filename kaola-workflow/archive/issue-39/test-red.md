# Issue #39 RED evidence

## Assigned scope

Test custody only for Issue #39. The acceptance surface is the editable review
keyboard contract: bare Return confirms the current non-whitespace draft exactly
once; Shift+Return inserts LF without confirming; Command+Return confirms; Escape,
Cancel, and window close discard; streaming and sealing remain read-only and expose
neither edit nor confirm authority. Existing Issue #38 destination, clipboard, and
independent capture/recognition/review-axis tests remain in place.

No production or product documentation files were changed.

## Tests authored

- `FeishuSpeechTests/TranscriptionReviewViewTests.swift`
  - Updated the old Issue #38 shortcut expectation so bare Return is no longer
    asserted to remain ordinary editing.
  - Added real `NSHostingView`/`NSTextView` event tests for bare Return,
    Shift+Return, Command+Return, and Escape.
- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`
  - Added exact untrimmed current-draft delivery coverage with repeated confirm
    attempts; the destination must receive the draft once and without trimming.
  - Strengthened the existing read-only streaming/sealing test to invoke both
    draft-change and confirm callbacks before action 2 and assert no edit/output.

## Baseline

- Actual baseline commit run: `286c6d956d3966a31d38b53133caf4568923b632`
  (`chore: archive issue-38 [sink]`).
- The brief names `a5840ab63d92d54a2b996230b81666d7107e0530` as the Issue #39
  baseline parent. The worktree HEAD used for the recorded run is the archive
  commit above; `git diff a5840ab..286c6d9 --name-status` contains only archived
  Issue #38 workflow records and no production or test-tree changes. The SHA
  recorded here is the commit actually executed.

## RED command and result

Command:

```bash
xcodebuild -scheme FeishuSpeech \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test \
  2>&1 | tee /tmp/feishuspeech-issue39-red-final.log
```

Failure signature on the baseline:

```text
Test Case '-[FeishuSpeechTests.TranscriptionReviewViewKeyboardTests test_editableReview_bareReturnConfirmsCurrentDraftExactlyOnce]' failed
XCTAssertEqual failed: ("[]") is not equal to ("[\"  draft with spaces  \"]") - bare Return must confirm the current untrimmed draft exactly once
Test Suite 'FeishuSpeechTests.xctest' failed
    Executed 30 tests, with 1 failure
** TEST FAILED **
```

The full run is recorded at `/tmp/feishuspeech-issue39-red-final.log`.

The baseline focused suites before adding the Issue #39 tests were green:
`ReviewFirstMainViewModelTests` 21/21 and `TranscriptionReviewViewTests` 4/4,
recorded at `/tmp/feishuspeech-issue39-baseline-existing.log`. The new RED is
therefore attributable to the missing bare-Return behavior, not a pre-existing
failure or a test build/fixture failure.

## Additional checks

- `git diff --check` — passed.
- `swiftlint lint --quiet` — passed.
- Changed paths are limited to the two test files above and this workflow receipt.

# Issue #40 v4 R4 TEST-ONLY GREEN

- Date: 2026-08-23 (Asia/Shanghai)
- Baseline actually executed: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`
- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Test custody: this final reconciliation changed only
  `FeishuSpeechTests/StreamingMainViewModelTests.swift`; production and
  workflow/docs files were not authored by this test lane.

## RED to GREEN

The baseline RED is recorded in
`kaola-workflow/issue-40/test-red-v4-r4.md` against
`4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`:

- `test_postReleaseDrainExpiryNeverAuthorizesPartialBeforeAction2ThroughEitherUISeam`
  observed ordinary `.editable` authority, a materialized Send path, one
  delivery, and the retained partial delivered before action 2 settled.
- `test_postReleaseDrainExpiryRetainsMultilineLFAsInertReadOnlyData` observed
  the LF-containing partial converted into the terminal streaming failure.
- RED result: `Executed 2 tests, with 6 failures (0 unexpected)`;
  xcresult was `/tmp/issue40-v4-r4-red-final/Logs/Test/Test-FeishuSpeech-2026.08.23_23-38-14-+0800.xcresult`.

After the R4 repair receipt in
`kaola-workflow/issue-40/.cache/implementation-v4-r4.md`, the contradictory
legacy `keyboard\nline` branch in
`test_postReleaseDrainExpiryReportsFixedFailureWhenNoSafeOutputWasCommitted`
was migrated while preserving the empty-snapshot terminal-error oracle. The
LF branch now asserts exact durable recovery text, non-authoritative/non-
editable state, inert real Send and qualified Return seams, no delivery or
output ledger activity, and unchanged text after late completion.

## Serialized verification

All commands used `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1`.

### R4 selectors

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-r4-final-r4 \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryReportsFixedFailureWhenNoSafeOutputWasCommitted \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryNeverAuthorizesPartialBeforeAction2ThroughEitherUISeam \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryRetainsMultilineLFAsInertReadOnlyData test
```

- exit: `0`
- result: `3 passed, 0 failed, 0 skipped`
- xcresult: `/tmp/issue40-v4-r4-final-r4/Logs/Test/Test-FeishuSpeech-2026.08.23_23-55-10-+0800.xcresult`

### Full StreamingMainViewModelTests class

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-r4-streaming-final \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test
```

- exit: `0`
- result: `105 passed, 0 failed, 0 skipped`
- xcresult: `/tmp/issue40-v4-r4-streaming-final/Logs/Test/Test-FeishuSpeech-2026.08.23_23-55-23-+0800.xcresult`
- source accounting: `105` `test_` methods; no `XCTSkip`,
  `retiredCompatibilityOutputTests`, or `setUpWithError` blanket skip marker
  remains in this class.

### Complete v4 focused matrix

Selectors: `FinalTextOutputSecurityTests`, `CurrentFocusAppendSessionTests`,
`ReviewDestinationDeliveryTests`, `ReviewPasteboardLifecycleTests`,
`ReviewFirstApplicationFallbackTests`, `ReviewFirstMainViewModelTests`,
`ReviewWindowControllerReadinessTests`, `TranscriptionReviewViewTests`, and
`StreamingMainViewModelTests`.

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-focused-r4-final \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests \
  -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
  -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test
```

- exit: `0`
- result: `265 passed, 0 failed, 0 skipped`
- xcresult: `/tmp/issue40-v4-focused-r4-final/Logs/Test/Test-FeishuSpeech-2026.08.23_23-55-49-+0800.xcresult`

### Full serialized macOS target

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-full-r4-final \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
```

- exit: `0`
- result: `484 executed; 483 passed, 0 failed, 1 skipped`
- xcresult: `/tmp/issue40-v4-full-r4-final/Logs/Test/Test-FeishuSpeech-2026.08.23_23-56-14-+0800.xcresult`
- only skip: `DirectFeishuKeepAliveSessionTests.test_liveKeepAliveTCPIsNotOnVPNTunnelAddress()`;
  Xcode result metadata marks this single live-network environment test
  `Skipped`. No Issue #40 test was skipped.

## Final integrity checks

```text
git diff --check
exit 0

rg -n '^    func test_' FeishuSpeechTests/StreamingMainViewModelTests.swift | wc -l
105

rg -n 'XCTSkip|retiredCompatibilityOutputTests|setUpWithError' FeishuSpeechTests/StreamingMainViewModelTests.swift
no matches
```

The final R4 oracle therefore preserves exact multiline LF data on the
non-authoritative recovery surface, denies ordinary confirmation authority,
keeps both real UI seams inert, suppresses late completion, and proves zero
delivery/AX/Unicode/keyboard/pasteboard/copy/append/retry/retarget effects.

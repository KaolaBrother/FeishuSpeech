# Issue #40 v4 final GREEN receipt

Date: 2026-08-23 (Asia/Shanghai)

Baseline: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a` (`git rev-parse HEAD`).

The v4 R1 and drain-expiry production repairs were present before this final
verification. This lane remained test-only. Test files touched by this lane:

- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
- `FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`

No production, architecture, mission-list, or other workflow file was edited
by this verification lane.

## RED to GREEN closure

- R1 RED receipt: 20 failures in 32 `FinalTextOutputSecurityTests`; modifier
  transitions returned `deliveryUncertain` and posted one Unicode pair instead
  of failing before submission with zero posts.
- R1 GREEN: the same executable exact/application Command/Shift/Control/
  Option/Fn matrix now passes 32/32.
- R3 source-string checks were replaced with executable phase/PID and
  cancellation hook tests; both pass in the 32-test suite.
- R2 no-skip baseline: 103 tests executed with 173 obsolete direct-output
  failures. After migration and production repair, all 103 execute and pass.
- Drain RED: `test_postReleaseDrainExpiryMapsUncertainKeyboardDeliveryToProvisionalPreserved`
  failed at line 1953. After the drain repair, it passes in the full Streaming
  class.

## Exact verification commands and result bundles

### R1/R3 FinalText security suite

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-r1-r3-finaltext -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test 2>&1 | tee /tmp/issue40-v4-r1-r3-finaltext.log
```

Result: exit 0, 32 tests, 0 failures.

Result bundle: `/tmp/issue40-v4-r1-r3-finaltext/Logs/Test/Test-FeishuSpeech-2026.08.23_23-13-19-+0800.xcresult`

### All StreamingMainViewModelTests

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-drain-streaming-final -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test 2>&1 | tee /tmp/issue40-v4-drain-streaming-final.log
```

Result: exit 0, 103 tests, 0 failures, 0 skipped.

Result bundle: `/tmp/issue40-v4-drain-streaming-final/Logs/Test/Test-FeishuSpeech-2026.08.23_23-13-30-+0800.xcresult`

### Full v4 focused matrix

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-focused-final2 -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test 2>&1 | tee /tmp/issue40-v4-focused-final2.log
```

Result: exit 0, 263 tests, 0 failures, 0 skipped.

Suite accounting:

```text
CurrentFocusAppendSessionTests       38 passed
FinalTextOutputSecurityTests        32 passed
ReviewDestinationDeliveryTests      13 passed
ReviewFirstApplicationFallbackTests 16 passed
ReviewFirstMainViewModelTests       31 passed
ReviewPasteboardLifecycleTests       7 passed
ReviewWindowControllerReadinessTests 11 passed
StreamingMainViewModelTests        103 passed
TranscriptionReviewViewTests         12 passed
                                     263 passed
```

Result bundle: `/tmp/issue40-v4-focused-final2/Logs/Test/Test-FeishuSpeech-2026.08.23_23-15-19-+0800.xcresult`

### Full serialized macOS test target

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-full-final -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test 2>&1 | tee /tmp/issue40-v4-full-final.log
```

Result: exit 0, 482 tests, 0 failures, 1 skipped.

The only skip is unrelated/environmental and explicitly expected by the test:

```text
DirectFeishuKeepAliveSessionTests.test_liveKeepAliveTCPIsNotOnVPNTunnelAddress
Test skipped - live TCP previously hung the XCTest host; issue #34 forbids additional live sockets
```

No v4-focused suite skipped a test. The Streaming class contains 103 test
methods, has no `retiredCompatibilityOutputTests`, `XCTSkip`, or
`setUpWithError` blanket skip, and its 51 formerly skipped compatibility
methods are included in the 103 executed tests.

Result bundle: `/tmp/issue40-v4-full-final/Logs/Test/Test-FeishuSpeech-2026.08.23_23-15-46-+0800.xcresult`

## Final static check

```text
git diff --check
```

Result: exit 0.

Final verification verdict: GREEN. The only non-executed test is the
pre-existing live-TCP environmental guard; there are no product failures in
the focused or full serialized target.

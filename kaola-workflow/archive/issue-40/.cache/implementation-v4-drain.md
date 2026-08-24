# Issue #40 v4 drain-expiry repair receipt

Date: 2026-08-23 (Asia/Shanghai)

## Scope and diagnosis

Production-only repair in `FeishuSpeech/ViewModels/MainViewModel.swift`; tests,
output/security services, documentation, workflow files, and protected capture/
recognition files were not edited by this lane.

The v4 RED receipt (`test-red-v4-r1-r3.md`) recorded one remaining failure:
`StreamingMainViewModelTests.test_postReleaseDrainExpiryMapsUncertainKeyboardDeliveryToProvisionalPreserved`
at `StreamingMainViewModelTests.swift:1953`. After the recorder barrier and
post-release drain deadline, the durable read-only preview was being discarded
and the `.none` preservation branch published `流式识别失败`, even though the
review authority still owned a safe, nonterminal preview. The pre-repair full
streaming run also exposed the existing negative oracle for the unsafe
`keyboard\nline` snapshot.

## Repair

`expirePostReleaseDrain` now snapshots the latest preview before interaction
cleanup, fences review-transition callbacks, and retains the same review
authority when the snapshot is nonempty, same-generation, bounded to 16,384
UTF-16 units, and eligible for provisional review. The helper republishes that
exact text as `.editable(isPossiblyIncomplete: true)`, reuses the existing
panel, and starts only advisory presentation-focus telemetry. It performs no
append, AX, Unicode/keyboard, pasteboard, copy, retry, retarget, or completion
feedback. Empty, unsafe (including LF control text), or oversized snapshots
continue through the fixed failure/preservation branches.

The recorder barrier, independent capture-drain and recognition-consumer task
roots, terminal admission fencing, and late-completion suppression remain
unchanged.

## Verification

Before repair (RED evidence, from `test-red-v4-r1-r3.md`):

```text
StreamingMainViewModelTests.test_postReleaseDrainExpiryMapsUncertainKeyboardDeliveryToProvisionalPreserved
— XCTAssertFalse failed at StreamingMainViewModelTests.swift:1953
```

After repair:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-drain-rejected2 \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryReportsFixedFailureWhenNoSafeOutputWasCommitted test
exit 0 — 1 test, 0 failures

The original RED oracle was rerun directly after the final repair:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-drain-exact-final \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryMapsUncertainKeyboardDeliveryToProvisionalPreserved test
exit 0 — 1 test, 0 failures
```

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-drain-streaming2 \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test
exit 0 — 103 tests, 0 failures, 0 skipped

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-drain-review \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test
exit 0 — 54 tests, 0 failures, 0 skipped

xcodebuild -scheme FeishuSpeech -configuration Debug \
  -derivedDataPath /tmp/issue40-v4-drain-build build
exit 0 — BUILD SUCCEEDED

swiftlint lint --strict --config .swiftlint.yml
exit 0 — 0 violations, 0 serious

git diff --check
exit 0

git diff --exit-code 4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a -- \
  FeishuSpeech/Services/AudioRecorder.swift \
  FeishuSpeech/Services/ByteBoundedAudioIngress.swift \
  FeishuSpeech/Services/HoldPacketJournal.swift \
  FeishuSpeech/Services/FeishuStreamingSession.swift \
  FeishuSpeech/Models/StreamingSpeechModels.swift \
  FeishuSpeech/Models/StreamingSpeechProvider.swift \
  FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift \
  FeishuSpeech/Services/BoundTLSSocket.swift \
  FeishuSpeech/Services/TransportAttemptContext.swift
exit 0 — no protected async-path differences
```

Verification tier: **tests-green** for the affected streaming class and focused
review suites, with build/lint/topology/diff checks green.

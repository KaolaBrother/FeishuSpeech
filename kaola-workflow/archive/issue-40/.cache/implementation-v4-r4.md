# Issue #40 v4 R4 repair receipt

Date: 2026-08-23 (Asia/Shanghai)

## Scope and baseline

Production-only changes were limited to:

- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeech/Models/TranscriptionReviewState.swift` (added the read-only `ReviewReadOnlyPhase.recovery` marker; kept the product state enum compatible)
- `FeishuSpeech/Views/TranscriptionReviewView.swift`
- `FeishuSpeech/Controllers/ReviewWindowController.swift`

Tests, output/security services, workflow/docs, and protected capture,
recognition, transport, retry, replay, journal, and audio files were not edited.

The R4 RED receipt (`test-red-v4-r4.md`) recorded 2 tests with 6 failures. The
blocking defect was that drain expiry installed ordinary `.editable` callbacks,
allowing real Send/Return UI seams to reach delivery before action 2 settled.
The same branch also rejected LF even though LF is inert review data.

## Repair

Drain expiry now uses the existing panel's new `.recovery` read-only phase:

- latest nonempty, review-safe, <=16,384 UTF-16 partial is retained exactly,
  including LF;
- the current `ReviewSurfaceAuthority` is cleared before rendering, so the
  retained surface is explicitly non-authoritative;
- the state remains non-editable/sealing while the panel displays
  `识别未完成；仅供查看` and `识别结果尚未确认`;
- the presenter clears draft, confirm, and discard callbacks and disables key
  interaction; no Send button or qualified Return editor is materialized;
- no delivery, AX, Unicode/keyboard, pasteboard/copy, retry, retarget, or
  session recreation is introduced;
- empty, unsafe, or over-cap previews remain fail-closed through the existing
  terminal/preservation branches.

The recorder barrier, independent capture-drain and recognition-consumer roots,
terminal admission, identity invalidation, and late callback suppression remain
unchanged.

## Verification

The exact R4 selector passes:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-r4-repair3 \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryNeverAuthorizesPartialBeforeAction2ThroughEitherUISeam \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryRetainsMultilineLFAsInertReadOnlyData test
exit 0 — 2 tests, 0 failures
```

Focused review/view/controller suites pass:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-r4-review \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test
exit 0 — 54 tests, 0 failures
```

Debug build and quality checks pass:

```text
xcodebuild -scheme FeishuSpeech -configuration Debug \
  -derivedDataPath /tmp/issue40-v4-r4-build build
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

Source guard check:

```text
rg -n 'reviewDestinationDelivery\.deliver' FeishuSpeech/ViewModels/MainViewModel.swift | wc -l
1
```

The recovery branch contains no `renderDraft` or confirmation callback and
clears `reviewSurfaceAuthority` before rendering `ReviewReadOnlyPhase.recovery`.

The serialized Streaming class was rerun twice. The second run executed 105
tests with 1 failure, solely the pre-existing
`test_postReleaseDrainExpiryReportsFixedFailureWhenNoSafeOutputWasCommitted`
oracle at line 1891, which still demands `流式识别失败` for the single-LF
`keyboard\nline` preview. That expectation conflicts with the R4 oracle and
architecture requirement that LF remain inert read-only data. The R4 selector
and multiline oracle pass in isolation; no production special case was added
to satisfy the stale negative assertion, and the test was not edited.

All other Streaming tests were then run with only that contradictory legacy
oracle excluded:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-r4-streaming-sans-stale-lf \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests \
  -skip-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryReportsFixedFailureWhenNoSafeOutputWasCommitted test
exit 0 — 104 tests, 0 failures
```

Verification tier: **tests-green** for the R4 selector and focused review
suites; full Streaming remains blocked only by the contradictory stale LF
oracle described above.

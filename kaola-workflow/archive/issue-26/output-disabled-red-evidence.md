# Issue #26 R1 — output-disabled RED evidence

## Assigned acceptance surface

With `autoInsert == false`:

1. A usable response received while Fn is held, followed by normal release and a nonempty action-2 final, completes without insertion, rewrite, copy, empty-result feedback, provisional/manual-recovery feedback, or error feedback.
2. A usable response received while Fn is held, followed by a recoverable failure and release during retry backoff, completes normally without a successor stream, stream error, output, copy, or late mutation.

## Baseline actually exercised

- Commit SHA: `7396a7cbdaf37058ca2a9b2df89923525d2ce7c8`
- The issue worktree already contained the current uncommitted review implementation in `FeishuSpeech/ViewModels/MainViewModel.swift`; its exercised file SHA-256 was `310d641357a9e92b5264c92f5b821560b3bb9dd1265f883eb762f1d42b606972`.
- No production file was written by the test-author run.

## Tests authored

Test path: `FeishuSpeechTests/StreamingMainViewModelTests.swift`

- `test_autoInsertFalseUsableHeldResponseThenNonemptyActionTwoCompletesWithoutOutputOrFeedback`
  - Pins one provider/session, one held send, one action-2 `finish`, zero cancel, and one recorder start/stop.
  - Pins zero captured-target rewrite, current-focus output, synthetic insertion, copy, late mutation, completion feedback, overlay message, and error/manual-recovery/provisional/empty-result states.
- `test_autoInsertFalseUsableHeldResponseThenRecoverableFailureReleasedDuringBackoffCompletesNormally`
  - Pins one provider/session, two sends, zero `finish`, one cancel, exactly one 250 ms retry delay, no successor send, and one recorder start/stop.
  - Pins idle completion with no stream error, output, copy, completion feedback, overlay message, or late mutation.

The retry test helper gained an `autoInsert` argument defaulting to `true`, so existing tests retain their prior setup while this focused scenario selects `false`.

## Commands run

Build only; the app was not launched:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' build-for-testing
```

Result: `** TEST BUILD SUCCEEDED **`. One pre-existing Swift 6 warning was reported in `FeishuAPIServiceTests.swift:271`; it is outside this change.

Direct XCTest bundle invocation, limited to the two new tests:

```text
env LLVM_PROFILE_FILE=/tmp/feishuspeech-output-disabled-%p.profraw DYLD_LIBRARY_PATH=/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS /Applications/Xcode.app/Contents/Developer/usr/bin/xctest -XCTest 'StreamingMainViewModelTests/test_autoInsertFalseUsableHeldResponseThenNonemptyActionTwoCompletesWithoutOutputOrFeedback,StreamingMainViewModelTests/test_autoInsertFalseUsableHeldResponseThenRecoverableFailureReleasedDuringBackoffCompletesNormally' /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: exit code `1`; 2 tests executed, 6 assertion failures, 0 unexpected failures. The command did not launch the app or exercise Fn, microphone, credentials, or permissions.

Focused lint and whitespace validation:

```text
swiftlint lint FeishuSpeechTests/StreamingMainViewModelTests.swift
git diff --check
```

Result: no serious lint violations and no whitespace errors. SwiftLint reported three pre-existing warnings elsewhere in the same large test file: two `closure_parameter_position` warnings and one long `type_name` warning.

## RED failure signatures

### Normal action-2 final incorrectly treated as empty output

Test:

`test_autoInsertFalseUsableHeldResponseThenNonemptyActionTwoCompletesWithoutOutputOrFeedback`

Failures:

```text
StreamingMainViewModelTests.swift:501: XCTAssertEqual failed: ("[FeishuSpeech.RecordingState.emptyFinalPreservedPartial]") is not equal to ("[]")
StreamingMainViewModelTests.swift:502: XCTAssertNil failed: "emptyFinalPreservedPartial"
StreamingMainViewModelTests.swift:503: XCTAssertNil failed: "未返回可用最终文本"
StreamingMainViewModelTests.swift:505: XCTAssertFalse failed
```

Interpretation: the nonempty action-2 result completed the transport lifecycle and produced no insertion/rewrite/copy, but production incorrectly published empty-final feedback and its overlay message/state.

### Release during recoverable retry incorrectly treated as stream failure

Test:

`test_autoInsertFalseUsableHeldResponseThenRecoverableFailureReleasedDuringBackoffCompletesNormally`

Failures:

```text
StreamingMainViewModelTests.swift:1094: XCTAssertEqual failed: ("error("流式识别失败")") is not equal to ("idle")
StreamingMainViewModelTests.swift:1095: XCTAssertFalse failed
```

Interpretation: retry admission, cancellation, recorder shutdown, successor suppression, zero-output behavior, and late-event invalidation all held, but production incorrectly terminated in the visible stream-error state instead of normal idle completion.

## Verdict

RED as required. The two focused tests falsify R1 on the current review implementation while the exact lifecycle, retry, zero-output, and late-mutation assertions remain satisfied.

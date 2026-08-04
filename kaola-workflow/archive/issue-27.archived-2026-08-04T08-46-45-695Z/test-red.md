# Issue #27 release-drain RED receipt

Date: 2026-08-04

## Assignment

Author regression tests, without production changes, for the revised UAT contract:

- Fn release closes capture but continues draining captured audio and admitting its packet/tail responses.
- The action-2 terminal result is authoritative and replaces the held snapshot exactly once on supported AX and keyboard-replacement routes.
- Release during recoverable retry retains authority to replay the captured journal and finish recognition.
- Repeated backend code 10024 remains recoverable; a successful packet resets the retry/backoff streak and later output resumes.
- Callbacks after terminal cleanup and callbacks from an old generation remain suppressed.

## Test artifact

- `FeishuSpeechTests/StreamingMainViewModelTests.swift`
- Test-only commit: `e8d859aedb5b4b6030cabacaca2daaffc527675b`
- Production files changed: none

## Baseline and RED proof

- Baseline commit exercised: `26825b829cd654f46a445b0505d82b165dc27e40`
- Branch: `workflow/issue-27`
- The focused test target compiled against the baseline production code.

Failure signatures:

1. `test_releaseDrainsInFlightPacketThenAppliesAuthoritativeFinalOnAXRoute`
   - Expected three AX ownership updates: held, post-release in-flight tail, authoritative terminal.
   - Actual: one held update. The post-release tail and terminal were suppressed.
2. `test_releaseFinalizesKeyboardReplacementWithAuthoritativeActionTwoTextExactlyOnce`
   - Expected one finalization carrying a non-nil authoritative terminal value.
   - Actual: one finalization carrying `nil`.
3. `test_releaseDuringRecoverableBackoffReplaysCapturedPacketAndFinishesSuccessor`
   - Expected provider creation count `2` and one captured-journal replay on the successor.
   - Actual provider creation count `1`; the successor was never admitted after release.
4. `test_successfulPacketAfterRepeatedBackend10024ResetsRetryBackoffStreak`
   - Expected retry delays `[250000000, 500000000, 250000000]` nanoseconds.
   - Actual retry delays `[250000000, 500000000, 1000000000]`; a successful packet did not reset the streak.

The AX lifecycle test also injects both a same-generation callback after terminal cleanup and an older-generation callback, then requires the committed output history to remain unchanged. This preserves the existing stale-generation security boundary while changing only the release-drain boundary.

## Commands run

Focused build and normal test-run attempt:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-release-drain-red -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_releaseDrainsInFlightPacketThenAppliesAuthoritativeFinalOnAXRoute -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_releaseFinalizesKeyboardReplacementWithAuthoritativeActionTwoTextExactlyOnce -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_releaseDuringRecoverableBackoffReplaysCapturedPacketAndFinishesSuccessor -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_successfulPacketAfterRepeatedBackend10024ResetsRetryBackoffStreak test
```

- Compile/link/sign completed.
- Xcode then remained at `waiting for workers to materialize`; it was interrupted after 151.535 seconds with exit 75.
- Result bundle: `/tmp/feishuspeech-issue27-release-drain-red/Logs/Test/Test-FeishuSpeech-2026.08.04_15-17-52-+0800.xcresult`

The already-built subject bundle was then run directly, one focused test at a time:

```text
mkdir -p /tmp/feishuspeech-issue27-release-drain-red/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/Frameworks
cp /tmp/feishuspeech-issue27-release-drain-red/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/FeishuSpeech.debug.dylib /tmp/feishuspeech-issue27-release-drain-red/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/Frameworks/
xcrun xctest -XCTest FeishuSpeechTests.StreamingMainViewModelTests/<focused-test-name> /tmp/feishuspeech-issue27-release-drain-red/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

- Each of the four focused tests executed the real `MainViewModel` subject and failed on its acceptance assertion.
- Each direct invocation exited `1` with an XCTest assertion failure; there were no unexpected errors.
- The copied dylib exists only inside the disposable `/tmp` build product and does not modify the repository or installed Release.

Additional checks:

```text
git diff --check
swiftlint lint --strict FeishuSpeechTests/StreamingMainViewModelTests.swift
```

- `git diff --check`: clean.
- SwiftLint reported three pre-existing violations outside the added test block (two closure-parameter-position findings and one overlong existing type name). No finding points into the new tests.

## Outcome

RED confirmed on baseline `26825b829cd654f46a445b0505d82b165dc27e40`. The implementation role now has a test-owned oracle for release drain, authoritative terminal replacement, release-time recoverable replay, retry-streak reset, resumed output, and post-cleanup stale suppression.

# Issue #27 terminal-reconciliation and drain-watchdog RED receipt

Date: 2026-08-04

## Assignment

Extend test custody for the release-drain blueprint without modifying production:

- A differing action-2 final must reconcile the fixed-PID keyboard owner with exact Swift-`Character` Backspaces plus replacement suffix while Secure Input, activation, and physical-interference monitoring remain armed.
- An equal action-2 final must close the owner without duplicate synthetic events.
- A hanging coordinator operation must leave the silent-active state through typed timeout/retry under a short injected drain policy.
- Post-release drain expiry must preserve already emitted text, publish a non-success terminal outcome, and suppress a late noncooperative completion.

## Test artifacts

- `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`
- Test-only commit: `eb9f0b340bb2013374800492d7eaf5d04f1b19ab`
- Starting test commit: `e8d859aedb5b4b6030cabacaca2daaffc527675b`
- Production files changed: none

## Behavioral RED: authoritative keyboard final

Command preparation and execution:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-release-drain-red build-for-testing
mkdir -p /tmp/feishuspeech-issue27-release-drain-red/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/Frameworks
cp /tmp/feishuspeech-issue27-release-drain-red/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/FeishuSpeech.debug.dylib /tmp/feishuspeech-issue27-release-drain-red/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/Frameworks/
xcrun xctest -XCTest FeishuSpeechTests.CurrentFocusAppendSessionTests/test_authoritativeFinalReconcilesExactGraphemeTailBeforeClosingSafetyMonitors /tmp/feishuspeech-issue27-release-drain-red/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

- Build-for-testing succeeded before the missing-policy coordinator cases were added.
- Focused XCTest exited `1` with six expected assertion failures and no unexpected error.

Failure signature: `test_authoritativeFinalReconcilesExactGraphemeTailBeforeClosingSafetyMonitors`

- Expected outcome: `exactCommitted`; actual: `preservedDivergence`.
- Expected one fixed-PID replacement transaction with one grapheme Backspace and one-character suffix; actual replacement requests: zero.
- Expected the safety monitors to be armed during the final transaction; the posting hook was never reached because current `finalize` closes before reconciliation.
- Expected one guarded replacement call, one destructive Backspace pair, and one insertion pair; all actual counts were zero.

The companion `test_equalAuthoritativeFinalClosesArmedOwnerWithoutDuplicateKeyboardEvents` executed successfully on the same subject. That is a preservation assertion, not the RED verdict: it locks the already-correct no-duplicate behavior while the differing-final path remains RED.

## Compile RED: injected operation watchdog and post-release drain expiry

Command:

```text
xcodebuild -quiet -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-release-drain-followup build-for-testing
```

Result: exit `65`, `TEST BUILD FAILED`.

Primary failure signatures:

```text
StreamingMainViewModelTests.swift:1626:35: error: cannot find 'StreamingDrainPolicy' in scope
StreamingMainViewModelTests.swift:1626:35: error: extra argument 'streamingDrainPolicy' in call
StreamingMainViewModelTests.swift:1677:35: error: cannot find 'StreamingDrainPolicy' in scope
StreamingMainViewModelTests.swift:1677:35: error: extra argument 'streamingDrainPolicy' in call
```

The later `.streaming`/`.sealing` inference errors are downstream consequences of the missing initializer/type. This is the anticipated compile-time RED: baseline production has neither the value-only `StreamingDrainPolicy` nor the internal `MainViewModel` injection seam required for deterministic short deadlines. Production was not edited to bypass it.

The two coordinator tests are ready to execute once that seam exists:

1. `test_hangingFactoryTimesOutAsRecoverableAndSuccessorLeavesSilentActiveState`
   - first factory never completes normally;
   - the operation watchdog must cancel that attempt exactly once;
   - zero-delay retry must create the successor under the same generation;
   - output must resume without abnormal cleanup.
2. `test_postReleaseDrainExpiryPreservesOutputAndSuppressesLatePacketCompletion`
   - first packet commits visible text and the second packet ignores cancellation;
   - Fn-up arms a 2 ms post-barrier drain budget;
   - expiry must preserve the first output and publish `.emptyFinalPreservedPartial` rather than ordinary success;
   - releasing the late packet after cleanup must cause no additional write.

## Additional checks

```text
git diff --check
swiftlint lint --strict FeishuSpeechTests/CurrentFocusAppendSessionTests.swift FeishuSpeechTests/StreamingMainViewModelTests.swift
```

- `git diff --check`: clean before commit.
- SwiftLint reported five pre-existing violations outside the new blocks: two long identifier findings in existing CurrentFocus test fakes, two existing closure-parameter-position findings, and the existing overlong coordinator fake type name. The new timeout-provider closure finding was corrected before commit.

## Outcome

RED is established at both remaining acceptance boundaries. The keyboard subject fails behaviorally against the existing production implementation, and the coordinator watchdog/drain tests fail compilation specifically because the blueprint's production policy and injection seam do not yet exist. No production or installed Release artifact was modified.

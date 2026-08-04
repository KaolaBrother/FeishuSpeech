# Issue 27 coordinator implementation receipt

## Assigned task

Implement the phase-2 streaming coordinator lifecycle so Fn release closes audio capture but does not truncate recognition. The same generation must continue through in-flight work, retry/backoff, journal replay, tail delivery, and terminal action-2 settlement. Add bounded operation and post-release drain watchdogs, suppress late completions, preserve already-produced output on drain expiry, reset retry streaks on successful packet acknowledgement, and keep lifecycle diagnostics transcript- and credential-free.

## Verification tier

`tests-green`

## Files changed

- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeech/Models/StreamingSpeechModels.swift`

Production commit: `62832ad fix: drain streaming recognition after release`

The test-contract migration used for final validation is commit `c067d2d test: align coordinator with terminal drain contract`. No test file was edited or committed by the implementing role.

## Before verification

Command:

```text
xcodebuild -scheme FeishuSpeech -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-coordinator build-for-testing
```

Result: exit `65`. The RED baseline failed to compile because the production surface did not yet provide `StreamingDrainPolicy` or the injected drain-policy initializer seam. Full output is recorded in `/tmp/feishuspeech-issue27-coordinator-baseline.log`.

An initial focused `xcodebuild test` attempt stalled waiting for test workers and was interrupted with exit `130`. Subsequent verification used the already-built XCTest bundle directly, avoiding application launch and macOS permission prompts.

## After verification

### Test build

Command:

```text
xcodebuild -scheme FeishuSpeech -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-coordinator build-for-testing
```

Result: exit `0`, `** TEST BUILD SUCCEEDED **`.

### Phase-2 focused coordinator contract

Command:

```text
xcrun xctest -XCTest '<six issue-27 release-drain, authoritative-final, retry-reset, factory-watchdog, and late-suppression tests>' /tmp/feishuspeech-issue27-coordinator/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: exit `0`; 6 tests executed, 0 failures.

### Streaming coordinator suite after contract migration

Command:

```text
xcrun xctest -XCTest 'FeishuSpeechTests.StreamingMainViewModelTests' /tmp/feishuspeech-issue27-coordinator/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: exit `0`; 83 tests executed, 0 failures.

### Full authored suite

Command:

```text
xcrun xctest /tmp/feishuspeech-issue27-coordinator/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: exit `0`; 308 tests executed, 0 failures in 6.103 seconds.

### Adjacent streaming/input suites

Direct XCTest selection covered `StreamingCoordinatorStateTests`, `CurrentFocusAppendSessionTests`, `CursorTextSessionTests`, `FinalTextOutputSecurityTests`, `FeishuStreamingSessionTests`, `StreamingAudioIngressTests`, and `AudioRecorderStreamingIntegrationTests`.

Result: exit `0`; 123 tests executed, 0 failures.

### Strict lint

Command:

```text
swiftlint lint --strict FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Models/StreamingSpeechModels.swift
```

Result: exit `0`; 0 violations, 0 serious violations.

### Debug build

Command:

```text
xcodebuild -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/feishuspeech-issue27-coordinator-debug build
```

Result: exit `0`, `** BUILD SUCCEEDED **`.

### Diff integrity and privacy review

`git diff --check` exited `0`. Lifecycle logging records generation, monotonic attempt identifier, operation/phase, retry streak, packet counts, timeout, and whether usable output was preserved. It does not log transcript text, request or response bodies, credentials, accessibility target content, or derived content hashes.

## Result location

The implementation landed in commit `62832ad` in the issue-27 workflow worktree. This receipt is stored at `kaola-workflow/issue-27/coordinator-green.md` in the root checkout.

evidence-binding: review cd499c929161
verdict: pass
findings_blocking: 0
finding: id=R1 scope=in_scope action=follow_up status=open severity=low fix_role=tdd-guide rationale=speech-400-401-invalidation-tests-use-real-retry-sleep-instead-of-new-sleeper-seam

# Code Review - issue #20 review

## Verdict
APPROVE. No blocking findings found.

## Findings
### CRITICAL
none

### HIGH
none

### MEDIUM
none

### LOW
- [FeishuSpeechTests/FeishuAPIServiceTests.swift](/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-20/FeishuSpeechTests/FeishuAPIServiceTests.swift:386): `assertSpeechHTTPErrorRefreshesToken` proves 400/401 token invalidation and retry, but it does not install `setRetrySleeperForTesting`, so each invalidation test still pays the real 1-second retry delay. This is non-blocking because behavior is covered and the focused run passes, but the test can use the new sleeper seam in a follow-up.

## Review Notes
- FeishuAPIService test seams are DEBUG-gated: retry sleeper, direct request sender, reset, parser/path accessors, and test-only send helpers all sit under `#if DEBUG`; release code still falls through to `Task.sleep` and the existing direct request path.
- `DirectHTTPResponse` is now `Sendable`; actor-owned test closures are set and cleared through actor-isolated DEBUG methods.
- MainViewModel DEBUG hooks keep production defaults on the live subscription path. `startsTranscriptionTask: false` is only exercised through DEBUG wrappers in tests; the production sink calls `handleHotKeyState(state)` with the default `true`.
- MockURLProtocol was replaced with the request-sequence fake used by the new API tests; no remaining references to the old URLProtocol helper were found.
- `FeishuSpeech.xcodeproj/project.pbxproj` is unchanged. The existing `AudioRecorderRecoveryTests.swift` target-membership exclusion remains out of scope for this node.

## Validation Reviewed
- `git diff --check`: pass.
- `kaola-workflow/issue-20/.cache/focused-validation-logs/direct-xctest-issue20-new-methods.log`: exit 0 for the 14 new FeishuAPIService focused tests.
- The recorded xctest command used the wrong XCTest suite name for the three new MainViewModel tests and therefore executed 0 of them in that log. Reviewer reran the corrected selector:
  `xcrun xctest -XCTest FeishuSpeechTests.CoordinatorStateInterplayTests/test_duplicateTranscribingSignals_stopRecorderOnlyOnce,FeishuSpeechTests.CoordinatorStateInterplayTests/test_maxDurationTranscribing_thenDuplicateReleaseStopsRecorderOnlyOnce,FeishuSpeechTests.CoordinatorStateInterplayTests/test_transcriptionErrorDuringNewActiveRecording_doesNotClobberRecordingState .kw/DerivedData/issue-20/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest`
  Result: pass, 3 tests, 0 failures.

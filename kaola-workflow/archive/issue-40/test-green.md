# Issue #40 GREEN evidence

## Scope

Test custody resumed after the Issue #40 production implementation landed.
Only test fixtures were repaired; no production, product documentation, or
workflow implementation files were changed by this turn.

The serialized run used baseline commit
`98e1eb53b6aaee369f6481303a289ca60b843262`; the implementing role's
production repair was present as an uncommitted worktree change.

The repairs were:

- `Issue40ApplicationRuntime` now uses an explicit `convenience init()` instead
  of evaluating a main-actor `Issue40ReviewTrace()` in a synchronous default
  argument.
- The capture-order assertion compares `runtime.trace.events` to the expected
  event sequence.
- `Issue40FinalTextOutput` supplies the unchanged compatibility
  `insertAtCurrentFocusOnce` protocol requirement while retaining the review
  fallback assertions.
- Successful fallback fixtures now provide the complete safe-read sequence for
  two consecutive preflight composites and one postflight composite.
- The strengthened R1 oracle verifies each preflight composite as
  `Secure(start) -> raw PID -> running identity -> frontmost identity ->
  Secure(end)`, including a Secure Input transition during the second
  identity window; the ending read rejects before any pasteboard or Cmd+V
  mutation.

## Focused serialized command

```bash
xcodebuild -scheme FeishuSpeech \
  -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests test
```

Result:

```text
Test Suite 'FeishuSpeechTests.xctest' passed
    Executed 79 tests, with 0 failures (0 unexpected)
Test Suite 'Selected tests' passed
    Executed 79 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

Complete serialized output:
`/tmp/feishuspeech-issue40-focused-r1-strengthened.log`

Result bundle:
`/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_11-49-53-+0800.xcresult`

## Additional check

- `git diff --check` — passed.

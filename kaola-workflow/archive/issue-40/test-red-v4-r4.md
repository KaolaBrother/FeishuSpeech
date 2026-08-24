# Issue #40 v4 R4 TEST-ONLY RED

- Baseline actually executed: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`
- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Scope: test custody only; production behavior was not changed by this task.
- Review authority: `.cache/code-review-v4-final.md`, finding R4.

## Oracle added

`FeishuSpeechTests/StreamingMainViewModelTests.swift` now adds:

- `test_postReleaseDrainExpiryNeverAuthorizesPartialBeforeAction2ThroughEitherUISeam`
  - drives a real async non-cooperative streaming session through the recorder
    barrier and bounded post-release drain expiry;
  - attempts both UI-authority paths from the test presenter: the production
    review panel's Send action path and a qualified native Return event;
  - requires a durable read-only recovery surface, no ordinary `.editable`
    authority, zero delivery/AX/Unicode/clipboard/copy/current-focus append,
    and no retry/session recreation after action 2 never settled;
  - verifies the retained partial remains unchanged after the late packet is
    released.
- `test_postReleaseDrainExpiryRetainsMultilineLFAsInertReadOnlyData`
  - retains an exact `LF`-delimited partial through drain expiry and late
    completion suppression;
  - forbids conversion to a terminal streaming error or ordinary editable
    confirmation authority;
  - verifies zero delivery, AX, Unicode/current-focus, copy, and append output.

The test-only delivery double now exposes `deliverCallCount`, and the test
presenter exposes real Send/qualified Return attempts without adding a
production confirmation entry point.

## Serialized RED command

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-r4-red-final -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryNeverAuthorizesPartialBeforeAction2ThroughEitherUISeam -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryRetainsMultilineLFAsInertReadOnlyData test 2>&1 | tee /tmp/issue40-v4-r4-red-final.log
```

Result: `Executed 2 tests, with 6 failures (0 unexpected)`.

xcresult: `/tmp/issue40-v4-r4-red-final/Logs/Test/Test-FeishuSpeech-2026.08.23_23-38-14-+0800.xcresult`

## Failure signatures proving RED

1. `StreamingMainViewModelTests.test_postReleaseDrainExpiryNeverAuthorizesPartialBeforeAction2ThroughEitherUISeam`
   - `failed - action 2 never settled; expiry must not install ordinary editable authority`
   - current production published ordinary `.editable` authority after drain expiry.
2. The same test's delivery ledger asserted `deliverCallCount == 0` but observed
   `("1") is not equal to ("0")`.
3. The same test's explicit Send seam asserted no materialized Send callback but
   failed `XCTAssertFalse - a read-only recovery surface must have no Send callback`.
4. The same test asserted zero delivered text but observed
   `["safe partial retained until action two"]`.
5. `StreamingMainViewModelTests.test_postReleaseDrainExpiryRetainsMultilineLFAsInertReadOnlyData`
   failed `XCTAssertFalse - LF-delimited partials must not be destroyed as a terminal streaming failure`.

The zero-side-effect assertions for AX writes, Unicode/synthetic input,
clipboard/copy, current-focus append, retry/session recreation, and late-packet
mutation were retained; the failures above are the authority/terminal-state
defects the new oracle is intended to expose.

`git diff --check` passed after authoring the tests and receipt.

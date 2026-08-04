# Issue #26 multi-partial RED evidence

Date: 2026-08-04  
Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`  
Baseline commit exercised: `7396a7cbdaf37058ca2a9b2df89923525d2ce7c8`

## Assigned acceptance surface

The RED suite fixes the following local product contract without asserting an unverified Feishu
partial-response semantic:

- every eligible live response owns its coordinator journal index once and extends one local UTF-16
  frontier in response order while the matching Fn generation remains held;
- equal response text on different journal indices is owned more than once, while replay of an
  already-owned index is not;
- a previously failed journal index can be owned once when replay succeeds, then is historical on
  every later replay;
- contentless, unsafe, stale, and sealed responses do not advance or reserve the frontier;
- release closes admission; action 2 and late packet/final events cannot create first output or add
  a suffix;
- the real `CurrentFocusAppendSession` receives locally growing frontiers and posts only their new
  UTF-16 suffixes while retaining its fixed PID, AX destination, Secure Input, and uncertainty gates.

## Test artifacts

- `FeishuSpeechTests/StreamingMainViewModelTests.swift`
  - `test_disjointLivePacketResponsesBuildOneOrderedFrontierWhileFnRemainsHeld`
  - `test_equalTextOnDistinctLivePacketIndicesIsOwnedTwice`
  - `test_retryOwnsOnlyThePreviouslyFailedJournalIndexAndNeverReownsHistory`
  - `test_liveAXOwnerReceivesGrowingFrontiersForDisjointPacketResponses`
  - `test_ineligibleEventsNeverAdvanceOrReserveTheResponseFrontier`
  - `test_releaseActionTwoCannotCreateFirstOutputOrAppendToOwnedFrontier`
- `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`
  - `test_coordinatorAssembledGrowingFrontiersPostOnlyEachNewUTF16Suffix`

No production or project-configuration file was edited. No installed application interaction,
credentials, microphone, Fn event, permission request, transcript, AX element content, clipboard
content, or target-application content was used.

## Commands run

Project-native compilation of the test artifact:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' build-for-testing
```

Result: `** TEST BUILD SUCCEEDED **` at the recorded baseline.

The first focused `xcodebuild ... test` invocation built successfully but Xcode's macOS test worker
did not materialize any test-case output and was interrupted after 69.714 seconds. Its result was
`** TEST INTERRUPTED **`, exit 75, with the runner diagnostic `waiting for workers to materialize`.
The derived test host was terminated; the already-running installed `/Applications/FeishuSpeech.app`
process was untouched.

The already-built XCTest bundle was then exercised directly, without launching the application or
invoking its lifecycle/permission paths:

```text
env LLVM_PROFILE_FILE=/tmp/issue26-multipartial-%p.profraw \
  DYLD_LIBRARY_PATH=/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  -XCTest 'StreamingMainViewModelTests/test_disjointLivePacketResponsesBuildOneOrderedFrontierWhileFnRemainsHeld,StreamingMainViewModelTests/test_equalTextOnDistinctLivePacketIndicesIsOwnedTwice,StreamingMainViewModelTests/test_retryOwnsOnlyThePreviouslyFailedJournalIndexAndNeverReownsHistory,StreamingMainViewModelTests/test_liveAXOwnerReceivesGrowingFrontiersForDisjointPacketResponses,StreamingMainViewModelTests/test_ineligibleEventsNeverAdvanceOrReserveTheResponseFrontier,StreamingMainViewModelTests/test_releaseActionTwoCannotCreateFirstOutputOrAppendToOwnedFrontier' \
  /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: **6 executed, 10 failures, 0 unexpected**. Five new acceptance tests failed RED; the
ineligible-event boundary control passed.

The production append-owner contract test was also run directly:

```text
/Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  -XCTest CurrentFocusAppendSessionTests/test_coordinatorAssembledGrowingFrontiersPostOnlyEachNewUTF16Suffix \
  /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

It passed as a safety control: the existing production owner correctly posts only new UTF-16
suffixes when its caller supplies locally monotonic frontiers.

Focused lint command:

```text
swiftlint lint FeishuSpeechTests/CurrentFocusAppendSessionTests.swift \
  FeishuSpeechTests/StreamingMainViewModelTests.swift
```

Result: no serious violations. Three pre-existing warnings remain in
`StreamingMainViewModelTests.swift` (`closure_parameter_position` twice and the existing long test
factory type name).

## Exact RED failure signatures

### Disjoint live packet indices do not advance in response order

`test_disjointLivePacketResponsesBuildOneOrderedFrontierWhileFnRemainsHeld`

```text
XCTAssertEqual failed: ("["one"]") is not equal to ("["one", "two", "three"]")
```

The real `CurrentFocusAppendSession` received raw divergent scalars, so only the first was posted.
The fixed-PID assertion also observed `[42]` instead of `[42, 42, 42]` because only one eligible
suffix reached the poster.

### Equal text is incorrectly treated as raw repeated state instead of a new-index frontier advance

`test_equalTextOnDistinctLivePacketIndicesIsOwnedTwice`

```text
XCTAssertEqual failed: ("["same", "same"]") is not equal to ("["same", "samesame"]")
```

The coordinator forwarded two raw values instead of constructing the journal-indexed frontier.

### Replay lacks durable journal-index ownership

`test_retryOwnsOnlyThePreviouslyFailedJournalIndexAndNeverReownsHistory`

```text
XCTAssertEqual failed: ("["same", "same"]") is not equal to ("["same", "samesame"]")
XCTAssertEqual failed: ("["same", "same", "tail"]") is not equal to ("["same", "samesame", "samesametail"]")
```

The two-retry scenario changes historical replay response strings deliberately. The expected output
ignores those strings, owns the formerly failed frontier index once, treats it as historical during
the second replay, and admits the next failed index once. Baseline instead routes the latest raw
catch-up value.

### Exact AX range receives raw scalars instead of local growing frontiers

`test_liveAXOwnerReceivesGrowingFrontiersForDisjointPacketResponses`

```text
XCTAssertEqual failed: ("["one", "two", "three"]") is not equal to ("["one", "onetwo", "onetwothree"]")
```

This asserts against the real `CursorTextSession`/captured AX-range path, not a stand-in for the
subject.

### Release/action 2 still mutates output

`test_releaseActionTwoCannotCreateFirstOutputOrAppendToOwnedFrontier`

```text
XCTAssertEqual failed: ("["terminal first output"]") is not equal to ("[]")
XCTAssertEqual failed: ("["seed", " terminal suffix"]") is not equal to ("["seed"]")
```

The first scenario proves action 2 can currently create the first output after release. The second
proves it can append a suffix after release. Synthetic one-shot output and clipboard recovery both
remained unused in the test.

## RED verdict

**RED confirmed on baseline `7396a7cbdaf37058ca2a9b2df89923525d2ce7c8`.** The current
coordinator has no journal-indexed response ownership ledger or locally growing UTF-16 frontier, and
its terminal finalize path still admits action-2 text after release. The existing production append
owner already behaves correctly when handed a monotonic local frontier, so the failing boundary is
the coordinator/replay/release policy rather than PID, AX, Secure Input, or Unicode suffix posting.

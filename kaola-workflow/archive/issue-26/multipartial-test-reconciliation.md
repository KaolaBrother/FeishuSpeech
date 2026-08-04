# Issue #26 multi-partial test reconciliation

Date: 2026-08-04  
Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`  
Baseline commit beneath the working changes: `7396a7cbdaf37058ca2a9b2df89923525d2ce7c8`

## Scope and custody

Only test artifacts were edited during reconciliation. The concurrent production implementation in
`FeishuSpeech/ViewModels/MainViewModel.swift` was read and run but not modified.

The acceptance oracle is now:

- one coordinator-owned response per eligible journal index;
- a held UTF-16 frontier formed by concatenating newly owned response scalars in response order;
- replay suppresses every already-owned historical index, including an index first owned during an
  earlier replay;
- release closes admission before draining and action 2/late callbacks only close the existing
  output owner;
- release cannot create first output, append, rewrite, invoke one-shot insertion, or copy;
- PID, exact AX element, Secure Input, unsafe text, destination drift, delivery uncertainty,
  cancellation, reset/sleep/wake, retry, feedback privacy, and lifecycle isolation remain stronger
  safety boundaries.

## Before reconciliation

After the issue #26 production implementation was present but before updating superseded test
assertions, direct lifecycle-free execution reported:

```text
Executed 69 tests, with 68 failures (0 unexpected)
```

Those were **68 failed assertions across 29 failed test cases**, not 68 removed or disabled tests.
The failures fell into three superseded-contract groups:

1. raw provider scalar replacement was expected where the new coordinator correctly supplied
   growing frontiers;
2. action-2/final text was expected to insert, append, or rewrite after release;
3. absent continuous owners and unsafe responses were expected to fall back to release-time
   one-shot insertion or clipboard copy.

Examples of the old assertions included:

```text
["one", "two", "three"] instead of ["one", "onetwo", "onetwothree"]
["first", "first extension", "first extension"] instead of concatenated held frontiers
finalTexts == [actionTwoText] instead of finalTexts == [nil]
insertedTexts/copiedTexts == [terminalText] instead of no release-time output
```

## Surgical reconciliation

The existing broad tests were retained and their names, setup, and assertions were updated only
where the old product contract had been superseded:

- live AX and rebound AX tests now assert growing owned-range frontiers and no action-2 rewrite;
- append-owner tests now assert growing frontiers during hold, `finalText: nil`, and the held frontier
  as `lastAcceptedText` when release closes the owner;
- retry tests now assert historical journal suppression and concatenation only for newly owned
  indices;
- unbound/factory-miss/final-only tests now assert zero release-time insert, synthetic input, or
  copy;
- unsafe control-character tests now assert the response never reaches an owner and never becomes a
  release-time clipboard recovery path;
- release/backoff/replay barrier tests still prove cancellation and successor exclusion, while a
  generation with no armed owner and no owned frontier retains its fixed stream-error outcome;
- completion tests distinguish fixed transcript-free no-owner feedback from the no-feedback close
  of an already visible held owner.

No PID, AX element, Secure Input, destination-drift, delivery-uncertainty, retry allowlist,
cancellation, reset, sleep/wake, overlay privacy, or recorder-barrier scenario was deleted.

## Commands and results

Build the test artifacts without launching the application lifecycle:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' build-for-testing
```

Result: `** TEST BUILD SUCCEEDED **`.

Run the complete coordinator class directly:

```text
env LLVM_PROFILE_FILE=/tmp/issue26-reconcile-final-%p.profraw \
  DYLD_LIBRARY_PATH=/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  -XCTest StreamingMainViewModelTests \
  /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

After reconciliation:

```text
Executed 69 tests, with 0 failures (0 unexpected)
```

Run every directly runnable unit test in the bundle:

```text
env LLVM_PROFILE_FILE=/tmp/issue26-all-tests-%p.profraw \
  DYLD_LIBRARY_PATH=/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result:

```text
Executed 270 tests, with 0 failures (0 unexpected)
```

This direct invocation did not launch the application or invoke AppDelegate, microphone, Fn,
credentials, or permission-prompt paths.

Focused lint:

```text
swiftlint lint FeishuSpeechTests/CurrentFocusAppendSessionTests.swift \
  FeishuSpeechTests/StreamingMainViewModelTests.swift
```

Result: no serious violations. Three pre-existing warnings remain in
`StreamingMainViewModelTests.swift`: two `closure_parameter_position` warnings and the existing long
`CoordinatorCurrentFocusAppendSessionFactory` test-double name.

## After counts

| Surface | Before | After |
|---|---:|---:|
| `StreamingMainViewModelTests` discovered tests | 69 | 69 |
| Failed test cases | 29 | 0 |
| Failed assertions | 68 | 0 |
| Directly runnable bundle tests | not used for the before classification | 270 executed |

The reconciliation changed the test oracle; it did not independently grade or modify the production
implementation.

## R1 recognition-availability reconciliation (2026-08-04)

### Baseline and scope

- Commit SHA: `7396a7cbdaf37058ca2a9b2df89923525d2ce7c8`.
- Current reviewed `FeishuSpeech/ViewModels/MainViewModel.swift` SHA-256:
  `0fb593aac555ed3d109e709c727f70c0482d85fc80e31f180cfaf43ec09b130e`.
- Test-author writes remained limited to `FeishuSpeechTests/StreamingMainViewModelTests.swift` and
  this evidence document. The pre-existing production change was not edited.

R1 separates recognition availability from output capability. A usable, active, unsealed held
response counts as recognized even when output is disabled, unsafe, or cannot acquire an owner.
Those paths must preserve zero insert/rewrite/copy behavior without inventing empty-result feedback
or a stream error merely because the output frontier is empty.

### Pre-reconciliation result

After the R1 production fix and before updating the superseded feedback/status expectations, direct
coordinator execution reported:

```text
Executed 71 tests, with 16 failures (0 unexpected)
```

The 16 assertions expected one of two now-obsolete outcomes after usable held recognition:

- `.emptyFinalPreservedPartial` completion feedback for disabled, unsafe, stale-destination, or
  ownerless output; or
- a visible `流式识别失败` state when release sealed a recoverable failure/retry/replay path whose
  usable recognition had not entered an output owner.

### Surgical oracle update

Only those superseded feedback/status expectations were changed:

- usable ownerless, disabled, stale-destination, and unsafe responses now expect no empty-result,
  provisional, manual-recovery, or error feedback;
- recoverable finish, retry-backoff, and replay cancellation after a usable held response now expect
  normal idle completion with no error surface;
- all zero insert, captured-range rewrite, current-focus output, synthetic input, clipboard copy,
  cancellation count, retry delay, successor exclusion, recorder barrier, and late-event assertions
  remain in place.

The retained negative controls still pass unchanged:

- Secure Input rejection remains an immediate fixed security error;
- authentication, invalid-request, and other terminal nonrecoverable failures remain errors;
- stale/sealed callbacks remain no-ops;
- contentless-only and no-recognition recoverable factory/first-packet/retry-sleep failures still
  publish the fixed stream error. In particular,
  `test_releaseActivelyCancelsCooperativeRetrySleepWithoutWaitingOrRetrying` continues to require an
  error because its first packet fails before any usable recognition.

### Lifecycle-free validation

Build-only command:

```text
xcodebuild -quiet -scheme FeishuSpeech -destination 'platform=macOS' build-for-testing
```

Result: succeeded. The existing Swift 6 captured-variable warning remains in
`FeishuAPIServiceTests.swift:271`.

Complete coordinator command:

```text
env LLVM_PROFILE_FILE=/tmp/feishuspeech-coordinator-green2-%p.profraw \
  DYLD_LIBRARY_PATH=/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  -XCTest StreamingMainViewModelTests \
  /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result:

```text
Executed 71 tests, with 0 failures (0 unexpected)
```

Complete directly runnable bundle command:

```text
env LLVM_PROFILE_FILE=/tmp/feishuspeech-bundle-green-%p.profraw \
  DYLD_LIBRARY_PATH=/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-fraktktlkmyirtcjmmknqiurnrtm/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result:

```text
Executed 272 tests, with 0 failures (0 unexpected)
```

The direct XCTest runs did not launch the app or exercise AppDelegate, Fn, microphone, credentials,
or permissions.

Focused validation:

```text
swiftlint lint FeishuSpeechTests/StreamingMainViewModelTests.swift
git diff --check
```

Result: no serious lint violations and no whitespace errors. The same three pre-existing warnings
remain in the coordinator test file: two `closure_parameter_position` warnings and the long
`CoordinatorCurrentFocusAppendSessionFactory` test-double name.

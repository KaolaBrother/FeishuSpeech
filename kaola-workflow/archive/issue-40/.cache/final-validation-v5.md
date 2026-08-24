# Issue #40 v5 final-candidate validation receipt

Date: 2026-08-24 15:03:52 +0800
Role: read-only validation investigator
Scope: v5 candidate in `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`.

No production, test, project, or workflow source file was edited by this validation. The only
write from this run is this receipt in the workflow evidence directory. The app was not launched
or installed by the investigator. XCTest hosts were transiently launched by `xcodebuild` and
were stopped after the reproducible hang; no GUI/UAT claim is made.

## Setup and identity

`CLAUDE.md` was read in full before validation:

```text
wc -l CLAUDE.md; sed -n '1,999p' CLAUDE.md
=> 119 lines; full read completed.
```

Environment:

```text
sw_vers; xcodebuild -version; swiftlint version; uname -m
=> macOS 26.6.2 / 25G83; Xcode 26.6 / 17F113; SwiftLint 0.65.0; arm64.
```

Repository identity:

```text
git rev-parse HEAD
=> b321ac5d6c04c91ced9afeb2240f9566d9b8d305

git status --short --branch
=> workflow/issue-40...origin/workflow/issue-40; expected v5 production/test changes dirty,
   including new untracked FeishuSpeech/Services/ReviewSubmissionExecutor.swift.
```

No existing worktree changes were reverted or normalized.

## Authoritative focused matrix source and current test size

`kaola-workflow/issue-40/test-green-v5.md` was inspected. Its canonical focused command is the
serialized nine-selector matrix in the “Canonical final focused-matrix GREEN” section. That
historical checkpoint recorded 306 tests. The receipt then adds five v5 security selectors and
records `FinalTextOutputSecurityTests` at 59 tests. Current source counts are:

```text
CurrentFocusAppendSessionTests=38
FinalTextOutputSecurityTests=59
ReviewDestinationDeliveryTests=13
ReviewFirstApplicationFallbackTests=16
ReviewFirstMainViewModelTests=33
ReviewWindowControllerReadinessTests=17
StreamingMainViewModelTests=105
TranscriptionReviewViewTests=30 (14 parent + 16 nested keyboard tests)
CURRENT_FOCUSED_MATRIX_SIZE=311
```

Thus the current command is expected to cover 311 tests (306 canonical tests plus five later
security selectors), while the authoritative command shape remains the same.

## XCTest observations

Each test leg used a fresh `/tmp` DerivedData directory and
`-parallel-testing-enabled NO -maximum-parallel-testing-workers 1`.

### Focused v5 matrix

Exact command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-final-focused-dd.aWAb6I -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test
```

Exit: `75` after safe Ctrl-C interruption. Result bundle:

`/tmp/issue40-v5-final-focused-dd.aWAb6I/Logs/Test/Test-FeishuSpeech-2026.08.24_14-57-53-+0800.xcresult`

Direct xcresult summary:

```text
passedTests=158 failedTests=1 skippedTests=0 totalTestCount=159 result=Failed
failure=ReviewFirstMainViewModelTests/test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend()
```

This is not an assertion failure observed during the run. The process sample while the test was
in flight showed the main thread blocked in AppKit event tracking:

```text
ReviewFirstMainViewModelTests.test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend()
  -> Issue40ProductionReviewSurfacePresenter.invokeConfirm()
  -> Issue40ProductionReviewSurfacePresenter.invokeSend()
  -> issue40PerformRealSendClick(on:contentY:) [ReviewWindowControllerReadinessTests.swift:56]
  -> ReviewPanel.sendEvent(_:) [ReviewWindowController.swift:84]
  -> NSTextView mouseDown:
  -> NSApplication nextEventMatchingMask:
```

The same stack was sampled twice; the test remained in `NSTextView.mouseDown` while the helper
scanned the Send-control band. The host emitted periodic permission telemetry but made no test
progress. The xcodebuild result is therefore `TEST INTERRUPTED`, not a green focused result.

### Full project test target

Exact command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-final-full-dd.uFcw3g -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
```

Exit: `75` after the same safe Ctrl-C interruption at the same coordinator selector. Result
bundle:

`/tmp/issue40-v5-final-full-dd.uFcw3g/Logs/Test/Test-FeishuSpeech-2026.08.24_14-59-59-+0800.xcresult`

Direct xcresult summary:

```text
passedTests=328 failedTests=1 skippedTests=1 totalTestCount=330 result=Failed
failure=ReviewFirstMainViewModelTests/test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend()
skip=DirectFeishuKeepAliveSessionTests/test_liveKeepAliveTCPIsNotOnVPNTunnelAddress()
```

The full target had passed 328 tests before reaching the same hang. The one skip is the existing
live-TCP environmental test; this run did not reach a complete full-target total, so no claim is
made for the remaining tests.

## Build and static observations

### Debug build

Exact command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/issue40-v5-final-debug-dd.DXR8gT build
```

Exit `0`; `** BUILD SUCCEEDED **`. Artifact remained in `/tmp`. Xcode emitted normal multiple-
destination selection and AppIntents metadata-skipped warnings; no build error.

### Release build

Exact command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/issue40-v5-final-release-dd.5Jd94Z build
```

Exit `0`; `** BUILD SUCCEEDED **`. Artifact remained in `/tmp`; no installation or launch was
performed. Existing warnings included Swift 6 concurrency diagnostics for AVFoundation/
`NSLock`, `CancelBox` isolation, `DirectFeishuKeepAliveSession` captured mutation, deprecated
Keychain UI, logger isolation, and AppIntents metadata extraction. No compiler error occurred.

### SwiftLint and whitespace

```text
swiftlint --strict
=> Done linting! Found 0 violations, 0 serious in 36 files.
exit=0

git diff --check
=> no output
exit=0
```

## Forbidden output-route checks

The production scan was:

```text
for file in FeishuSpeech/Services/ReviewSubmissionExecutor.swift FeishuSpeech/Models/CursorTextModels.swift FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Controllers/ReviewWindowController.swift; do printf 'FILE=%s\n' "$file"; rg -n -i 'NSPasteboard|generalPasteboard|changeCount|Cmd.?V|command.?V|NSWorkspace\.shared\..*activate|\.activate\(|activateIgnoringOtherApps|retarget|CurrentFocusProvisionalOutputSession|insertAtCurrentFocusOnce|ReviewOutputCompatibilityWriter|ReviewOutputCompatibilityPoster' "$file" || true; done
```

Observed:

- `ReviewSubmissionExecutor.swift` contains no clipboard, Cmd+V, activation, or retarget call;
  only comments document that those operations are intentionally absent.
- `CursorTextModels.swift` contains no such output route.
- `ReviewWindowController.swift` contains no such output route.
- `MainViewModel.swift` contains only the source-compatible legacy initializer label
  `currentFocusAppendSessionFactory` and the production capture handoff; no clipboard/Cmd+V
  operation.

The default initializer proves the accepted route is the v5 facade:

```text
MainViewModel.swift:375  self.reviewSubmissionFacade = SystemReviewSubmissionFacade()
MainViewModel.swift:808  target: .production(descriptor)
MainViewModel.swift:2186 issueAttemptHandle()
MainViewModel.swift:2203 makeAdmissionEnvelope(...)
MainViewModel.swift:2210 enqueueAdmission(envelope)
MainViewModel.swift:2295 enqueueStart(handle)
```

The `ReviewSubmissionExecutor` comments and implementation state that its target registry is fixed,
it does not activate or retarget, and only the post-boundary immutable Unicode pair reaches the
committer. The legacy `.legacy`/`ReviewDestinationDelivery` branch remains source-compatible only
when an explicit legacy delivery dependency is injected; the default accepted app path selects
`SystemReviewSubmissionFacade`, sets `reviewDestinationDelivery` to nil, and never invokes that
branch. This is source evidence; the focused/full runtime proof is blocked by the Send-click
hang above.

Additional production-wide scan:

```text
rg -n -i 'NSPasteboard|generalPasteboard|changeCount|clearContents|setString\(|setData\(|writeObjects|readObjects|pasteboardItems|public\.png|Apple PNG|Cmd.?V|command.?V' FeishuSpeech --glob '*.swift'
=> no matches
```

The accepted route does contain the expected post-confirmation `postToPid` pair implementation;
this is not clipboard/Cmd+V and is outside the pre-confirmation boundary. No pre-confirmation
output operation was found by the checked-in source/tests.

## Protected asynchronous topology

Protected-file diff command:

```text
git diff --name-only -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift
=> FeishuSpeech/Services/HotKeyService.swift
```

The only protected-file diff is four HotKeyService lines; no recorder, streaming actor, Feishu
API, journal, ingress, or direct-TCP implementation file changed. The marker scan was:

```text
for file in FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Services/ReviewSubmissionExecutor.swift FeishuSpeech/Services/AccessibilityClient.swift FeishuSpeech/ViewModels/MainViewModel.swift; do printf 'FILE=%s\n' "$file"; git diff --unified=0 -- "$file" | rg -n '^[+-].*(Task|Task\.detached|DispatchQueue|MainActor|audioQueue|bufferQueue|sessionQueue|CGEventTap|startRunning|stopRunning|await|NSLock|actor|NSEvent|addGlobalMonitor|addLocalMonitor|withChecked|continuation|Thread\.sleep)' || true; done
```

Observed:

- `AudioRecorder.swift`, `FeishuStreamingSession.swift`, and `FeishuAPIService.swift` have no
  changed topology lines. `AudioRecorder` still owns separate `audioQueue`, `bufferQueue`, and
  `sessionQueue`; blocking `startRunning`/`stopRunning` remains on `sessionQueue`.
- `FeishuStreamingSession` remains an actor. `MainViewModel` retains separate
  `captureDrainTask` and `consumerTask` roots for recording ingress and recognition consumption.
- ReviewSubmissionExecutor uses its own serial queue and raw commit work; it does not move audio
  capture or provider recognition onto MainActor.
- The changed review/coordinator lines add/cancel MainActor presentation callbacks only. No
  `Task.detached`, MainActor synchronous wait, or capture/recognition queue migration was added.

A broad source scan found `Thread.sleep` and locks inside the executor's private serial raw
submission queue, as expected for its bounded gate; no MainActor blocking primitive was added.

## Reproduction status, inference, and limits

Reproduced:

- The authoritative focused command compiles and begins running, but deterministically hangs in
  the real Send-click fixture at AppKit `NSTextView.mouseDown`; the result is 158 passed, 1
  interrupted failure, 0 skips out of 311 planned tests.
- The full project target reaches the same selector and has 328 passed, 1 interrupted failure,
  and 1 expected live-TCP skip before interruption.
- Debug and Release builds succeed; SwiftLint strict and diff check pass.
- The accepted v5 source route has no clipboard/Cmd+V/activation/retarget operation and preserves
  the recording/recognition asynchronous roots.

Inference, high confidence: the current release candidate is not independently validation-green
because the real production-surface Send test fixture blocks the main AppKit event loop and
prevents completion of both required test targets. The source checks rule out the checked-in
forbidden routes and async-topology regression, but they do not replace a completed runtime
focused/full test run.

Not measured:

- No GUI/UAT, live microphone or Feishu credential behavior, third-party target focus or Unicode
  consumption, Accessibility permission behavior outside the test host, or sole-copy/install
  audit.
- No application launch/install was performed. The only app processes observed were transient
  XCTest hosts from the requested `xcodebuild` test commands; the final process check was empty:

```text
ps -axo pid=,comm= | awk '$2 ~ /FeishuSpeech|Siji\.FeishuSpeech|FeishuSpeechTests/ {print}'
=> empty output; exit 0
```

## Verdict

`BLOCKED / NOT GREEN`: Debug, Release, lint, diff, forbidden-route static checks, and protected
async-topology checks pass. The required focused and full XCTest gates are incomplete because the
same real Send-click test hangs in `NSTextView.mouseDown` and had to be interrupted safely. No
production or test fix was attempted; the exact result bundles, counts, stack evidence, and
blocker are preserved above for the owning implementation lane.

---

# Superseding v5 final-candidate validation after AppKit test-helper repair

Date: 2026-08-24 15:42 +0800
Role: read-only validation investigator

This section supersedes the preceding `BLOCKED / NOT GREEN` result. The test-only
AppKit event-helper repair was already present when this validation began; this
investigator made no production, test, project, or workflow-source edits. The
only write from this rerun is this workflow receipt. No standalone FeishuSpeech
application was launched or installed. `xcodebuild test` used transient XCTest
hosts only, and the final process check was empty.

## Identity and environment

Worktree:
`/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`

HEAD:
`b321ac5d6c04c91ced9afeb2240f9566d9b8d305`

Environment: macOS 26.6.2 / build 25G83, Xcode 26.6 / 17F113, SwiftLint
0.65.0, arm64. `CLAUDE.md` was read in full before this rerun.

The worktree already contained the Issue #40 candidate changes: 16 modified
tracked Swift files plus the untracked
`FeishuSpeech/Services/ReviewSubmissionExecutor.swift`. `git status --short
--branch` and `git diff --name-status` were recorded before validation. No
status or diff entry was created by this investigator.

## Focused 9-suite matrix

Fresh DerivedData:
`/tmp/issue40-v5-r5-focused-dd.cPydrM`

Exact command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r5-focused-dd.cPydrM -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test > /tmp/issue40-v5-r5-focused-20260824.log 2>&1
```

Exit: 0.

Raw log: `/tmp/issue40-v5-r5-focused-20260824.log`.

Result bundle:
`/tmp/issue40-v5-r5-focused-dd.cPydrM/Logs/Test/Test-FeishuSpeech-2026.08.24_15-38-08-+0800.xcresult`

Result: **311 tests executed, 0 failures, 0 skips** in 26.673 seconds
(26.781 reported by the selected-tests aggregate); `** TEST SUCCEEDED **`.

Per-suite counts from the raw log, in command order: FinalTextOutputSecurity
59, ReviewWindowControllerReadiness 17, TranscriptionReviewView 14,
TranscriptionReviewViewKeyboard 16, ReviewFirstMainViewModel 33,
ReviewDestinationDelivery 13, ReviewFirstApplicationFallback 16,
CurrentFocusAppendSession 38, and StreamingMainViewModel 105. Every suite
reported zero failures.

The previously hanging coordinator selector completed in this run. No test
watchdog or interruption was needed.

## Full project test target

Fresh DerivedData:
`/tmp/issue40-v5-r5-full-dd.Uya4JO`

Exact command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r5-full-dd.Uya4JO -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test > /tmp/issue40-v5-r5-full-20260824.log 2>&1
```

Exit: 0.

Raw log: `/tmp/issue40-v5-r5-full-20260824.log`.

Result bundle:
`/tmp/issue40-v5-r5-full-dd.Uya4JO/Logs/Test/Test-FeishuSpeech-2026.08.24_15-39-03-+0800.xcresult`

Result: **524 tests executed, 0 failures, 1 test skipped** in 44.290 seconds
(44.484 reported by the all-tests aggregate); `** TEST SUCCEEDED **`.

The sole skip is the expected, documented live-TCP guard:

```text
DirectFeishuKeepAliveSessionTests/test_liveKeepAliveTCPIsNotOnVPNTunnelAddress
Test skipped - live TCP previously hung the XCTest host; issue #34 forbids additional live sockets
```

No other test was skipped or interrupted.

## Debug and Release builds

Debug exact command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/issue40-v5-r5-debug-dd.rI1z66 build > /tmp/issue40-v5-r5-debug-20260824.log 2>&1
```

Exit: 0; `** BUILD SUCCEEDED **`.

Debug product: `/tmp/issue40-v5-r5-debug-dd.rI1z66/Build/Products/Debug/FeishuSpeech.app`.
Raw log: `/tmp/issue40-v5-r5-debug-20260824.log`.

Release exact command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/issue40-v5-r5-release-dd.Cq5g63 build > /tmp/issue40-v5-r5-release-20260824.log 2>&1
```

Exit: 0; `** BUILD SUCCEEDED **`.

Release product: `/tmp/issue40-v5-r5-release-dd.Cq5g63/Build/Products/Release/FeishuSpeech.app`.
Raw log: `/tmp/issue40-v5-r5-release-20260824.log`.

The compiler emitted non-fatal pre-existing warning diagnostics (32 Debug,
26 Release); neither build emitted a build error or failed. No product was
opened, copied to `/Applications`, or installed by this validation.

## SwiftLint and whitespace checks

Exact lint command:

```text
swiftlint --strict > /tmp/issue40-v5-r5-swiftlint-20260824.log 2>&1
```

Exit: 0. The log reports:

```text
Done linting! Found 0 violations, 0 serious in 36 files.
```

Exact diff check:

```text
git diff --check
```

Exit: 0; no output.

## Forbidden output-route checks

The accepted review path was scanned with this exact command:

```text
for file in FeishuSpeech/Services/ReviewSubmissionExecutor.swift FeishuSpeech/Models/CursorTextModels.swift FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Controllers/ReviewWindowController.swift; do printf 'FILE=%s\n' "$file"; rg -n -i 'NSPasteboard|generalPasteboard|changeCount|Cmd.?V|command.?V|NSWorkspace\.shared\..*activate|\.activate\(|activateIgnoringOtherApps|retarget|CurrentFocusProvisionalOutputSession|insertAtCurrentFocusOnce|ReviewOutputCompatibilityWriter|ReviewOutputCompatibilityPoster' "$file" || true; done
rg -n -i 'NSPasteboard|generalPasteboard|changeCount|clearContents|setString\(|setData\(|writeObjects|readObjects|pasteboardItems|public\.png|Apple PNG|Cmd.?V|command.?V' FeishuSpeech --glob '*.swift' > /tmp/issue40-v5-r5-forbidden-broad-20260824.log || true
```

Observed:

* The broad production Swift scan produced 0 match lines.
* The accepted default path remains `SystemReviewSubmissionFacade()` at
  `MainViewModel.swift:375`, captures `.production(descriptor)` at line 808,
  issues one handle at line 2186, builds one envelope at line 2203, and calls
  `enqueueAdmission` at line 2210. The post-boundary executor uses the fixed
  captured PID and `postToPid`; no clipboard or Cmd+V route appears.
* The source-compatible legacy delivery branch remains selectable only when an
  explicit legacy delivery dependency is injected; the default initializer
  sets `reviewDestinationDelivery` to nil. No default accepted route invokes
  legacy direct output, application activation, or retargeting.

## Protected asynchronous topology checks

Protected-file diff command:

```text
git diff --name-only -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift
```

Observed output: only `FeishuSpeech/Services/HotKeyService.swift`.

The zero-context topology marker scan over the protected services, executor,
accessibility client, and view model found no changed `Task.detached`,
`DispatchQueue`, `MainActor` migration, audio queue, streaming actor,
`startRunning`/`stopRunning`, continuation, or event-tap topology line. The
HotKeyService diff only advances the interference epoch on accessibility/tap
failure and normalizes whitespace.

Exact active-topology source scan:

```text
rg -n 'captureDrainTask|consumerTask|captureDrainTask = Task|consumerTask = Task|audioQueue|bufferQueue|sessionQueue|actor FeishuStreamingSession' FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/FeishuStreamingSession.swift
```

Observed topology remains:

* `MainViewModel` has independent `captureDrainTask` and `consumerTask` roots
  at lines 303-304 and starts them separately at lines 714-717.
* `AudioRecorder` retains distinct `audioQueue`, `bufferQueue`, and
  `sessionQueue`; session start/stop remains on `sessionQueue`.
* `FeishuStreamingSession` remains an actor.
* `ReviewSubmissionExecutor` has its own serial queue; MainActor admission is
  `queue.async` and returns without waiting (source lines 100-105).
* The only `Thread.sleep` matches are inside the executor's private bounded
  raw modifier/commit loops (lines 698 and 949-955), not in MainViewModel,
  AudioRecorder, or the streaming actor. A blocking-primitive scan found no
  `DispatchSemaphore`, `dispatch_sync`, `semaphore_wait`, or `Thread.sleep` in
  those MainActor/recording/recognition files.

These checks preserve the recording/recognition two-line asynchronous
topology and do not establish GUI/UAT behavior.

## Final process and evidence status

The final check was:

```text
ps -axo pid=,comm=,args= | awk '$2 ~ /FeishuSpeech|Siji\.FeishuSpeech|FeishuSpeechTests/ {print}'
```

Result: empty output, exit 0. No app process remains. No install or standalone
launch was performed.

Raw evidence retained at:

* `/tmp/issue40-v5-r5-focused-20260824.log`
* `/tmp/issue40-v5-r5-focused-dd.cPydrM/Logs/Test/Test-FeishuSpeech-2026.08.24_15-38-08-+0800.xcresult`
* `/tmp/issue40-v5-r5-full-20260824.log`
* `/tmp/issue40-v5-r5-full-dd.Uya4JO/Logs/Test/Test-FeishuSpeech-2026.08.24_15-39-03-+0800.xcresult`
* `/tmp/issue40-v5-r5-debug-20260824.log`
* `/tmp/issue40-v5-r5-release-20260824.log`
* `/tmp/issue40-v5-r5-swiftlint-20260824.log`
* `/tmp/issue40-v5-r5-forbidden-broad-20260824.log`

## Superseding verdict

**GREEN for the requested automated validation gates.** Focused v5 is 311/311
green; the full target is 524/524 executed with 0 failures and exactly one
documented live-TCP skip; Debug and Release build successfully; SwiftLint
strict and `git diff --check` pass; forbidden-route and protected-topology
checks pass; and the app is stopped. This is not a GUI/UAT or real-target
delivery claim.

---

# Superseding v5-r3 final validation after production/TDD GREEN closure

Date: 2026-08-24 17:00 +0800
Role: read-only validation investigator

This section supersedes all earlier validation sections and their verdicts.
The candidate already contained the production and TDD closure changes when
this rerun started. No production, test, project, or workflow-source file was
edited by this investigator. No standalone FeishuSpeech application was
launched or installed; only transient XCTest hosts were created by the
requested test commands.

## Setup, identity, and changed-file inventory

Worktree:
`/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`

`CLAUDE.md` was read in full before any validation action.

Environment: macOS 26.6.2 / build 25G83, Xcode 26.6 / 17F113, SwiftLint
0.65.0, arm64.

HEAD:
`b321ac5d6c04c91ced9afeb2240f9566d9b8d305`

Exact status command:

```text
git status --short --branch
```

Observed inventory (16 modified tracked files and one untracked Swift file):

```text
 M FeishuSpeech/Controllers/ReviewWindowController.swift
 M FeishuSpeech/Models/CursorTextModels.swift
 M FeishuSpeech/Models/TranscriptionReviewState.swift
 M FeishuSpeech/Services/AccessibilityClient.swift
 M FeishuSpeech/Services/CurrentFocusAppendSession.swift
 M FeishuSpeech/Services/HotKeyService.swift
 M FeishuSpeech/Services/ReviewDestinationDelivery.swift
 M FeishuSpeech/ViewModels/MainViewModel.swift
 M FeishuSpeech/Views/TranscriptionReviewView.swift
 M FeishuSpeechTests/FinalTextOutputSecurityTests.swift
 M FeishuSpeechTests/ReviewDestinationDeliveryTests.swift
 M FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift
 M FeishuSpeechTests/ReviewFirstMainViewModelTests.swift
 M FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift
 M FeishuSpeechTests/StreamingMainViewModelTests.swift
 M FeishuSpeechTests/TranscriptionReviewViewTests.swift
?? FeishuSpeech/Services/ReviewSubmissionExecutor.swift
```

`git diff --stat` reported 16 tracked files, 6,509 insertions and 763
deletions. The untracked executor is included in the build and lint checks but
not in `git diff --stat` until staged. No inventory entry was created by this
validation.

## Authoritative 9-suite focused matrix

Fresh DerivedData:
`/tmp/issue40-v5-r3-focused-dd.txr2pr`

Exact serialized command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r3-focused-dd.txr2pr -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test > /tmp/issue40-v5-r3-focused-20260824.log 2>&1
```

Exit: 0.

Raw log:
`/tmp/issue40-v5-r3-focused-20260824.log`

Result bundle:
`/tmp/issue40-v5-r3-focused-dd.txr2pr/Logs/Test/Test-FeishuSpeech-2026.08.24_16-57-14-+0800.xcresult`

Aggregate result: **321 tests executed, 0 failures, 0 skips** in 28.922
seconds (29.048 selected-tests aggregate); `** TEST SUCCEEDED **`.

Per-suite raw counts:

| Suite | Executed | Failures |
|---|---:|---:|
| CurrentFocusAppendSessionTests | 38 | 0 |
| FinalTextOutputSecurityTests | 65 | 0 |
| ReviewDestinationDeliveryTests | 13 | 0 |
| ReviewFirstApplicationFallbackTests | 16 | 0 |
| ReviewFirstMainViewModelTests | 34 | 0 |
| ReviewWindowControllerReadinessTests | 17 | 0 |
| StreamingMainViewModelTests | 105 | 0 |
| TranscriptionReviewViewKeyboardTests | 19 | 0 |
| TranscriptionReviewViewTests | 14 | 0 |

The repaired Send route and the new production/TDD selectors completed; no
watchdog or interruption was required.

## Full project test target

Fresh DerivedData:
`/tmp/issue40-v5-r3-full-dd.5Rqixq`

Exact serialized command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r3-full-dd.5Rqixq -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test > /tmp/issue40-v5-r3-full-20260824.log 2>&1
```

Exit: 0.

Raw log:
`/tmp/issue40-v5-r3-full-20260824.log`

Result bundle:
`/tmp/issue40-v5-r3-full-dd.5Rqixq/Logs/Test/Test-FeishuSpeech-2026.08.24_16-58-11-+0800.xcresult`

Aggregate result: **534 tests executed, 0 failures, 1 test skipped** in 45.583
seconds (45.767 all-tests aggregate); `** TEST SUCCEEDED **`.

The sole skip is exactly the documented live-TCP guard:

```text
DirectFeishuKeepAliveSessionTests/test_liveKeepAliveTCPIsNotOnVPNTunnelAddress
Test skipped - live TCP previously hung the XCTest host; issue #34 forbids additional live sockets
```

No other skip, failure, or interruption occurred.

## Debug and Release builds

Debug command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/issue40-v5-r3-debug-dd.AuOW3J build > /tmp/issue40-v5-r3-debug-20260824.log 2>&1
```

Exit: 0; `** BUILD SUCCEEDED **`.

Release command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/issue40-v5-r3-release-dd.mC2mxp build > /tmp/issue40-v5-r3-release-20260824.log 2>&1
```

Exit: 0; `** BUILD SUCCEEDED **`.

Build logs:

* `/tmp/issue40-v5-r3-debug-20260824.log`
* `/tmp/issue40-v5-r3-release-20260824.log`

The compiler emitted non-fatal existing warning diagnostics (32 in Debug, 26
in Release); neither build emitted a build error. No built product was opened,
copied to `/Applications`, or installed.

## SwiftLint and diff checks

Exact lint command:

```text
swiftlint --strict > /tmp/issue40-v5-r3-swiftlint-20260824.log 2>&1
```

Exit: 0. Terminal output:

```text
Done linting! Found 0 violations, 0 serious in 36 files.
```

Exact whitespace check:

```text
git diff --check > /tmp/issue40-v5-r3-diff-check-20260824.log 2>&1
```

Exit: 0; log size 0 bytes and no output.

## Forbidden output-route checks

The accepted review path was scanned with:

```text
for file in FeishuSpeech/Services/ReviewSubmissionExecutor.swift FeishuSpeech/Models/CursorTextModels.swift FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Controllers/ReviewWindowController.swift; do printf 'FILE=%s\n' "$file"; rg -n -i 'NSPasteboard|generalPasteboard|changeCount|Cmd.?V|command.?V|NSWorkspace\.shared\..*activate|\.activate\(|activateIgnoringOtherApps|retarget|CurrentFocusProvisionalOutputSession|insertAtCurrentFocusOnce|ReviewOutputCompatibilityWriter|ReviewOutputCompatibilityPoster' "$file" || true; done
rg -n -i 'NSPasteboard|generalPasteboard|changeCount|clearContents|setString\(|setData\(|writeObjects|readObjects|pasteboardItems|public\.png|Apple PNG|Cmd.?V|command.?V' FeishuSpeech --glob '*.swift' > /tmp/issue40-v5-r3-forbidden-broad-20260824.log || true
```

Observed:

* The broad `FeishuSpeech/**/*.swift` scan produced 0 match lines.
* The default initializer selects `SystemReviewSubmissionFacade()` at
  `MainViewModel.swift:375`, captures `.production(descriptor)` at line 808,
  issues one handle at line 2186, makes one admission envelope at line 2203,
  and enqueues it at line 2210.
* `ReviewSubmissionExecutor` only posts the prepared Unicode pair to the one
  captured PID after the admission boundary. It contains no clipboard,
  Cmd+V, activation, or ambient retarget operation.
* The source-compatible `.legacy` delivery branch and its activation code are
  reachable only when an explicit `ReviewDestinationDelivering` dependency is
  injected. The default initializer sets that dependency to nil; the accepted
  production path does not invoke it.

Forbidden scan log:
`/tmp/issue40-v5-r3-forbidden-broad-20260824.log`

## Protected recording/recognition async topology

Protected-file diff command:

```text
git diff --name-only -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift
```

Observed output: only `FeishuSpeech/Services/HotKeyService.swift`.

The zero-context topology marker scan over protected services, executor,
accessibility client, and view model found no changed recording/recognition
queue migration, `Task.detached`, synchronous MainActor wait, event-tap
replacement, or recorder `startRunning`/`stopRunning` topology. The HotKey
diff only advances the interference epoch on accessibility/tap failure and
normalizes whitespace.

Active source topology remained:

* `MainViewModel` retains independent `captureDrainTask` and `consumerTask`
  roots at lines 303-304 and starts them separately at lines 714-717.
* `AudioRecorder` retains distinct `audioQueue`, `bufferQueue`, and
  `sessionQueue`; session start/stop remains on `sessionQueue`.
* `FeishuStreamingSession` remains an actor.
* `ReviewSubmissionExecutor` owns a separate serial queue; MainActor admission
  calls `queue.async` and returns without waiting.
* A blocking-primitive scan over MainViewModel, AudioRecorder, and
  FeishuStreamingSession found no `DispatchSemaphore`, `dispatch_sync`,
  `semaphore_wait`, or `Thread.sleep`.

These are source/runtime checks of topology, not GUI/UAT or real-target
delivery evidence.

## Final process audit and evidence paths

Final exact process audit:

```text
ps -axo pid=,comm=,args= | awk '$2 ~ /FeishuSpeech|Siji\.FeishuSpeech|FeishuSpeechTests/ {print}'
```

Result: empty output, exit 0. No FeishuSpeech or XCTest process remained. No
standalone launch or install occurred.

All raw evidence paths:

* `/tmp/issue40-v5-r3-focused-20260824.log`
* `/tmp/issue40-v5-r3-focused-dd.txr2pr/Logs/Test/Test-FeishuSpeech-2026.08.24_16-57-14-+0800.xcresult`
* `/tmp/issue40-v5-r3-full-20260824.log`
* `/tmp/issue40-v5-r3-full-dd.5Rqixq/Logs/Test/Test-FeishuSpeech-2026.08.24_16-58-11-+0800.xcresult`
* `/tmp/issue40-v5-r3-debug-20260824.log`
* `/tmp/issue40-v5-r3-release-20260824.log`
* `/tmp/issue40-v5-r3-swiftlint-20260824.log`
* `/tmp/issue40-v5-r3-diff-check-20260824.log`
* `/tmp/issue40-v5-r3-forbidden-broad-20260824.log`

## Superseding verdict

**GREEN for the requested automated validation gates.** The authoritative
focused matrix is 321/321 with zero failures and zero skips; the full project
target is 534/534 executed with zero failures and exactly one documented
live-TCP skip; Debug and Release builds pass; SwiftLint strict and diff check
pass; forbidden output routes are absent from the accepted path; recording and
recognition retain their independent asynchronous topology; the exact current
changed-file inventory is recorded; and the application/test processes are
stopped. This verdict does not claim GUI/UAT or real third-party target
delivery.

---

# Superseding v5-r5 classification-fix final validation

Date: 2026-08-24 18:08 +0800
Role: read-only validation investigator

This section supersedes all preceding validation sections and verdicts. The
R5 classification-fix candidate was present before this run. No production,
test, project, or workflow-source file was edited by this investigator. No
standalone FeishuSpeech application was launched or installed; test hosts were
transient XCTest processes only.

## Setup and exact changed-file inventory

Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`.
`CLAUDE.md` was read in full before validation.

Environment: macOS 26.6.2 / build 25G83, Xcode 26.6 / 17F113, SwiftLint
0.65.0, arm64.

HEAD: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305`.

Exact commands:

```text
git status --short --branch
git diff --name-status
```

Observed inventory: 16 modified tracked files and one untracked Swift file:

```text
 M FeishuSpeech/Controllers/ReviewWindowController.swift
 M FeishuSpeech/Models/CursorTextModels.swift
 M FeishuSpeech/Models/TranscriptionReviewState.swift
 M FeishuSpeech/Services/AccessibilityClient.swift
 M FeishuSpeech/Services/CurrentFocusAppendSession.swift
 M FeishuSpeech/Services/HotKeyService.swift
 M FeishuSpeech/Services/ReviewDestinationDelivery.swift
 M FeishuSpeech/ViewModels/MainViewModel.swift
 M FeishuSpeech/Views/TranscriptionReviewView.swift
 M FeishuSpeechTests/FinalTextOutputSecurityTests.swift
 M FeishuSpeechTests/ReviewDestinationDeliveryTests.swift
 M FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift
 M FeishuSpeechTests/ReviewFirstMainViewModelTests.swift
 M FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift
 M FeishuSpeechTests/StreamingMainViewModelTests.swift
 M FeishuSpeechTests/TranscriptionReviewViewTests.swift
?? FeishuSpeech/Services/ReviewSubmissionExecutor.swift
```

Current `git diff --stat`: 16 tracked files, 8,447 insertions and 1,832
deletions. The untracked executor was compiled and linted.

## Focused 9-suite matrix

Fresh DerivedData: `/tmp/issue40-v5-r5-focused-dd.mf1T5q`.

Exact serialized command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r5-focused-dd.mf1T5q -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test > /tmp/issue40-v5-r5-focused-20260824.log 2>&1
```

Exit: 0. Raw log: `/tmp/issue40-v5-r5-focused-20260824.log`.

Result bundle:
`/tmp/issue40-v5-r5-focused-dd.mf1T5q/Logs/Test/Test-FeishuSpeech-2026.08.24_18-04-23-+0800.xcresult`

**324 tests executed, 0 failures, 0 skips** in 42.229 seconds (42.336
selected-tests aggregate); `** TEST SUCCEEDED **`.

Per-suite counts: CurrentFocusAppendSession 38, FinalTextOutputSecurity 68,
ReviewDestinationDelivery 13, ReviewFirstApplicationFallback 16,
ReviewFirstMainViewModel 34, ReviewWindowControllerReadiness 17,
StreamingMainViewModel 105, TranscriptionReviewViewKeyboard 19, and
TranscriptionReviewView 14. Every suite reported zero failures.

## Full project target

Fresh DerivedData: `/tmp/issue40-v5-r5-full-dd.FmyfPc`.

Exact serialized command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r5-full-dd.FmyfPc -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test > /tmp/issue40-v5-r5-full-20260824.log 2>&1
```

Exit: 0. Raw log: `/tmp/issue40-v5-r5-full-20260824.log`.

Result bundle:
`/tmp/issue40-v5-r5-full-dd.FmyfPc/Logs/Test/Test-FeishuSpeech-2026.08.24_18-05-31-+0800.xcresult`

**537 tests executed, 0 failures, 1 test skipped** in 56.860 seconds (57.051
all-tests aggregate); `** TEST SUCCEEDED **`.

The sole expected skip was:

```text
DirectFeishuKeepAliveSessionTests/test_liveKeepAliveTCPIsNotOnVPNTunnelAddress
Test skipped - live TCP previously hung the XCTest host; issue #34 forbids additional live sockets
```

No other skip, failure, or interruption occurred.

## Debug, Release, strict lint, and diff check

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/issue40-v5-r5-debug-dd.236yUD build > /tmp/issue40-v5-r5-debug-20260824.log 2>&1
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/issue40-v5-r5-release-dd.Y4NYiz build > /tmp/issue40-v5-r5-release-20260824.log 2>&1
swiftlint --strict > /tmp/issue40-v5-r5-swiftlint-20260824.log 2>&1
git diff --check > /tmp/issue40-v5-r5-diff-check-20260824.log 2>&1
```

All four exited 0. Debug and Release both reported `** BUILD SUCCEEDED **`;
their logs contained 32 and 26 non-fatal warning diagnostics respectively.
SwiftLint reported `Done linting! Found 0 violations, 0 serious in 36 files.`
The diff-check log is 0 bytes with no output. No product was opened, copied to
`/Applications`, or installed.

## Forbidden output-route checks

Exact scan:

```text
for file in FeishuSpeech/Services/ReviewSubmissionExecutor.swift FeishuSpeech/Models/CursorTextModels.swift FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Controllers/ReviewWindowController.swift; do printf 'FILE=%s\n' "$file"; rg -n -i 'NSPasteboard|generalPasteboard|changeCount|Cmd.?V|command.?V|NSWorkspace\.shared\..*activate|\.activate\(|activateIgnoringOtherApps|retarget|CurrentFocusProvisionalOutputSession|insertAtCurrentFocusOnce|ReviewOutputCompatibilityWriter|ReviewOutputCompatibilityPoster' "$file" || true; done
rg -n -i 'NSPasteboard|generalPasteboard|changeCount|clearContents|setString\(|setData\(|writeObjects|readObjects|pasteboardItems|public\.png|Apple PNG|Cmd.?V|command.?V' FeishuSpeech --glob '*.swift' > /tmp/issue40-v5-r5-forbidden-broad-20260824.log || true
```

The broad production Swift scan produced 0 match lines. The default path uses
`SystemReviewSubmissionFacade()` at `MainViewModel.swift:375`, captures
`.production(descriptor)` at line 808, issues one handle at line 2186, creates
one envelope at line 2203, and enqueues it at line 2210. The executor posts
only the prepared Unicode pair to the captured PID after admission and has no
clipboard, Cmd+V, activation, or ambient retarget operation. The legacy branch
is reachable only with an explicit legacy delivery dependency; the default
accepted path sets that dependency to nil.

Forbidden scan log:
`/tmp/issue40-v5-r5-forbidden-broad-20260824.log`

## Protected recording/recognition async topology

Exact protected-file command:

```text
git diff --name-only -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift
```

Observed output: only `FeishuSpeech/Services/HotKeyService.swift`.

The topology marker scan found no changed recording/recognition queue migration,
`Task.detached`, synchronous MainActor wait, event-tap replacement, or recorder
`startRunning`/`stopRunning` topology. `MainViewModel` retains independent
`captureDrainTask` and `consumerTask` roots (lines 303-304, started separately
at 714-717); AudioRecorder retains distinct `audioQueue`, `bufferQueue`, and
`sessionQueue`; FeishuStreamingSession remains an actor; and
ReviewSubmissionExecutor owns a separate serial queue with non-blocking
MainActor admission. The blocking-primitive scan over MainViewModel,
AudioRecorder, and FeishuStreamingSession found no `DispatchSemaphore`,
`dispatch_sync`, `semaphore_wait`, or `Thread.sleep`.

## Final stopped-process audit and raw evidence

Exact audit:

```text
ps -axo pid=,comm=,args= | awk '$2 ~ /FeishuSpeech|Siji\.FeishuSpeech|FeishuSpeechTests/ {print}'
```

Result: empty output, exit 0. No FeishuSpeech or XCTest process remained. No
standalone launch or install occurred.

Raw paths:

* `/tmp/issue40-v5-r5-focused-20260824.log`
* `/tmp/issue40-v5-r5-focused-dd.mf1T5q/Logs/Test/Test-FeishuSpeech-2026.08.24_18-04-23-+0800.xcresult`
* `/tmp/issue40-v5-r5-full-20260824.log`
* `/tmp/issue40-v5-r5-full-dd.FmyfPc/Logs/Test/Test-FeishuSpeech-2026.08.24_18-05-31-+0800.xcresult`
* `/tmp/issue40-v5-r5-debug-20260824.log`
* `/tmp/issue40-v5-r5-release-20260824.log`
* `/tmp/issue40-v5-r5-swiftlint-20260824.log`
* `/tmp/issue40-v5-r5-diff-check-20260824.log`
* `/tmp/issue40-v5-r5-forbidden-broad-20260824.log`

## Superseding verdict

**GREEN for the requested R5 automated validation gates.** Focused is 324/324
with zero failures and zero skips; the full target is 537/537 executed with
zero failures and exactly one documented live-TCP skip; Debug and Release
builds pass; strict lint and diff check pass; forbidden output routes are
absent from the accepted path; recording and recognition retain independent
asynchronous topology; the exact changed-file inventory is recorded; and all
FeishuSpeech/XCTest processes are stopped. This does not claim GUI/UAT or real
third-party target delivery.

---

# Latest superseding section: v5-r5 classification-fix final validation

Date: 2026-08-24 18:08 +0800. This is the latest section and supersedes the
historical R4 section immediately above. It records the R5 rerun performed
read-only at HEAD `b321ac5d6c04c91ced9afeb2240f9566d9b8d305` in
`/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40` on macOS
26.6.2 / Xcode 26.6 (17F113) / SwiftLint 0.65.0 arm64. `CLAUDE.md` was read
in full. No source/test edit, install, or standalone app launch was performed.

Exact focused command (fresh DerivedData `/tmp/issue40-v5-r5-focused-dd.mf1T5q`):

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r5-focused-dd.mf1T5q -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test > /tmp/issue40-v5-r5-focused-20260824.log 2>&1
```

Exit 0; result bundle
`/tmp/issue40-v5-r5-focused-dd.mf1T5q/Logs/Test/Test-FeishuSpeech-2026.08.24_18-04-23-+0800.xcresult`.
Result: **324 tests, 0 failures, 0 skips**, 42.229s; `TEST SUCCEEDED`.

Exact full-target command (fresh DerivedData `/tmp/issue40-v5-r5-full-dd.FmyfPc`):

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r5-full-dd.FmyfPc -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test > /tmp/issue40-v5-r5-full-20260824.log 2>&1
```

Exit 0; result bundle
`/tmp/issue40-v5-r5-full-dd.FmyfPc/Logs/Test/Test-FeishuSpeech-2026.08.24_18-05-31-+0800.xcresult`.
Result: **537 tests, 0 failures, 1 expected skip**, 56.860s; the only skip is
`DirectFeishuKeepAliveSessionTests/test_liveKeepAliveTCPIsNotOnVPNTunnelAddress`
because issue #34 forbids additional live sockets.

Exact remaining gate commands and outcomes:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/issue40-v5-r5-debug-dd.236yUD build > /tmp/issue40-v5-r5-debug-20260824.log 2>&1
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/issue40-v5-r5-release-dd.Y4NYiz build > /tmp/issue40-v5-r5-release-20260824.log 2>&1
swiftlint --strict > /tmp/issue40-v5-r5-swiftlint-20260824.log 2>&1
git diff --check > /tmp/issue40-v5-r5-diff-check-20260824.log 2>&1
```

All exited 0; both builds reported `BUILD SUCCEEDED`; strict lint reported 0
violations in 36 files; diff check produced an empty log. The forbidden-route
scan at `/tmp/issue40-v5-r5-forbidden-broad-20260824.log` produced 0 broad
production matches. The accepted path remains
`SystemReviewSubmissionFacade` → captured `.production` target → one handle →
one admission envelope → fixed-PID Unicode pair; no clipboard/Cmd+V,
activation, ambient retarget, or default legacy direct output was found.

Protected topology is unchanged: only `HotKeyService.swift` is in the
protected-file diff; `captureDrainTask` and `consumerTask` remain independent;
AudioRecorder retains separate audio/buffer/session queues;
`FeishuStreamingSession` remains an actor; and the executor uses its own
serial queue with non-blocking MainActor admission. No blocking primitive was
found in MainViewModel, AudioRecorder, or FeishuStreamingSession.

The exact R5 changed-file inventory is the 16 modified tracked files plus
untracked `FeishuSpeech/Services/ReviewSubmissionExecutor.swift`, with
`git diff --stat` at 8,447 insertions and 1,832 deletions. Final audit:

```text
ps -axo pid=,comm=,args= | awk '$2 ~ /FeishuSpeech|Siji\.FeishuSpeech|FeishuSpeechTests/ {print}'
```

Output was empty, exit 0. **Latest verdict: GREEN for all requested automated
R5 gates; no FeishuSpeech/XCTest process remains.** This remains an automated
validation result only, with no GUI/UAT or real-target delivery claim.

---

# Superseding v5-r4 post-fix final validation

Date: 2026-08-24 17:33 +0800
Role: read-only validation investigator

This section supersedes all preceding validation sections and verdicts. The
candidate was already in its R4 post-fix state when this run began. No
production, test, project, or workflow-source file was edited by this
investigator. No standalone FeishuSpeech application was launched or
installed; only transient XCTest hosts were created by the test commands.

## Setup, identity, and changed-file inventory

Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`.
`CLAUDE.md` was read in full before validation.

Environment: macOS 26.6.2 / build 25G83, Xcode 26.6 / 17F113, SwiftLint
0.65.0, arm64.

HEAD: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305`.

Exact inventory commands:

```text
git status --short --branch
git diff --name-status
```

Observed inventory: 16 modified tracked files and one untracked Swift file:

```text
 M FeishuSpeech/Controllers/ReviewWindowController.swift
 M FeishuSpeech/Models/CursorTextModels.swift
 M FeishuSpeech/Models/TranscriptionReviewState.swift
 M FeishuSpeech/Services/AccessibilityClient.swift
 M FeishuSpeech/Services/CurrentFocusAppendSession.swift
 M FeishuSpeech/Services/HotKeyService.swift
 M FeishuSpeech/Services/ReviewDestinationDelivery.swift
 M FeishuSpeech/ViewModels/MainViewModel.swift
 M FeishuSpeech/Views/TranscriptionReviewView.swift
 M FeishuSpeechTests/FinalTextOutputSecurityTests.swift
 M FeishuSpeechTests/ReviewDestinationDeliveryTests.swift
 M FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift
 M FeishuSpeechTests/ReviewFirstMainViewModelTests.swift
 M FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift
 M FeishuSpeechTests/StreamingMainViewModelTests.swift
 M FeishuSpeechTests/TranscriptionReviewViewTests.swift
?? FeishuSpeech/Services/ReviewSubmissionExecutor.swift
```

`git diff --stat` reported 16 tracked files, 8,105 insertions and 1,845
deletions. The untracked executor was included in build and lint inputs.

## Authoritative 9-suite focused matrix

Fresh DerivedData: `/tmp/issue40-v5-r4-focused-dd.l1Z53S`.

Exact serialized command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r4-focused-dd.l1Z53S -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test > /tmp/issue40-v5-r4-focused-20260824.log 2>&1
```

Exit: 0. Raw log: `/tmp/issue40-v5-r4-focused-20260824.log`.

Result bundle:
`/tmp/issue40-v5-r4-focused-dd.l1Z53S/Logs/Test/Test-FeishuSpeech-2026.08.24_17-30-25-+0800.xcresult`

**324 tests executed, 0 failures, 0 skips** in 34.556 seconds (34.670
selected-tests aggregate); `** TEST SUCCEEDED **`.

Per-suite counts: CurrentFocusAppendSession 38, FinalTextOutputSecurity 68,
ReviewDestinationDelivery 13, ReviewFirstApplicationFallback 16,
ReviewFirstMainViewModel 34, ReviewWindowControllerReadiness 17,
StreamingMainViewModel 105, TranscriptionReviewViewKeyboard 19, and
TranscriptionReviewView 14. Every suite reported zero failures.

## Full project test target

Fresh DerivedData: `/tmp/issue40-v5-r4-full-dd.hwGI5U`.

Exact serialized command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-v5-r4-full-dd.hwGI5U -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test > /tmp/issue40-v5-r4-full-20260824.log 2>&1
```

Exit: 0. Raw log: `/tmp/issue40-v5-r4-full-20260824.log`.

Result bundle:
`/tmp/issue40-v5-r4-full-dd.hwGI5U/Logs/Test/Test-FeishuSpeech-2026.08.24_17-31-29-+0800.xcresult`

**537 tests executed, 0 failures, 1 test skipped** in 52.892 seconds (53.071
all-tests aggregate); `** TEST SUCCEEDED **`.

The sole expected skip is:

```text
DirectFeishuKeepAliveSessionTests/test_liveKeepAliveTCPIsNotOnVPNTunnelAddress
Test skipped - live TCP previously hung the XCTest host; issue #34 forbids additional live sockets
```

No other skip, failure, or interruption occurred.

## Debug, Release, lint, and diff checks

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/issue40-v5-r4-debug-dd.AWks6U build > /tmp/issue40-v5-r4-debug-20260824.log 2>&1
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/issue40-v5-r4-release-dd.cPRT9b build > /tmp/issue40-v5-r4-release-20260824.log 2>&1
swiftlint --strict > /tmp/issue40-v5-r4-swiftlint-20260824.log 2>&1
git diff --check > /tmp/issue40-v5-r4-diff-check-20260824.log 2>&1
```

All four exited 0. Debug and Release both reported `** BUILD SUCCEEDED **`;
build logs contain 32 and 26 non-fatal warnings respectively. SwiftLint
reported `Done linting! Found 0 violations, 0 serious in 36 files.` The diff
check log is 0 bytes with no output. No built product was opened, copied to
`/Applications`, or installed.

## Forbidden output-route checks

The accepted review path and complete production Swift tree were scanned with:

```text
for file in FeishuSpeech/Services/ReviewSubmissionExecutor.swift FeishuSpeech/Models/CursorTextModels.swift FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Controllers/ReviewWindowController.swift; do printf 'FILE=%s\n' "$file"; rg -n -i 'NSPasteboard|generalPasteboard|changeCount|Cmd.?V|command.?V|NSWorkspace\.shared\..*activate|\.activate\(|activateIgnoringOtherApps|retarget|CurrentFocusProvisionalOutputSession|insertAtCurrentFocusOnce|ReviewOutputCompatibilityWriter|ReviewOutputCompatibilityPoster' "$file" || true; done
rg -n -i 'NSPasteboard|generalPasteboard|changeCount|clearContents|setString\(|setData\(|writeObjects|readObjects|pasteboardItems|public\.png|Apple PNG|Cmd.?V|command.?V' FeishuSpeech --glob '*.swift' > /tmp/issue40-v5-r4-forbidden-broad-20260824.log || true
```

The broad production Swift scan produced 0 match lines. The default path uses
`SystemReviewSubmissionFacade()` (`MainViewModel.swift:375`), captures
`.production(descriptor)` (line 808), issues one handle (line 2186), creates
one envelope (line 2203), and enqueues it (line 2210). The executor posts only
the prepared Unicode pair to the captured PID after admission. It has no
clipboard, Cmd+V, activation, or ambient retarget operation. The source-
compatible legacy branch is reachable only with an explicitly injected legacy
delivery dependency; the default accepted path sets it to nil.

Forbidden scan log:
`/tmp/issue40-v5-r4-forbidden-broad-20260824.log`

## Protected recording/recognition asynchronous topology

Exact protected-file command:

```text
git diff --name-only -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift
```

Observed output: only `FeishuSpeech/Services/HotKeyService.swift`.

The topology marker scan found no changed recording/recognition queue migration,
`Task.detached`, synchronous MainActor wait, event-tap replacement, or recorder
`startRunning`/`stopRunning` topology. HotKeyService only advances the
interference epoch on accessibility/tap failure and normalizes whitespace.
`MainViewModel` retains independent `captureDrainTask` and `consumerTask`
roots (lines 303-304, started separately at 714-717); AudioRecorder retains
distinct `audioQueue`, `bufferQueue`, and `sessionQueue`; and
FeishuStreamingSession remains an actor. ReviewSubmissionExecutor owns a
separate serial queue and MainActor admission uses `queue.async` without
waiting. A blocking-primitive scan over MainViewModel, AudioRecorder, and
FeishuStreamingSession found no `DispatchSemaphore`, `dispatch_sync`,
`semaphore_wait`, or `Thread.sleep`.

## Final stopped-process audit and evidence

Exact final audit:

```text
ps -axo pid=,comm=,args= | awk '$2 ~ /FeishuSpeech|Siji\.FeishuSpeech|FeishuSpeechTests/ {print}'
```

Result: empty output, exit 0. No FeishuSpeech or XCTest process remained. No
standalone launch or install occurred.

Raw evidence paths:

* `/tmp/issue40-v5-r4-focused-20260824.log`
* `/tmp/issue40-v5-r4-focused-dd.l1Z53S/Logs/Test/Test-FeishuSpeech-2026.08.24_17-30-25-+0800.xcresult`
* `/tmp/issue40-v5-r4-full-20260824.log`
* `/tmp/issue40-v5-r4-full-dd.hwGI5U/Logs/Test/Test-FeishuSpeech-2026.08.24_17-31-29-+0800.xcresult`
* `/tmp/issue40-v5-r4-debug-20260824.log`
* `/tmp/issue40-v5-r4-release-20260824.log`
* `/tmp/issue40-v5-r4-swiftlint-20260824.log`
* `/tmp/issue40-v5-r4-diff-check-20260824.log`
* `/tmp/issue40-v5-r4-forbidden-broad-20260824.log`

## Superseding verdict

**GREEN for the requested R4 automated validation gates.** Focused is 324/324
with zero failures and zero skips; the full target is 537/537 executed with
zero failures and exactly one documented live-TCP skip; Debug and Release
builds pass; SwiftLint strict and diff check pass; forbidden output routes are
absent from the accepted path; recording and recognition retain independent
asynchronous topology; the exact changed-file inventory is recorded; and all
FeishuSpeech/XCTest processes are stopped. This does not claim GUI/UAT or real
third-party target delivery.

---

# Final R5 tail verdict (latest)

The R5 classification-fix rerun is the latest validation result. Its exact
commands, counts, result bundles, raw logs, changed inventory, forbidden-route
scan, topology scan, and process audit are recorded in the immediately
preceding `Latest superseding section: v5-r5 classification-fix final
validation` above. The measured result remains **GREEN**: focused 324/324,
full 537/537 with exactly one documented live-TCP skip, Debug/Release builds
successful, strict lint and diff check successful, no forbidden accepted-route
output behavior, preserved recording/recognition async separation, and zero
remaining FeishuSpeech/XCTest processes. No GUI/UAT or real-target delivery
claim is made.

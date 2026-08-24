# Issue #40 v5 — isolated Send-click hang diagnosis

Date: 2026-08-24 (Asia/Shanghai)

## Scope and baseline

This is a read-only diagnosis of the single selector
`ReviewFirstMainViewModelTests/test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend`.
No production or test file was edited. No standalone FeishuSpeech application
was launched or installed. The two `xcodebuild test` invocations below created
transient test hosts only; the final process check found no FeishuSpeech,
Siji.FeishuSpeech, or FeishuSpeechTests process.

Worktree:
`/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`

HEAD:
`b321ac5d6c04c91ced9afeb2240f9566d9b8d305`

Environment: macOS 26.6.2 (arm64), Xcode 26.6 (17F113), SwiftLint 0.65.0.
`CLAUDE.md` was read in full before investigation.

## Reproduction commands and raw evidence

### First isolated run

Command, verbatim:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-send-click-hang-dd.hp0UP1 -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend test > /tmp/issue40-send-click-test-hang-20260824-1505.log 2>&1
```

Outcome: exit 0. The selector passed in 26.212 seconds. Result bundle:

`/tmp/issue40-send-click-hang-dd.hp0UP1/Logs/Test/Test-FeishuSpeech-2026.08.24_15-07-03-+0800.xcresult`

Raw log: `/tmp/issue40-send-click-test-hang-20260824-1505.log` (1,666 lines).

Relevant raw result:

```text
Test Case '-[FeishuSpeechTests.ReviewFirstMainViewModelTests test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend]' passed (26.212 seconds).
Executed 1 test, with 0 failures (0 unexpected) in 26.212 (26.214) seconds
** TEST SUCCEEDED **
```

While this run was in the synchronous mouse route, a five-second `sample`
capture was taken from test-host PID 27835:

```text
sample 27835 5 1 > /tmp/issue40-send-click-sample-20260824-1507.txt 2>&1
```

Sample: `/tmp/issue40-send-click-sample-20260824-1507.txt` (1,188 lines).

### Bounded watchdog run

Clean DerivedData: `/tmp/issue40-send-click-bounded-dd.VD1k6U`.

Command, verbatim:

```text
perl -e '$SIG{ALRM}=sub { exit 124 }; alarm 40; exec @ARGV' xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination platform=macOS -derivedDataPath /tmp/issue40-send-click-bounded-dd.VD1k6U -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend test > /tmp/issue40-send-click-bounded-20260824-1508.log 2>&1
```

Outcome: exit 142 (the 40-second alarm terminated the wrapper/process). The
test began at 15:08:39.061 and reported `review focus ready` at 15:08:39.156,
but never emitted a test completion or result. No completed xcresult was
produced for this watchdog run.

Raw log: `/tmp/issue40-send-click-bounded-20260824-1508.log` (1,640 lines).

At about 15:08:43, while the selector was still in the same route, a five-
second `sample` capture was taken from test-host PID 30726:

```text
sample 30726 5 1 > /tmp/issue40-send-click-bounded-sample-20260824-1508.txt 2>&1
```

Sample: `/tmp/issue40-send-click-bounded-sample-20260824-1508.txt` (1,234
lines).

The watchdog left no FeishuSpeech-related process running. The process check
used after cleanup was:

```text
ps -axo pid=,comm=,args= | awk '$2 ~ /FeishuSpeech|Siji\.FeishuSpeech|FeishuSpeechTests/ {print}'
```

Result: empty.

## Observation table

| Measurement | Command/evidence | Result | Exit |
|---|---|---|---:|
| Isolated selector, first run | `xcodebuild ... -derivedDataPath /tmp/issue40-send-click-hang-dd.hp0UP1 ... -only-testing:...test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend test` | 1 executed, 0 failures, 26.212 s; result bundle above | 0 |
| Main-thread sample, first run | `sample 27835 5 1` | `invokeConfirm` → `invokeSend` → `issue40PerformRealSendClick` → `ReviewPanel.sendEvent` → AppKit `NSTextView mouseDown` → `_bellerophonTrackMouse...` → `nextEventMatchingMask` → `mach_msg` | 0 |
| Isolated selector, bounded run | `perl ... alarm 40 ... xcodebuild ... -derivedDataPath /tmp/issue40-send-click-bounded-dd.VD1k6U ...` | Started and reached `review focus ready`; no completion before watchdog | 142 |
| Main-thread sample, bounded run | `sample 30726 5 1` | Same synchronous AppKit event-tracking stack; 4,371 of the captured samples were at `mach_msg` from that path | 0 |
| Standalone app/process residue | `ps ... | awk ...` | No matching process after both runs | 0 |

The first run therefore proves the selector can eventually complete; the
bounded run proves the same isolated route can remain blocked beyond 40
seconds. This is a reproduction of a timing-dependent stall, not a
deterministic assertion failure.

## Call-stack and source trace

The bounded sample's main stack was:

```text
ReviewFirstMainViewModelTests.test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend()
  ReviewFirstMainViewModelTests.swift:394
  Issue40ProductionReviewSurfacePresenter.invokeConfirm()
  ReviewFirstMainViewModelTests.swift:1855
  Issue40ProductionReviewSurfacePresenter.invokeSend()
  ReviewFirstMainViewModelTests.swift:1882
  issue40PerformRealSendClick(on:contentY:)
  ReviewWindowControllerReadinessTests.swift:56
  ReviewPanel.sendEvent(_:)
  ReviewWindowController.swift:84
  -[NSWindow(NSEventRouting) sendEvent:]
  -[NSWindow _reallySendEvent:isDelayedEvent:]
  -[NSWindow _handleMouseDownEvent:isDelayedEvent:]
  -[NSTextView mouseDown:]
  -[NSTextView _bellerophonTrackMouseWithMouseDownEvent:...]
  -[NSApplication nextEventMatchingMask:untilDate:inMode:dequeue:]
  _DPSBlockUntilNextEventMatchingListInMode
  mach_msg
```

The source path is consistent with that sample:

* `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:1853-1856` makes
  `invokeConfirm()` call `invokeSend()`.
* `.../ReviewFirstMainViewModelTests.swift:1871-1889` synchronously probes
  the Send-control band and calls the real mouse helper at line 1882.
* `FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift:8-11` marks
  that helper `@MainActor`; lines 31-52 create mouse-down/up events and lines
  56-57 call `panel.sendEvent(down)` followed by `panel.sendEvent(up)`.
* `FeishuSpeech/Controllers/ReviewWindowController.swift:79-85` only handles
  Return specially; a mouse event falls through to `super.sendEvent(event)`.
  Consequently the captured frame is AppKit's normal mouse routing, not a
  production submission lock.

The first event is synchronously sent before the next statement can send the
mouse-up. AppKit routes the down event to `NSTextView.mouseDown`, which enters
its private tracking loop and waits in `nextEventMatchingMask`/`mach_msg`.
The helper is itself running on the main actor. The sample contains no
`ReviewSubmissionExecutor`, facade admission, committer, AX delivery, or
production confirmation frame below `ReviewPanel.sendEvent`.

For contrast, when the event helper does return, the production boundary is
the expected one: `FeishuSpeech/ViewModels/MainViewModel.swift:2183-2210`
issues one facade handle and enqueues one admission envelope. The executor
states at `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:594-597`
that raw submission is serial-queue confined and does not activate or retarget;
`.../ReviewSubmissionExecutor.swift:914-929` uses the captured target PID.
Those frames are not present in the blocked sample because the mouse gesture
has not returned to the confirmation callback.

## Comparison with earlier green evidence

`kaola-workflow/issue-40/test-green-v5.md:459-475` records an earlier isolated
four-selector run containing this exact selector: 4 tests executed, 0
failures, result bundle `...14-14-51-+0800.xcresult`.

The same document's canonical focused matrix at lines 532-565 records 306
tests executed with 0 failures, including this selector in the 33-test
`ReviewFirstMainViewModelTests` suite. The current first isolated run also
passed, while the immediately repeated clean watchdog run exceeded 40 seconds.
This history rules out “the selector has always been broken” and does not, by
itself, establish a production regression.

## Narrowing and classification

1. **Production-facade/deadlock hypothesis (a): not supported by the sample.**
   The blocked stack stops at `ReviewPanel.sendEvent`/AppKit before the
   confirmation callback returns. No executor queue, control-plane lock,
   admission, AX delivery, or output helper is on the blocked stack. The same
   source passed in 26.212 seconds in the first run.

2. **Synchronous AppKit event-helper stall (b): supported and the primary
   classification.** The helper calls `panel.sendEvent(down)` synchronously
   while the key review panel's editor can receive the event. The sample
   repeatedly shows `NSTextView.mouseDown`'s tracking loop waiting for the next
   event. The helper cannot execute its following `sendEvent(up)` until that
   synchronous call returns, which explains the observed long stall.

3. **Deterministic lifecycle issue (c): not primary; timing is a secondary
   manifestation.** The first isolated attempt passed and the second exceeded
   the bound under the same source and selector. That is nondeterministic
   timing around AppKit event tracking, rather than a deterministic terminal
   state or production-lifecycle assertion. A subsequent run could still vary
   with window/event-loop timing.

## Recommended owner and minimal correction

Owner: the test/UI event-fixture lane owning
`issue40PerformRealSendClick`, with AppKit review-surface ownership consulted
if a production-safe test seam is required.

Minimal correction to evaluate (not implemented here): do not synchronously
inject a mouse-down into a potentially editor-hit `NSPanel` and then rely on a
later synchronous mouse-up. Either enqueue a paired event sequence through the
AppKit event loop before processing, or use a narrow, production-equivalent
Send-control action seam that preserves the opaque confirmation boundary. If
the real coordinate route is retained, hit-test/verify the measured control
before sending and fail/skip the helper rather than sending a mouse-down to an
`NSTextView`. Any correction should remain outside the production submission
contract unless the owning UI reviewer proves a production change is necessary;
it must not bypass the one-time confirmation/admission boundary.

## Limits and verdict

The `sample` output is a stack/time measurement, not a GUI/UAT result. No
external target application was activated, no real text was delivered, and no
clipboard or Cmd+V behavior was exercised by this diagnosis. The test host
was transient and is stopped.

**Verdict:** the evidence supports **(b) synchronous AppKit event-helper
stall**, with timing-dependent behavior as a secondary **(c)** characteristic;
it does **not** support classifying the incident as a production facade or
`ReviewSubmissionExecutor` deadlock (**(a)**).

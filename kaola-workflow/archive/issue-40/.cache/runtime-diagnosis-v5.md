# Issue #40 v5 runtime diagnosis: Send deadlock and Return/focus boundary

Date: 2026-08-24 (Asia/Shanghai)

Role: read-only investigator

Scope: installed v4 Release UAT failure reported as “Send shows sending and stops
responding; Return does not work when the preview has focus.” The application was
already stopped. No application launch, install, clipboard mutation, target-app
interaction, or tracked repository edit was performed by this investigation.

## Setup and baseline

| Measurement | Exact command | Result | Exit |
|---|---|---|---:|
| Worktree status | `git status --short --branch` | `## workflow/issue-40...origin/workflow/issue-40` (clean) | 0 |
| Source revision | `git rev-parse HEAD` | `b321ac5d6c04c91ced9afeb2240f9566d9b8d305` | 0 |
| Environment | `sw_vers; uname -a; xcodebuild -version` | macOS 26.6.2 / 25G83, arm64; Xcode 26.6 / 17F113 | 0 |
| Stopped-app check | `pgrep -x FeishuSpeech` | no matching process; this is the expected stopped state | 1 |
| Supplied runtime artifact | `stat -f 'path=%N size=%z bytes modified=%Sm' ...sample.txt` | 214,733 bytes; modified `2026-08-24T08:47:37+0800` | 0 |
| Artifact identity | `shasum -a 256 /tmp/FeishuSpeech_2026-08-24_084734_25BZ.sample.txt` | `d2e8399687c8001ba1e3bc92b7df8ca81e4f3b2390421fcb40319735b9ebd6a0` | 0 |

The sample header identifies `/Applications/FeishuSpeech.app`, PID `99976`,
identifier `Siji.FeishuSpeech`, launched at `08:43:03.620`, sampled from
`08:47:34.122`, every 1 ms, on the same macOS build.

The unified-log query below returned zero application records for the relevant
interval. This is an absence of logging evidence, not evidence that no UI event
occurred:

```text
/usr/bin/log show --style compact --start '2026-08-24 08:46:30' \
  --end '2026-08-24 08:48:30' \
  --predicate 'process == "FeishuSpeech" AND subsystem == "com.feishuspeech.app"' \
  | tail -n +2 | wc -l
=> 0
exit: 0
```

## Observation table

| Measurement | Command/source | Result | Exit |
|---|---|---|---:|
| Main-thread sample | `sed -n '1,74p' /tmp/FeishuSpeech_2026-08-24_084734_25BZ.sample.txt` | All `2620` samples stop at `CurrentFocusInputInterferenceEpoch.value` waiting in `__psynch_mutexwait`. The stack is `MainViewModel.handleReviewConfirmation` -> `SystemReviewDestinationDelivery.deliver` -> `deliverAfterActivation` -> `insertReviewText` -> `SystemFinalTextOutput.insertReviewPair` -> `ReviewDeliveryMonitoringSession.performFinalPair` -> `WorkspaceCurrentFocusInputMonitor.postComplete...` -> closure -> `interferenceEpoch.getter` -> mutex wait. | 0 |
| Hotkey-tap sample | same artifact | All `2620` samples of `com.feishuspeech.hotkey.tap` stop at `HotKeyService.handleEvent` -> `CurrentFocusInputInterferenceEpoch.observePreDispatch` -> mutex wait. | 0 |
| Deadlock persistence | sample count | The same two blocked stacks are present for every 1-ms sample (`2620` observations); this is a persistent stall, not a transient slow API call. | n/a |
| Pasteboard symbols in reviewed production path | `rg -n 'NSPasteboard|changeCount|setString|clearContents|setData|writeObjects|readObjects|pasteboardItems|public\.png' FeishuSpeech/Services/TextInputSimulator.swift FeishuSpeech/Services/ReviewDestinationDelivery.swift FeishuSpeech/ViewModels/MainViewModel.swift` | No matches. The remaining pasteboard-named types are empty compatibility markers only. | 1 |
| Unicode post calls | `rg -n 'postUnicodeEvent|postToPid' FeishuSpeech/Services/TextInputSimulator.swift` | Construction/readback occurs before the pair gate (`:775-838`); the actual down/up calls are only `:856` and `:864`, inside the closure passed to the gate. | 0 |
| AX setter locations | `rg -n 'AXUIElementSetAttributeValue|restoreAndValidateBeforeDelivery|setSelectedText\(' FeishuSpeech/Services/AccessibilityClient.swift FeishuSpeech/Services/ReviewDestinationDelivery.swift` | AX setters exist for exact-cursor focus/range restoration (`AccessibilityClient.swift:262,268,474-486`), but the application-current-focus composite sample is read-only (`ReviewDestinationDelivery.swift:801-833`). The sample does not identify the captured binding. | 0 |

## Reproduction status

The Send failure is reproduced by the supplied live-process sample and proved by
source correlation. The app’s main actor is in the confirmation task, but the task
cannot return to `completeReviewDelivery`; it is blocked synchronously inside the
final-pair gate. Therefore the view remains in `.confirming`, where
`TranscriptionReviewView` renders “正在发送…” and disables the editable controls.

Return was not independently reproduced with a live GUI after the app was stopped.
Its source path and focus prerequisites are deterministic and are described below;
the runtime artifact contains no custom application log records for a Return event.

## Narrowing leg 1: exact deadlock mechanism

The production lock and the production gate form a reentrant self-deadlock:

1. `CurrentFocusInputInterferenceEpoch.performIfUnchanged` acquires its
   non-recursive `NSLock` and invokes `operation()` while retaining the lock
   (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:176-202`).
2. `WorkspaceCurrentFocusInputMonitor.postCompleteSyntheticPairIfInterferenceEpochIsUnchanged`
   delegates directly to that method (`:765-773`).
3. `ReviewDeliveryMonitoringSession.performFinalPair` supplies a closure to that
   gate (`FeishuSpeech/Services/ReviewDestinationDelivery.swift:387-409`).
4. Before calling `postPair()`, the closure reads
   `inputMonitor.interferenceEpoch` at `:392-394`.
5. The concrete monitor’s getter calls `CurrentFocusInputInterferenceEpoch.shared.value`
   (`CurrentFocusAppendSession.swift:738-742`), and `value` tries to acquire the
   same `NSLock` (`:183-187`). The main actor therefore waits on a lock it already
   holds.
6. The event-tap thread concurrently reaches `observePreDispatch` from
   `HotKeyService.handleEvent` (`HotKeyService.swift:200-203`), then calls
   `advance()` (`CurrentFocusAppendSession.swift:204-221`) and waits on that same
   lock. This matches the second stack in all 2620 sample observations.

This is not an activation timeout, recognition stall, recorder barrier stall, or
network retry. Those stages are above the blocked stack. The deadlock occurs after
activation and after event preparation, at the final physical-input epoch gate.

## Narrowing leg 2: what did and did not reach the external-output boundary

Observed/source-supported facts for the sampled Send attempt:

- `SystemFinalTextOutput.insertReviewPair` is entered, and the pair gate is entered.
- The gate’s closure blocks at the nested `inputMonitor.interferenceEpoch` read
  before line `ReviewDestinationDelivery.swift:407` can call `postPair()`.
- `SystemFinalTextCurrentFocusEventPoster.submitReviewUnicodePair` calls the actual
  Unicode down and up only inside `postPair()` (`TextInputSimulator.swift:841-880`,
  especially `:856` and `:864`). The sampled attempt therefore did not reach either
  `postUnicodeEvent` call, so no Unicode key-down/key-up pair from that attempt was
  posted by FeishuSpeech.
- v4’s accepted review path contains no pasteboard read, write, snapshot, restore,
  copy, paste, `Cmd+V`, or image-paste operation. The structural search returned no
  pasteboard symbols in the reviewed production path. The earlier residual-image
  mechanism is not present in this candidate.
- The application-current-focus preflight reads Accessibility trust, Secure Input,
  frontmost PID, running identity, and frontmost identity; it has no AX setter
  (`ReviewDestinationDelivery.swift:794-834`). If the captured binding was
  application-current-focus, no AX write is reachable before this deadlock.

One binding-specific fact remains unobservable from this sample: an exact-cursor
binding executes `restoreAndValidateBeforeDelivery` before entering
`insertReviewPair` (`ReviewDestinationDelivery.swift:637-651, 741-756`). That
routine can set the target’s focused attribute and selected range
(`AccessibilityClient.swift:245-276`) before the final gate. The sample does not
record whether the destination was `.exactCursor` or `.applicationCurrentFocus`,
so an exact-cursor focus/range AX write cannot be ruled out. There is no source
evidence that the review path called the AX selected-text setter to insert the
transcript; review text insertion is the Unicode-event path, and it did not reach
its post closure.

After the observed stop, `pgrep -x FeishuSpeech` returned exit 1. No FeishuSpeech
process or helper remains to emit additional events. This does not prove that an
earlier, separate explicit-send attempt never emitted an event, and macOS provides
no target-consumption receipt for `postToPid`; those histories remain unmeasured.

## Narrowing leg 3: why the existing tests passed

The prior v4 receipt records the focused and full test suites as green (focused
160/160 in the final validation leg; full target 481 passed, 1 unrelated live-TCP
skip). That green result does not cover the concrete lock composition that failed
in UAT:

- `ReviewDestinationDeliveryTests` injects `Issue38ReviewInputMonitor`, whose
  `postComplete...` implementation compares a plain `UInt64`, invokes the closure,
  and returns (`ReviewDestinationDeliveryTests.swift:672-698`). It does not hold
  the production `CurrentFocusInputInterferenceEpoch` lock.
- The security-delivery fixtures use `R1ReviewInputMonitor`, also a plain property
  and unlocked gate (`FinalTextOutputSecurityTests.swift:1436-1462`).
- `CurrentFocusAppendSessionTests` does instantiate
  `WorkspaceCurrentFocusInputMonitor`, but those tests exercise the provisional
  session/event-poster surface, not `ReviewDeliveryMonitoringSession.performFinalPair`
  with its nested `inputMonitor.interferenceEpoch` read.
- The test-only `TestAtomicInterferenceGate` intentionally holds an `NSLock` while
  invoking its operation (`CurrentFocusAppendSessionTests.swift:1453-1487`), but
  its exercised operation does not perform the review-session nested getter. No
  concrete production-monitor + review-delivery integration test combines the two
  surfaces.

Thus the tests proved the individual seams and fake transactional behavior, but
not the production lock reentrancy that the live sample exposed.

## Narrowing leg 4: Return/Enter and preview focus

The native Return path is conditional on the preview editor actually receiving the
key event:

- `ReviewDraftTextEditor` passes `onConfirm` into `ReviewDraftTextView`
  (`TranscriptionReviewView.swift:210-224, 265-285`).
- `ReviewDraftTextView.keyDown` handles key codes 36 and 76 only when the editor is
  editable and has no marked IME text; unsupported Option/Control combinations and
  Shift-only Return are passed to AppKit (`:361-385`). A qualified event then calls
  `onConfirm(.qualifiedReturn)` at `:380`.
- The SwiftUI button separately calls the same confirmation callback at
  `:234-261`; its declared keyboard shortcut is Command+Return only
  (`:243-250`). There is no application-wide plain-Return fallback.

The preview presenter does not make focus an authority gate. `renderDraft` enables
key interaction and mouse events and calls `orderFrontRegardless`, but not
activation (`ReviewWindowController.swift:207-246`). A separate best-effort focus
task then requests activation (`:248-289`), calls `makeKeyAndOrderFront` (`:310-315`),
and polls for application-active, key-panel, materialized/attached editor, and
first-responder predicates (`:396-415`) for at most two seconds (`:317-393`). A
failure is logged as telemetry and does not revoke editable/Send authority.

This creates two independent user-visible flaws:

1. If the accessory app/panel is not active and the editor is not first responder,
   Return is delivered to the previously active target (or consumed elsewhere),
   because there is no global/local Return routing path. The Send button can still
   receive a mouse click because mouse events are enabled; this explains why the
   user can trigger the separate Send deadlock while Return appears inert.
2. Once either UI action reaches `handleReviewConfirmation`, the coordinator sets
   `reviewConfirmationInFlight = true`, transitions to `.confirming`, and starts an
   async task (`MainViewModel.swift:1950-2020`). There is no timeout around the
   synchronous final-pair call. The self-deadlock therefore leaves the panel
   permanently in “sending” until the process is killed.

## Labeled inferences

- **High confidence — root cause:** the Send hang is a same-thread reentrant
  `NSLock` acquisition at `CurrentFocusInputInterferenceEpoch.value`, proven by
  the main-thread sample stack and the `performIfUnchanged`/nested-getter source
  path. The hotkey-tap wait is a consequence and also explains broader input
  unresponsiveness.
- **High confidence — sampled attempt had no Unicode down/up and no pasteboard
  activity:** the pair gate deadlocks before `postPair()` and the v4 accepted path
  has no pasteboard capability. This rules out this Send attempt as the source of
  a newly queued Unicode pair or image paste.
- **Medium confidence — no AX mutation for the owner’s usual current-focus route:**
  the application-bound route is read-only before the gate. The captured binding
  was not recorded, so exact-cursor focus/range writes remain possible and are
  explicitly not claimed absent.
- **High confidence — Return is not guaranteed by this design:** it requires panel
  activation/key status and editor first responder, while activation is advisory
  and failure only produces telemetry. The runtime artifact did not independently
  measure a Return event, so the exact owner-UAT focus predicate remains unknown.
- **High confidence — tests missed the composition:** all delivery tests substituted
  unlocked fake monitors, and concrete-monitor tests did not drive the review
  delivery closure that performs the nested getter.

## Minimal deterministic reproduction/test hooks (no implementation performed)

1. Add a production-concrete integration oracle that arms a
   `WorkspaceCurrentFocusInputMonitor`, calls its
   `postCompleteSyntheticPairIfInterferenceEpochIsUnchanged` method, and makes the
   supplied `postPair` closure read `monitor.interferenceEpoch`. Run it in a
   subprocess or bounded child task so a failure cannot wedge the XCTest host. The
   current candidate should block at the second getter; a passing implementation
   must return within a short bound without a process kill.
2. Add a coordinator delivery watchdog oracle with an injected pair gate that never
   returns. It should prove that `.confirming` cannot remain indefinitely and that
   the exact frozen draft is retained without retry or another output attempt.
3. Add two native-panel Return legs: (a) panel active/key and editor first responder,
   injecting key codes 36 and 76 and asserting one opaque confirmation intent; (b)
   panel visible but inactive/non-key, asserting that no confirmation is claimed and
   recording the unmet focus predicate. This isolates event delivery from delivery
   deadlock.
4. After the deadlock is addressed, run an installed Release target matrix with
   Send and Return separately. Record target text, event count/phase, pasteboard
   change count/types, and any AX setter trace before and after each attempt. The
   current sample alone cannot supply those GUI measurements.

## What remains unmeasured

- The sampled destination binding (exact cursor versus application-current-focus).
- Whether any exact-cursor focus/range AX setters ran before the deadlock.
- A live Return/Enter event and the corresponding focus predicate.
- Whether a separate earlier Send attempt emitted any output before this sample.
- Whether a target application consumed any previously posted event; macOS exposes
  no consumption acknowledgement for `CGEvent.postToPid`.
- A post-repair installed Release UAT. The app remains stopped pending the owning
  implementation and validation work.

## Result location

This full evidence deliverable is at:

`/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/runtime-diagnosis-v5.md`


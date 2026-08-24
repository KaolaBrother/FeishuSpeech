## Status

**UAT failed — keep this issue open. Do not merge, close, or publish candidate `60090c9`.**

The first Issue #40 defect (strict AX capture blocking startup) is fixed in the candidate, but the
installed Release exposed a second blocking defect: after Fn release, the live preview is destroyed
instead of becoming a durable editable draft.

This body is the canonical Issue #40 contract as of 2026-08-23. It supersedes earlier wording that
allowed either compatibility-mode direct output or automatic clipboard recovery.

## Required product outcome

There is exactly one user-visible output route:

```text
capture task -----\
                   +--> one preview panel: streaming --> sealing --> editable
recognition task -/                                            |
                                                                +--> explicit Send or bare Return
                                                                        |
                                                                        +--> captured cursor destination
```

- Capture/recording and recognition/provider remain separate asynchronous roots.
- They converge only in the in-memory preview/draft model; neither waits for preview rendering,
  editor readiness, acknowledgement, delivery, or the other asynchronous root.
- Fn release only closes capture and moves the same panel to sealing.
- Recognition action 2 plus the recorder barrier freezes the best authoritative result into the
  same panel as an editable draft.
- Only an explicit Send click or bare Return from the editable panel may start destination delivery.
- Before that explicit action, no path may mutate an AX field, emit text keyboard events, paste,
  insert directly, or copy transcript text to the pasteboard.
- Shift+Return inserts one newline. Command+Return and keypad Enter remain compatible confirmation
  gestures. Escape/window close explicitly discards without output.
- A transient panel activation/readiness failure must retain the frozen draft and review authority.
  It must never dismiss the only draft surface or silently downgrade to clipboard output.
- A confirmation delivery failure must return to a retryable editable draft with non-sensitive
  feedback. It must not copy automatically, retry delivery automatically, or target another app.
- Both values of the legacy `reviewBeforeInsert` setting must enter this preview route. The setting
  may be retained temporarily for decoding/migration, but it can no longer authorize direct output.

## Evidence chronology

### A. Original startup failure on main

Installed Release 1.0 (8) from `98e1eb53b6aaee369f6481303a289ca60b843262` failed four
consecutive accepted Fn holds with `无法确认输入位置`.

- macOS TCC reported Accessibility allowed for `Siji.FeishuSpeech`.
- `MainViewModel.prepareReviewDestination` treated every strict AX focused-element/selection miss as
  terminal.
- The strict gate ran before panel, recorder, journal, and provider startup, so no streaming preview
  could appear on an otherwise safe editable target.

### B. Candidate that fixed startup

Local branch `workflow/issue-40`, candidate
`60090c955fbd57d4b6e875acb8a9bdc42d61f032` (`fix: keep review available without exact AX cursor
(#40)`) added typed exact-cursor versus captured-application authority and fail-closed delivery.

Automated evidence before installation:

| Gate | Result |
| --- | --- |
| Focused Issue #40 suites | 79 passed, 0 failed |
| Full serialized macOS suite | 442 passed, 1 intentional live-TCP skip, 0 failed |
| Debug build | passed |
| Release build | passed |
| SwiftLint strict | 0 violations |
| Correctness review | passed |
| Security review | passed after consecutive Secure/PID/complete-identity sample repair |
| Capture/recognition topology guard | protected task-launch, drain, consumer, journal, transport, retry, and replay surfaces unchanged |

The candidate was installed as Release 1.0 (8) at `/Applications/FeishuSpeech.app` for UAT. It is
not an accepted release and its branch commit is not yet published to GitHub.

### C. Installed candidate UAT failure

Observed process: `/Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech`, PID `3567`, on
2026-08-23 CST.

First interaction:

| Time | Evidence |
| --- | --- |
| 13:35:01.929 | Fn pressed |
| 13:35:02.242 | streaming generation 1 begins; preview, capture, provider, and packet ACKs operate |
| 13:35:11.214 | Fn released; streaming transitions to sealing |
| 13:35:11.214 | `releaseRequested`, `captureClosed=true`, 43 journal packets |
| 13:35:11.258 | recorder resources stop; `recorderBarrierComplete`, 44 journal packets |
| after barrier | recognition ACKs continue, proving recognition remains independent of recorder shutdown |
| 13:35:12.184 | `Manual reset to idle` from the normal terminal-review transition |
| 13:35:12.190 | `Recovery text copied to pasteboard`, followed by another reset; panel disappears |

A second interaction captured for about 10.15 seconds (`13:35:18.818–13:35:28.970`) and showed the
same user-visible loss. This rules out the 60-second watchdog and an isolated capture failure.

No transcript bytes, target control contents, credentials, or clipboard contents are included in
this evidence.

## Root cause

Fn release is not the destructive event:

1. `HotKeyService.handleFnReleased` only changes `.streaming` to `.sealing`.
2. `MainViewModel.beginSealing` closes capture, renders the latest snapshot as sealing in the same
   read-only panel, and starts the recorder barrier.
3. `handleReviewTerminal` independently freezes the action-2 final text, or the latest non-empty
   snapshot as an incomplete draft, and awaits the recorder barrier.
4. `finishReviewTransition` tears down the completed capture/recognition session and calls
   `hotKeyService.resetToIdle()` **before editable surface readiness is proven**.
5. `ReviewWindowController.renderEditableWhenReady` requires application activation, a key review
   panel, a materialized editable `NSTextView`, and successful first-responder ownership. Failure,
   cancellation, or the two-second readiness deadline returns `.failed` and dismisses the panel.
6. `MainViewModel.recoverReviewSurfaceFailure` then copies the frozen draft, revokes review
   authority, dismisses/clears the surface, resets the hot key again, and returns the review state
   to idle.

The observed `Manual reset to idle` followed by `Recovery text copied to pasteboard` without any
Send/Return uniquely matches this failure branch.

The Release lacks per-predicate readiness telemetry. Therefore it is confirmed that the production
editable transition returned `.failed`, but it is not yet measured whether the immediate cause was
activation rejection, inactive application, non-key panel, delayed editor materialization, failed
first-responder assignment, task cancellation, or timeout. A bounded probe proved that this
accessory process can activate asynchronously, so permanent activation impossibility is ruled out.

## Why existing tests passed

- `ReviewFirstMainViewModelTests` uses a fake presenter. Its success path returns `.ready` without a
  real `NSPanel`; its failure test explicitly expects one clipboard copy, dismissal, and idle state.
  That test encodes the now-obsolete behavior observed in UAT.
- `TranscriptionReviewViewTests` are source-policy/string assertions, not a running controller test.
- Keyboard tests prove Return behavior in a generic native editor, not `LSUIElement`/accessory app
  activation, production `ReviewPanel` key-window state, SwiftUI editor materialization, or first
  responder transfer.
- No installed-Release gate records activation result, individual readiness predicates,
  cancellation/timeout reason, or the final readiness result.

## Target architecture and ownership

### State and authority

```text
idle
  -> streaming(read-only live snapshot)
  -> sealing(read-only frozen/latest snapshot; capture closes)
  -> editablePending(durable frozen draft; presenter activation may retry)
  -> editable(durable user-owned draft)
  -> confirming(frozen exact draft; one explicit delivery task)
      -> delivered -> idle
      -> deliveryFailed -> editable(same draft + retryable feedback)

discard/cancel before confirmation -> idle, zero output
presenter readiness failure        -> editablePending, authority retained, zero output
```

The durable draft authority belongs to the coordinator/model and must outlive transient AppKit
window readiness. `ReviewWindowController` presents that authority; it cannot destroy it merely
because activation or focus is delayed.

### Component boundaries

| Component | Responsibility | Must not do |
| --- | --- | --- |
| `HotKeyService` | Accepted Fn lifecycle and generation identity | deliver text or own draft lifetime |
| capture/recorder task | Produce bounded audio packets and complete recorder barrier | await UI, recognition, or delivery |
| recognition consumer/retry/replay | Produce ordered snapshots and action-2 terminal result | mutate target or await UI readiness |
| `MainViewModel` review coordinator | Own one generation-scoped preview/draft authority and state transitions | revoke draft on transient presenter failure |
| `ReviewWindowController` | Render the same panel read-only then editable; report typed readiness reason | copy transcript, choose destination, or make terminal product decisions |
| `ReviewDestinationDelivery` | After explicit confirmation only, validate captured authority and attempt exactly one delivery | ambient PID discovery, automatic retry, fallback copy, or cross-app output |

### Destination security

- Capture a complete original application identity before preview/audio/provider startup.
- Prefer the exact captured AX cursor/selection route when available.
- On an ordinary non-secure strict AX miss, retain only the complete captured application identity;
  after explicit confirmation, reactivate and revalidate that same application and deliver to its
  current focus.
- Secure Input, accessibility trust loss, incomplete identity, PID/launch-identity change,
  activation failure, target change, unsafe text, or uncertain post fails closed.
- Failure preserves the editable draft and does not mutate the target or clipboard automatically.
- Never log transcript, target-control data, clipboard data, credentials, tokens, or stream bytes.

## Implementation plan

1. **Replace obsolete test authority (RED).** Change tests that currently expect automatic recovery
   copy/dismiss. Add exhaustive assertions that clipboard, AX setters, keyboard events, and direct
   output remain untouched before explicit confirmation and after readiness/delivery failures.
2. **Unify both legacy settings paths.** Route every accepted interaction through the review
   coordinator. Retire compatibility continuous/direct output as a selectable user-visible route;
   retain persisted-setting decoding only as needed for migration.
3. **Separate durable draft from presenter readiness.** Add a generation/revision-scoped
   `editablePending`/editable authority that is not cleared by `resetToIdle`, activation delay,
   timeout, presenter cancellation, or first-responder failure.
4. **Repair same-panel editable activation.** Make readiness retryable and typed; keep the panel and
   draft visible, materialize the editor before first-responder assignment, and record
   non-content-bearing activation/readiness reason telemetry.
5. **Enforce the sole output gate.** Only Send/bare Return may freeze a draft and create one delivery
   task. Remove automatic transcript clipboard recovery from surface failure and delivery failure.
   A failed delivery returns the same draft to editable state with safe retry/discard controls.
6. **Retain exact/fallback security.** Preserve exact target preference, captured-application
   fallback, consecutive Secure/PID/complete-identity gates, fixed target PID, multiline-safe
   exact-once transaction, postflight uncertainty handling, and no automatic retry.
7. **Validate and release only after live UAT.** Run focused and full serialized tests, Debug/Release,
   strict lint, correctness/security review, topology guards, then install a fresh Release and prove
   streaming -> sealing -> editable -> edit -> Return/Send in at least two third-party targets.

### Expected implementation surfaces

- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeech/Models/TranscriptionReviewState.swift`
- `FeishuSpeech/Controllers/ReviewWindowController.swift`
- `FeishuSpeech/Views/TranscriptionReviewView.swift`
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift`
- `FeishuSpeech/Services/TextInputSimulator.swift`
- `FeishuSpeech/Models/AppSettings.swift` and settings UI only if needed to retire the bypass
- Review coordinator, window readiness, keyboard, destination, clipboard, security, and migration
  tests corresponding to those production surfaces

Protected asynchronous surfaces remain unchanged unless separate evidence proves a defect:
`AudioRecorder`, `ByteBoundedAudioIngress`, `HoldPacketJournal`, streaming transport/session,
retry/replay, capture drain, and recognition consumer loops.

## Acceptance gates

- [ ] Both legacy setting values open one streaming preview and produce zero external output while
      Fn is held.
- [ ] Fn release leaves the same panel visible in sealing; recorder closure does not stop or block
      recognition settlement.
- [ ] Action 2 plus recorder barrier produces one durable editable draft in that same panel.
- [ ] Activation, key-window, editor-materialization, first-responder, cancellation, and timeout
      failures preserve authority/draft and produce zero clipboard/target mutation.
- [ ] Bare Return, keypad Enter, Command+Return, and Send confirm exactly once; Shift+Return inserts
      exactly one newline without confirming.
- [ ] Exact-target confirmation remains preferred; safe non-secure AX misses use only the captured
      application identity and never an ambient/different application.
- [ ] Before explicit confirmation, clipboard change count, AX setters, pasteboard writes, keyboard
      posts, and direct insert calls are all zero.
- [ ] Confirmation failure/uncertainty retains the exact edited draft, performs no automatic copy or
      retry, and allows explicit retry or discard.
- [ ] Secure Input, trust loss, identity/PID drift, unsafe text, and cross-app focus fail closed.
- [ ] Late/stale callbacks cannot mutate a newer draft or deliver an older generation.
- [ ] Capture/journal and recognition/retry/replay remain independent, bounded, and free of UI
      awaits/backpressure.
- [ ] Focused tests, full serialized suite, Debug/Release, strict SwiftLint, correctness review,
      security review, and diff/topology guards pass.
- [ ] Fresh installed-Release UAT proves the complete path twice and verifies the installed app is
      the intended sole runnable copy before Issue #40 can close.

## Current decision

Candidate `60090c9` is useful evidence for application-bound target capture, but it is rejected as a
release because the preview draft is not durable and the implementation still has multiple
external-output paths. Issue #40 remains the active implementation and release gate.

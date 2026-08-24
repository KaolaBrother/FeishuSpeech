# Issue #40 Fn-release preview dismissal diagnosis

## Result

The installed Release does not dismiss the preview directly on physical Fn release. Fn release
correctly moves the hot-key state from streaming to sealing, closes capture, preserves the latest
recognition snapshot in the same read-only review panel, and starts the recorder barrier.

The destructive transition occurs after recognition action 2 and the recorder barrier. The
production `ReviewWindowController.renderEditableWhenReady` returns `.failed`; the coordinator then
runs `recoverReviewSurfaceFailure`, which copies the frozen draft to the pasteboard, revokes review
authority, dismisses the panel, resets the hot key, and returns the review state to idle. This is why
the user sees the streaming preview disappear and never receives an editor, Send button, or Return
submission surface.

No product or test implementation was changed during this diagnosis.

## Installed-process evidence

Candidate: `60090c955fbd57d4b6e875acb8a9bdc42d61f032`, installed as
`/Applications/FeishuSpeech.app`, observed PID `3567`.

First observed generation:

- `13:35:01.929`: Fn pressed.
- `13:35:02.242`: streaming generation 1 begins; capture, provider streaming, packet ACKs, and the
  live preview all operate.
- `13:35:11.214`: Fn released; state changes from streaming to sealing.
- `13:35:11.214`: lifecycle records `releaseRequested`, `captureClosed=true`, 43 journal packets.
- `13:35:11.258`: audio resources finish stopping; lifecycle records
  `recorderBarrierComplete`, 44 journal packets.
- Recognition ACKs continue after release, confirming that recognition remains independent from
  recorder shutdown.
- `13:35:12.184`: `Manual reset to idle`, emitted by `HotKeyService.resetToIdle()` during
  `finishReviewTransition` before editable readiness is known.
- `13:35:12.190`: `Recovery text copied to pasteboard`, followed by another reset. This exact
  source sequence belongs to `recoverReviewSurfaceFailure`.

A second capture ran from approximately `13:35:18.818` to `13:35:28.970` and exhibited the same
user-visible failure, so this is not the 60-second recording watchdog or an isolated capture fault.

## Source-backed failure chain

1. `HotKeyService.handleFnReleased` changes `.streaming` to `.sealing`; it does not dismiss a
   review surface.
2. `MainViewModel.beginSealing` marks capture closed, renders `.sealing(preview:)` into the same
   panel, and starts the asynchronous recorder barrier.
3. `handleReviewTerminal` freezes the authoritative final text (or latest non-empty snapshot) and
   independently awaits the recorder barrier.
4. `finishReviewTransition` tears down capture/recognition session ownership and calls
   `hotKeyService.resetToIdle()` before it knows whether the editable surface is usable. It then
   publishes `.editable` and awaits `renderEditableReviewSurface`.
5. The production controller requires activation plus every readiness predicate: `NSApp.isActive`,
   the review panel is the key window, an editable `NSTextView` exists in that panel, and the panel
   accepts and retains that editor as first responder. Activation rejection, cancellation, identity
   invalidation, or failure to satisfy the combined predicate within two seconds returns `.failed`.
6. The controller dismisses on that failure. Main then calls `copyForManualRecovery`, revokes the
   only review authority (which dismisses again and clears the draft), resets the hot key, and
   publishes `.manualRecoveryCopied`.

The available Release telemetry does not record the individual readiness predicates. A bounded
activation probe showed that the accessory process can accept activation and become active
asynchronously, so permanent activation impossibility is ruled out. It does not prove which
activation/readiness condition failed during the UAT. The exact subcondition remains unmeasured;
the `.failed` branch and its destructive consequence are high-confidence conclusions.

## Contract conflict

The required global output topology is:

```text
capture task -----\
                   +--> one preview: streaming --> sealing --> editable
recognition task -/                                      |
                                                          +--> explicit Send or bare Return
                                                                  |
                                                                  +--> bound cursor destination
```

Capture and recognition stay separate and asynchronous. They converge only in the preview model.
Fn release only seals capture. Recognition action 2 plus the recorder barrier freezes the same
panel into an editable draft. Before explicit Send or bare Return, no path may insert text, emit
keyboard events, mutate an AX field, paste, or copy transcript text to the pasteboard.

The current implementation violates that contract in three places:

1. Editable-surface failure automatically copies the transcript, revokes authority, and destroys
   the only draft surface.
2. Confirmation delivery failures automatically copy the transcript instead of retaining a
   retryable/editable draft.
3. Compatibility mode still bypasses the preview and performs continuous/direct output. The new
   global contract supersedes that externally visible route; it does not require capture and
   recognition tasks to be coupled.

## Why the green suite missed the UAT failure

- `ReviewFirstMainViewModelTests` injects a fake presenter. Its success path simply returns `.ready`;
  its failure test explicitly expects one recovery copy, dismissal, and idle state. The test thus
  codifies the obsolete behavior that caused the UAT failure.
- `TranscriptionReviewViewTests` checks controller source strings, not a running production panel.
- Keyboard tests prove Return semantics in a generic native editor, not accessory-app activation,
  `ReviewPanel` key-window ownership, SwiftUI editor materialization, or first-responder transfer.
- No installed-Release test or diagnostic log records activation result, readiness predicate values,
  timeout/cancellation cause, or the final readiness result.

Focused review-first, static review-window, and keyboard selectors passed during the read-only
investigation. That confirms the gap: the suite exercises the intended state model and old recovery
policy, but not the real WindowServer boundary where the candidate failed.

## Diagnosis boundary

Confirmed root cause at the product boundary: production editable-surface readiness returns
`.failed`, and the failure policy destroys the preview and produces automatic clipboard output.

Not yet measured: whether the UAT failure was activation rejection, inactive application,
non-key panel, missing editor materialization, failed first-responder assignment, readiness task
cancellation, or timeout. The next implementation must add non-content-bearing readiness reason
telemetry and preserve the frozen draft for retry/editing regardless of those transient UI
conditions.

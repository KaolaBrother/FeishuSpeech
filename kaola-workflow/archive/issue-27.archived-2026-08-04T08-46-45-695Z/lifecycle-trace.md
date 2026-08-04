# Issue #27 UAT lifecycle trace

Date: 2026-08-04

Scope: read-only production/control-flow investigation in `.kw/worktrees/issue-27`, plus current unified-log evidence and a narrow comparison with the locally available KaolaTerminal streaming implementation. No tracked product or test files were changed.

## Findings

### 1. Fn release currently closes text admission before the recorder tail and Feishu final are processed

This is code-proven and directly explains the reported truncated ending.

- Fn-down is detected on the HID event tap and marshalled to the main queue (`FeishuSpeech/Services/HotKeyService.swift:290-307`). After the 0.3-second hold, `transitionToStreaming()` allocates a generation and publishes `.streaming` (`HotKeyService.swift:437-460`).
- `MainViewModel` receives that state through its Combine sink (`FeishuSpeech/ViewModels/MainViewModel.swift:326-345`, `356-371`), captures the output destination, starts audio capture, and starts the audio consumer (`MainViewModel.swift:419-471`).
- Audio callbacks convert PCM and append it to the byte-bounded ingress (`FeishuSpeech/Services/AudioRecorder.swift:369-384`, `551-567`). The consumer journals every packet before sending it (`MainViewModel.swift:680-704`). Each successful action-1/action-0 request returns one opaque recognition snapshot (`FeishuSpeech/Services/FeishuStreamingSession.swift:173-204`).
- While Fn remains held, packet snapshots are admitted only when `sealStarted == false` and the response ledger remains open (`MainViewModel.swift:983-1057`, `1151-1171`). They are then offered either to the AX-owned range or the current-focus keyboard replacement owner (`MainViewModel.swift:1119-1148`).
- Fn-up changes the hot-key state from `.streaming` to `.sealing` (`HotKeyService.swift:336-353`). `MainViewModel.beginSealing()` immediately does all of the following, in this order: sets `sealStarted = true`, closes `responseOutputLedger`, closes retry admission, and only then starts the asynchronous recorder stop/barrier (`MainViewModel.swift:1466-1493`).
- Recorder shutdown itself is careful: it stops `AVCaptureSession`, waits for all already-queued audio delegate callbacks, and only then flushes the ingress tail and closes the ingress (`AudioRecorder.swift:208-250`). Therefore accepted physical audio is not being cut at the recorder boundary; the text-admission boundary is earlier than the completed audio/recognition boundary.
- Any packet HTTP response that returns after Fn-up is rejected as `sealed`: `recordHeldRecognitionIfEligible` refuses it and `classifyPacketAdmission` refuses it (`MainViewModel.swift:1151-1171`). This includes the response to a packet that was already in flight when the user released Fn.
- Once the recorder barrier closes the ingress, the consumer does call `session.finish()` (Feishu action 2) (`MainViewModel.swift:732-769`; `FeishuStreamingSession.swift:206-255`). However, the returned terminal text is deliberately not admitted. `handleFinal(..., isTerminal: true)` records `terminalNotAdmitted`, calls `finalizeExistingOutputOwner`, and ignores the `text` parameter (`MainViewModel.swift:1190-1232`). `finalizeExistingOutputOwner` passes `finalText: nil` and only the last pre-release ledger snapshot (`MainViewModel.swift:1235-1252`).

Observed state machine:

```text
Fn held
  capture audio -> packet -> HTTP snapshot -> admit/replace output

Fn released
  sealStarted = true + close response admission + close retries
    -> stop recorder
    -> wait queued audio callbacks
    -> flush tail and close ingress
    -> drain/send tail, but all post-release snapshots are suppressed
    -> action 2 final, but terminal text is ignored
    -> finalize only the last snapshot admitted before Fn-up
    -> cleanup/idle
```

The user-requested behavior instead requires capture closure and recognition/output closure to be distinct lifecycle boundaries: release ends capture, while already-captured audio, its packet responses, and the action-2 final remain eligible until the final recognition transaction settles.

### 2. Release during creation, retry wait, or replay can end without recognizing all captured audio

- At release, `closeRetryAdmission()` cancels an in-flight session factory and retry sleep (`MainViewModel.swift:1643-1649`).
- If release interrupts `.creatingSession` or `.waitingToRetry`, `beginSealing()` goes directly to `completeAfterRecoverableRelease()` after the recorder barrier (`MainViewModel.swift:1495-1499`). If it interrupts replay, it cancels that attempt and then takes the same completion path (`MainViewModel.swift:1500-1507`).
- `completeAfterRecoverableRelease()` never creates a final attempt or drains/replays the complete captured journal. It either completes with the last held recognition, reports failure, or treats release before the first accepted packet as ordinary completion (`MainViewModel.swift:847-864`).

Thus, the truncation is not limited to action-2 text. Release can revoke the only authority capable of recognizing captured-but-not-yet-acknowledged audio.

### 3. Current logs show a real recoverability loop that leaves the app apparently active with no output

Current unified-log evidence from the production `FeishuSpeech` process (PID 79949), not XCTest:

- `15:00:32.501`: HTTP 200 response rejected at action 0, sequence 99, Feishu business code 10024.
- `15:00:32.680` through `15:00:48.840`: retry ordinals 1 through 8. Most fresh streams were rejected immediately at action 1, sequence 0, with the same code 10024; one reached action 0, sequence 1 before rejection.
- `15:01:49.224` through `15:01:50.423`: another interaction shows code 10024 followed by retry ordinals 1 through 3.

The logs contain no transcript, credentials, or response body. They prove repeated Feishu business rejection and repeated retries; they do not establish the documented meaning of business code 10024.

The code maps exactly this backend code to recoverable (`MainViewModel.swift:833-844`). Retry ordinal has no attempt or elapsed-time limit: it increments indefinitely, while only the delay is capped at approximately four seconds (`MainViewModel.swift:771-812`; `FeishuSpeech/Models/StreamingSpeechModels.swift:13-30`). The visible state remains `.streaming`; there is no reconnecting/degraded state transition. This matches the user-visible symptom “normally active, but nothing comes out.”

### 4. Recovery can become progressively latent even after connectivity returns

- Every delivered packet is retained both in `packetJournal` and in ingress accounting for replay (`MainViewModel.swift:433-455`, `680-704`; `FeishuSpeech/Services/ByteBoundedAudioIngress.swift:179-217`).
- Every fresh attempt replays the entire journal serially before consuming new live audio (`MainViewModel.swift:657-665`, `707-729`). A failure at sequence 99 therefore creates a substantial catch-up path. Previously owned packet indices are correctly suppressed as historical replay, but the replay still consumes network round trips before new speech can produce output (`MainViewModel.swift:1060-1103`).
- `retryOrdinal` is not reset after a successful packet; it resets only when an interaction begins or is cleaned up (`MainViewModel.swift:425-440`, `1533-1552`, `1617-1633`). After one recovered outage, a later outage in the same hold immediately inherits the larger, capped backoff.
- Streaming session creation and individual packet/finish operations have no coordinator-owned watchdog. Production streaming uses `URLSession.shared.data(for:)` without an explicit request deadline (`FeishuAPIService.swift:691-699`, `864-881`), so the UI may remain active while token creation or an HTTP packet is parked until URLSession/network failure resolves.
- The UI is set active before `AVCaptureSession.startRunning()` confirms success and before a streaming session exists (`MainViewModel.swift:452-471`; `AudioRecorder.swift:165-184`). Failure is eventually handled, but slow startup is visually indistinguishable from healthy streaming with no hypothesis yet.

These are separate liveness mechanisms from the release truncation, but both converge on the same symptom: the overlay says active while no new response is eligible or arriving.

## Existing tests versus the UAT contract

Several tests currently lock in the behavior the owner has now rejected:

- `StreamingMainViewModelTests.swift:150-178` requires an action-2 final to produce no release-time output.
- `StreamingMainViewModelTests.swift:231-253` requires live AX output to retain only the held partial and ignore the terminal final.
- `StreamingMainViewModelTests.swift:283-320` requires release to call `finalize(finalText: nil)` using only the held partial.
- `StreamingMainViewModelTests.swift:2735-2764` explicitly requires every post-seal partial/final callback to be suppressed.
- The in-flight-release test at `StreamingMainViewModelTests.swift:255-281` proves the tail bytes are sent but does not assert that the returned tail snapshot or action-2 final updates output.
- Retry coverage proves backend 10024 is admitted for one successor attempt (`StreamingMainViewModelTests.swift:2293-2335`) and proves exponential delay capping (`StreamingCoordinatorStateTests.swift:67-85`), but it does not test repeated 10024, eventual recovery after many attempts, reset-after-success, a hanging factory/send/finish, or visible reconnect progress.

## Minimal production seams affected

This section identifies ownership seams; it does not select the implementation.

1. `MainViewModel.beginSealing` (`MainViewModel.swift:1466-1511`): currently conflates “capture admission closed,” “retry authority closed,” and “recognition/output response admission closed.”
2. Response ledger admission (`MainViewModel.swift:28-102`, `983-1089`, `1151-1171`): currently cannot distinguish a post-release response owned by already-captured audio from a truly late/stale callback after terminal cleanup.
3. Terminal-final handling (`MainViewModel.swift:1190-1252`): currently discards action-2 text and finalizes with `finalText: nil`.
4. Release recovery (`MainViewModel.swift:574-676`, `771-864`, `1495-1507`): currently revokes creation/replay/backoff authority without a path that proves all captured packets reached a final attempt.
5. Retry/liveness policy (`MainViewModel.swift:771-844`; `StreamingSpeechModels.swift:13-30`): delay is bounded, but attempts and elapsed silence are not; success does not reset the streak.
6. Per-operation deadlines (`FeishuAPIService.swift:533-553`, `691-699`; `FeishuStreamingSession.swift:173-255`): factory, packet, and finish calls depend on transport behavior rather than coordinator-owned lifecycle deadlines.
7. Privacy-safe diagnostics (`MainViewModel.swift:1266-1301`; `FeishuStreamingSession.swift:30-45`): response/output receipts exist, but there is no durable per-generation phase receipt covering capture-start confirmation, factory start/end, packet backlog/ACK count, retry cause/streak, release boundary, tail flush, finish start/end, and cleanup reason.

## Directly useful KaolaTerminal comparison

The local KaolaTerminal implementation confirms two liveness patterns that are absent here, without determining FeishuSpeech's final design:

- It wraps streaming factory, each packet, and finish in attempt-scoped watchdogs (`KaolaTerminal/Services/Speech/SpeechClient.swift:1238-1276`, `1309-1341`, `1503-1535`).
- Its release path distinguishes stopping capture from draining an already-emitted packet/tail and gives the latter a bounded acknowledgement grace (`SpeechClient.swift:1343-1409`, `1474-1501`).
- It tracks a failure streak and resets it after a successful packet ACK (`SpeechClient.swift:1067-1072`, `1148-1162`).

KaolaTerminal's output destination and release UX differ from FeishuSpeech, so its exact fallback/timeout policy should not be copied as a product decision. The useful comparison is limited to lifecycle separation, operation watchdog ownership, and success-reset retry accounting.

## Regression-test recommendations

Tests should remain in separate custody from production implementation.

1. Release while the last action-0 request is in flight: its response extends/revises the held snapshot; after release it must still replace owned text, then action 2 must apply the authoritative final exactly once before cleanup.
2. Release with a queued short tail: recorder barrier must flush the tail; tail response and action-2 final remain eligible; idle/owner close occurs only after both settle.
3. Terminal final differs from the last held snapshot in the last words: both AX and keyboard-replacement routes end at the terminal final, without duplicate append or release-time one-shot insertion.
4. Release during factory creation, retry sleep, and replay: captured journal ownership is not silently discarded. Each branch must end either with a recognized final or a typed, observable terminal outcome; no success state may be reported from an unrecognized tail.
5. Repeated backend 10024 while held, followed by success: the interaction remains recoverable, eventually emits new output, and a successful ACK resets the failure streak/backoff.
6. Hanging factory, packet, and finish fakes: each operation leaves the silent-active state through a typed timeout/retry transition; no task can park indefinitely.
7. Release during a recoverable outage: test the agreed post-release retry/finalization budget and verify output admission remains generation-bound until its terminal boundary.
8. Stale callback after terminal cleanup and callback from an old generation: both remain suppressed, preserving the current stale-generation security boundary.
9. Privacy receipt assertions: phase/retry diagnostics contain only generation, counts, phase, typed error class, and timing; never transcript, credentials, response body, target content, or hashes of those values.

## Unknowns requiring a product/implementation decision

- The authoritative Feishu meaning and operational recovery guidance for business code 10024 was not available in the inspected local source/logs. The present allowlist marks it recoverable, and production logs prove retries, but not whether immediate fresh-stream replay is the appropriate recovery.
- “Finish recognizing all recordings” establishes that release must not seal early, but it does not yet state the maximum post-release wait/retry budget or the user-visible outcome if Feishu remains unavailable indefinitely. That policy is required before a reliable terminal-state test can be exact.
- Current unified logs retained the error-level product evidence above but not the full info-level lifecycle needed to bind every failure to one generation and packet backlog. The code path is clear; a complete field diagnosis still needs the missing phase receipts.

## Validation commands for the eventual fix

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test
xcodebuild -scheme FeishuSpeech -configuration Debug build
xcodebuild -scheme FeishuSpeech -configuration Release build
swiftlint --strict
```

Focused suites should include `StreamingMainViewModelTests`, `StreamingCoordinatorStateTests`, `FeishuStreamingSessionTests`, `StreamingAudioIngressTests`, `AudioRecorderStreamingIntegrationTests`, `CursorTextSessionTests`, `CurrentFocusAppendSessionTests`, and `FinalTextOutputSecurityTests`.

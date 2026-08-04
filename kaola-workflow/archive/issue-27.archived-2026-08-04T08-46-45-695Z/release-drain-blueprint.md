# Issue #27 release-drain and streaming-liveness blueprint

## Outcome and evidence

Release must become a capture boundary, not a recognition/output boundary. Fn-up stops the recorder, waits for its already-queued callbacks, flushes the ingress tail, and closes ingress. The same generation must then remain authoritative while its current request settles, any captured journal is replayed after a recoverable failure, all queued/tail packets are acknowledged, and Feishu action 2 returns the terminal snapshot. That terminal snapshot is authoritative and is reconciled through the already-owned AX range or fixed-PID keyboard replacement route before output ownership closes.

This design addresses two separately proven defects:

- `MainViewModel.beginSealing` currently sets `sealStarted`, closes `ResponseOutputLedger` admission, and cancels factory/backoff before the recorder barrier. The Release log shows valid packet responses and action 2 arriving after Fn-up and being locally suppressed.
- Repeated HTTP-200 / Feishu business-code `10024` responses are already classified recoverable, but the failure ordinal never resets after a successful packet and factory/send/finish have no coordinator-owned deadline. The app can therefore look active while recovery is increasingly latent or a transport call is parked.

No Feishu response body, transcript, credentials, token, stream identifier, target content, or content hash may be introduced into logs or receipts.

## Resolved failure policy

The policy is correctness-first but finite, using limits already established by the app:

1. While Fn remains held, recoverable failures continue retrying without an attempt-count cap. Each failed streak uses the existing jittered `250 ms -> 4 s` capped backoff. Any successful packet acknowledgement, including a replay acknowledgement, resets that streak to zero.
2. Every coordinator-owned factory, packet, and finish operation has a 30-second watchdog, matching the existing API request/recognition timeout. The effective operation deadline is clamped to the remaining post-release drain budget.
3. Fn-up does not consume the recognition budget while `AudioRecorder.stopStreamingRecording` is proving the recorder barrier and flushing the tail. Once that barrier completes, the current generation receives an overall 60-second drain budget, matching the app's maximum recording duration. Recoverable retries, including backend `10024`, continue within that budget without an additional arbitrary attempt cap.
4. Normal success requires current-generation ingress exhaustion followed by a settled action-2 result. A safe non-empty action-2 snapshot is authoritative. A contentless action-2 result preserves the last safe snapshot and presents the existing `.emptyFinalPreservedPartial` feedback.
5. If the post-release budget expires, a nonrecoverable error occurs, or a watchdog cannot recover before the budget ends, close response admission first, invalidate the generation, cancel the attempt, and never mutate output again. Preserve already committed/provisional text. Present `.emptyFinalPreservedPartial` when a safe snapshot exists, `.provisionalOutputPreserved` when delivery ownership is uncertain, and the fixed `流式识别失败` error when no usable snapshot exists. Never report this path as an ordinary successful completion.
6. App reset, permission loss, Secure Input activation, sleep/lifecycle invalidation, ingress failure, or explicit abnormal termination still revoke the generation immediately; they do not receive release-drain recovery.

The 60-second post-barrier cap prevents an unavailable backend from holding the application forever, while the 30-second per-operation cap makes a single silent factory/send/finish observable and recoverable. A retry-count cap is deliberately not added: fast `10024` responses should be allowed to recover for the full bounded drain window.

## State and ownership invariants

### Lifecycle invariants

1. `activeSessionIdentity` is the sole generation authority. Every factory result, packet result, replay result, timeout, retry wake-up, terminal callback, and drain-deadline callback must match both the active generation and the active attempt token before changing state.
2. Split the existing `sealStarted` meaning into two explicit facts:
   - `captureClosed`: Fn-up was accepted; no successor hold is admitted and recorder shutdown is in progress or complete.
   - response/retry admission: recognition work and safe output remain admitted for the current generation until terminal settlement or true cleanup.
   `ResponseOutputLedger.isAdmissionOpen` and `retryAdmissionOpen` must not be closed merely because `captureClosed` became true.
3. Fn-up is idempotent. It starts exactly one recorder barrier, exactly one post-barrier drain deadline, and does not cancel an in-flight factory, retry sleep, replay, packet, or finish solely because release occurred.
4. The recorder barrier owns capture closure. Only after `stopStreamingRecording` has stopped the session, crossed the audio delegate queue, flushed/padded the accepted tail, and called `ingress.finish` may the consumer observe ingress exhaustion and attempt action 2.
5. `packetJournal` is append-only for a generation. A packet is journaled before its first send. On a fresh session, all journal entries replay in index order; already-owned indices remain historical no-ops, while the first previously unacknowledged index may acquire response ownership.
6. `retryFailureStreak` and `attemptIdentifier` are different counters. The attempt identifier is monotonic for stale-callback/watchdog suppression and never resets during the generation. The failure streak drives backoff and resets after every successful nonfailed packet response.
7. Action 2 runs only after the current attempt has acknowledged every journaled packet and ingress is exhausted. A recoverable packet or finish failure retires that attempt and returns to fresh-session creation plus full journal replay, even after Fn-up, while the drain budget remains.
8. Normal cleanup occurs only after terminal output finalization. Cleanup closes ledger/retry admission, cancels watchdogs, invalidates identity and output owners, clears journal/references, and then returns the hot-key state to idle. True abnormal cleanup invalidates identity before awaiting remote cancellation so late callbacks cannot write.

### Output safety invariants

1. The output owner is created once for the generation and never rebound during release drain. Preserve the existing captured AX destination or fixed process identifier. For the accessibility-unavailable route, arm the fixed-PID `CurrentFocusAppendSession` during streaming startup rather than waiting until the first post-release response; a terminal-only response must never capture whichever app happens to be frontmost after Fn-up.
2. AX output continues replacing one verified owned range. It must receive the terminal snapshot as `.final(text)` so it verifies and commits the authoritative replacement before discarding its destination token.
3. Keyboard output continues treating every response as a complete opaque snapshot. Terminal reconciliation uses the same Swift-`Character` longest-common-prefix calculation, exact Backspace count, and replacement suffix as held-time updates. It is not appended as a delta and is emitted at most once.
4. The current physical-interference epoch remains armed for the whole generation, including drain. Each complete synthetic down/up pair stays inside the shared epoch lock. Any physical input or tap loss may let the active pair finish but permanently suspends later Backspaces/insertion for that generation.
5. Secure Input remains fail-closed before and during every AX or keyboard transaction. Release drain never reopens a security-rejected owner and never falls back to pasteboard or a newly sampled cursor.
6. An unsafe/contentless terminal snapshot cannot overwrite the last safe snapshot. Contentless final produces the existing partial-preserved feedback; control/action characters remain rejected according to the current AX versus keyboard route rules.
7. Once response admission closes or `activeSessionIdentity` changes, callbacks from the old generation, a timed-out attempt, or a late noncooperative task are receipts-only suppressed events and cannot claim a packet index, alter the ledger, or touch an output owner.

## Transition ordering

### A. Start and held streaming

1. `beginStreaming(identity:)` resets generation state, opens ledger and retry admission, zeros `retryFailureStreak`, zeros attempt sequencing, and records `phase=generationStarted`.
2. Capture the AX destination or arm the current-focus fixed-PID owner before starting recognition work. Keep all existing destination, Secure Input, and interference gates.
3. Start recording/ingress and the consumer. Record separate `captureConfigured` and asynchronous `captureStarted` phase receipts.
4. For each attempt: allocate a new monotonic attempt identifier, watchdog session creation, replay the journal, then consume live ingress.
5. On every successful packet result: verify generation+attempt, set the accepted-packet fact, reset `retryFailureStreak = 0`, then reserve/claim/output the packet snapshot. A `.failed` event is not an acknowledgement.

### B. Fn-up / capture close

1. `beginSealing(identity:)` verifies generation and idempotence, sets `captureClosed = true`, stops the duration timer, changes UI to `.sealing`, and plays the stop sound once.
2. It does **not** close `ResponseOutputLedger`, call `closeRetryAdmission`, cancel `sessionCreationTask`, cancel `retrySleepTask`, cancel replay, or finalize an output owner.
3. Start the existing recorder barrier exactly once. The consumer remains in its existing factory/retry/replay/send phase.
4. When the barrier completes, clear `pendingRecorderBarrier`, record `recorderBarrierComplete` with counts only, and arm the generation-scoped 60-second drain deadline. `ingress.finish` wakes or eventually terminates the same consumer iterator.

### C. Post-release drain and recovery

1. A factory that succeeds after release is admitted only if generation, attempt identifier, retry admission, and drain deadline are still current. Otherwise cancel the returned session and suppress it.
2. A retry sleep that wakes after release creates the successor attempt under the same checks. It is not cancelled merely by `captureClosed`.
3. Replay continues through the complete journal. Historical packet indices stay suppressed by `ResponseOutputLedger.reserve`; an unacknowledged index can become owned. Each successful replay response resets the failure streak.
4. After replay, consume all queued packets and the recorder tail. Post-release packet responses pass the same content and route checks as held responses and may reconcile output.
5. On a recoverable factory/packet/finish failure, retire/cancel the exact attempt once, increment the consecutive failure streak, wait using the existing capped backoff (clamped to remaining drain time after release), and create a fresh attempt. Do not call the current `completeAfterRecoverableRelease` shortcut.
6. On ingress exhaustion, call action 2 behind the finish watchdog. A recoverable finish failure uses the same fresh-session/full-journal recovery path; it does not finalize the last partial as success.

### D. Terminal authority and cleanup

1. For a non-empty safe action-2 final, reserve terminal authority separately from packet-index ownership, claim it in the current generation's ledger, and compute privacy-safe replacement metrics.
2. AX route: send `.final(text)` to `CursorTextSession`; this replaces/verifies the owned range and commits it.
3. Fixed-PID keyboard route: pass `finalText: text` and the ledger's prior safe snapshot to `CurrentFocusAppendSession.finalize`. `finalize` must reconcile a differing final with the same exact replacement transaction before closing monitoring; equal text commits without another synthetic event.
4. Close response admission only after the terminal route returns. Record the terminal receipt, then perform normal cleanup.
5. A terminal empty/cancelled result closes the owner without a new mutation, preserves the last safe snapshot, and publishes the appropriate fixed feedback. A terminal unsafe/security-rejected result follows the existing fail-closed outcomes.

## Production file plan

### 1. `FeishuSpeech/Models/StreamingSpeechModels.swift`

Add a small value-only `StreamingDrainPolicy` (or equivalently named struct) rather than scattering constants through the coordinator:

- production defaults: operation timeout 30 seconds; post-barrier release drain 60 seconds;
- method to clamp an operation/retry delay to a remaining drain budget;
- keep `StreamingRetryPolicy` unchanged except that its ordinal is now the consecutive failure streak supplied by `MainViewModel`.

Do not add a transport dependency or public API. Pure policy tests belong in `StreamingCoordinatorStateTests`.

### 2. `FeishuSpeech/ViewModels/MainViewModel.swift`

This file owns the lifecycle change.

- State fields:
  - replace ambiguous `sealStarted` checks with `captureClosed`;
  - rename `retryOrdinal` to `retryFailureStreak`;
  - add monotonic `nextAttemptIdentifier` / current attempt identifier;
  - add a generation-scoped post-release drain task/deadline;
  - inject policy timeout values (or a policy value) through the existing internal initializer for fast deterministic XCTest coverage.
- `beginStreaming(identity:)`: reset the new fields, open both admissions, and capture/arm output ownership before any response can be delayed until after release.
- `configureUnboundCursorFallback`, `prepareContinuousOutputIfNeeded`, and `armCurrentFocusAppendSession`: ensure one fixed PID is captured during the active generation and forbid first-time rebinding once `captureClosed` is true. Existing AX final-only binding stays tied to its captured destination token.
- `consumeAudio`, `createStreamingSession`, `runStreamingAttempt`, `replayJournal`, `consumePackets`, and `waitForRetryIfAdmitted`: remove release as a stop condition; gate by identity, attempt token, admission, task cancellation, and remaining drain budget instead. Preserve journal ordering.
- `consumePackets` and `replayJournal`: after any returned nonfailed packet event, reset `retryFailureStreak` before output classification. Do not reset it on factory success or failed events.
- `finishConsumedAudio`: return a typed attempt result (`completed`, `retry`, `terminalFailure`) to the outer loop so recoverable action-2 failure can create a fresh session and replay all captured audio. Remove the normal-flow use of `completeAfterRecoverableRelease`; delete that helper once callers are migrated.
- `beginSealing(identity:)`: only close capture/start the barrier and sealing UI. On barrier completion arm the drain deadline; never close recognition/output admission here.
- `recordHeldRecognitionIfEligible` / rename to `recordUsableRecognitionIfEligible`, `classifyPacketAdmission`, and ledger checks: admit current-generation packet responses after release while the drain is active.
- `handleFinal`, `finalizeExistingOutputOwner`, and response receipts: admit the terminal snapshot as authority, route `.final` to AX, pass non-nil `finalText` to keyboard finalization, then close admission. Do not finalize with `nil` when a safe action-2 snapshot exists.
- `completeNormally`, `terminateAbnormally`, `clearInteractionReferences`, `closeRetryAdmission`, `resetService`, sleep/wake, and `cleanup`: cancel both operation and drain watchdogs, close response admission, and retain the current early identity invalidation on true abnormal cleanup.
- Add a private coordinator-owned operation race used only around provider factory, `sendAudioPacket`, and `finish`. Each watchdog carries generation + attempt + phase. Timeout wins once, cancels only that factory/attempt, returns typed timeout to retry logic, and ignores a late result. Do not move deadlines into `CursorTextSession`, `CurrentFocusAppendSession`, `AudioRecorder`, or global `URLSession` configuration.
- Add privacy-safe phase/retry receipts (see diagnostics section). Never interpolate raw `Error.localizedDescription` into these receipts.

No new `RecordingState` is required: `.streaming` remains held capture and `.sealing` already describes post-release recognition/output drain.

### 3. `FeishuSpeech/Services/CurrentFocusAppendSession.swift`

Make `CurrentFocusAppendSession.finalize(finalText:lastAcceptedText:generation:)` authoritative without weakening any gate:

- validate generation/open state before work;
- choose usable `finalText` first, then the last accepted snapshot only when final is contentless;
- if the final differs from `previousSnapshot`, execute the existing `Character`-based `postReplacement` path while monitoring is still armed;
- resample fixed PID, captured-destination validation, Secure Input, and interference epoch before, during, and after posting exactly as `applyOpaqueHypothesis` does;
- only then close monitoring and return `exactCommitted` or `suffixCommitted` as applicable;
- on destination/security/interference/delivery uncertainty, preserve visible text, close, and return the existing preservation outcome; never rollback or recapture a destination;
- equal final text closes with `exactCommitted` and emits no duplicate keys.

Prefer extracting one private replacement primitive shared by `applyOpaqueHypothesis` and `finalize`; do not duplicate the safety checks or change `FinalTextCurrentFocusEventPosting`.

### 4. Explicit no-change surfaces

- `FeishuSpeech/Services/CursorTextSession.swift`: its existing `.final(text)` verified-range commit is the required AX mechanism; only caller behavior changes unless tests expose a defect.
- `FeishuSpeech/Services/AudioRecorder.swift` and `ByteBoundedAudioIngress.swift`: the existing stop/delegate barrier and tail flush are correct and should not be rewritten.
- `FeishuSpeech/Services/FeishuStreamingSession.swift` and `StreamingSpeechProvider.swift`: keep protocol and Feishu wire semantics unchanged. Coordinator watchdog cancellation should use existing `cancel()`. Change this actor only if a real cancellation test proves its existing active-request cancellation cannot release a watched operation.
- `TextInputSimulator.swift`, `HotKeyService.swift`, and physical-interference epoch code: no behavioral changes. Exact Backspace/replacement posting and Fn generation state stay intact.

## Test mapping (separate custody, RED before production)

### `FeishuSpeechTests/StreamingMainViewModelTests.swift`

1. `test_releaseDrainsInFlightPacketThenAppliesAuthoritativeFinalOnAXRoute`
   - held snapshot, held in-flight tail response, Fn-up, authoritative action-2 final;
   - assert AX replacements occur in order and final exactly once;
   - inject old-generation and post-cleanup callbacks and assert no further write.
2. `test_releaseFinalizesKeyboardReplacementWithAuthoritativeActionTwoTextExactlyOnce`
   - assert finalization receives the non-nil terminal text and one existing owner; no one-shot/pasteboard fallback.
3. Add a real `CurrentFocusAppendSession` integration assertion (or map it to its dedicated suite) where final changes the last characters; assert exact grapheme Backspaces and suffix output, fixed PID, and no duplicate event for an equal final.
4. `test_releaseDuringRecoverableBackoffReplaysCapturedPacketAndFinishesSuccessor`
   - release while backend `10024` backoff is waiting;
   - successor replays journal, obtains snapshot, calls action 2, and reaches terminal cleanup.
5. Add release-during-factory and release-during-replay variants. Hold each phase, release, complete the recorder barrier, then let it recover; assert no new generation, no journal loss, and final output.
6. `test_successfulPacketAfterRepeatedBackend10024ResetsRetryBackoffStreak`
   - expect `250 ms`, `500 ms`, successful ACK, then `250 ms` for the next failure.
7. Add hanging factory, hanging packet, and hanging finish tests using short injected operation deadlines. Each must cancel only its current attempt, enter typed recovery, and either succeed on a successor or reach the explicit terminal policy; no indefinitely active state.
8. Add post-release drain-expiry tests with short injected budget:
   - usable output exists -> it is preserved and partial-preserved feedback is shown;
   - no usable output -> one fixed streaming failure;
   - late completion after expiry -> no mutation.
9. Add contentless/unsafe/security/interference terminal cases to prove terminal authority does not bypass current fail-closed policy.
10. Update or replace tests that currently require release to close retry/admission (`test_releaseSealsSnapshotAdmissionBeforeLatePartialAndFinalCallbacks`, release-during-backoff/factory/replay cancellation tests, and recoverable-finish-after-seal tests). Do not retain contradictory old-contract assertions.
11. Assert phase/retry receipt formatting through an injected receipt sink if logger capture is impractical; payloads may contain only typed metadata and counts.

### `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`

- final revision uses exact `Character` count for Backspaces and posts the replacement suffix;
- final extension posts only the suffix and returns `suffixCommitted`;
- equal final emits no keys and returns `exactCommitted`;
- final-only first text uses the PID captured when the owner was armed;
- physical interference, tap loss, PID drift, captured AX destination loss, and Secure Input before final all preserve prior text and emit no later keys;
- an interference epoch change between synthetic pairs stops all later pairs, preserving the existing atomic pair guarantee.

### `FeishuSpeechTests/StreamingCoordinatorStateTests.swift`

- policy defaults are 30-second operation / 60-second post-barrier drain;
- remaining-budget clamping never schedules work beyond the drain deadline;
- retry failure streak resets independently of monotonic attempt identity.

### Existing suites that must remain green

- `FeishuStreamingSessionTests`: request sequence/action semantics and bounded cancel/abort;
- `StreamingAudioIngressTests` and `AudioRecorderStreamingIntegrationTests`: queued callback barrier and tail flush;
- `CursorTextSessionTests`: AX verified-range replacement/commit;
- `FinalTextOutputSecurityTests` and `CurrentFocusAppendSessionTests`: Secure Input, fixed PID, event-pair, and interference guarantees;
- `HotKeyServiceTests`: Fn state/generation and sealing successor rejection.

## Privacy-safe diagnostics contract

Add one coordinator receipt function with a typed phase and typed failure class. Suggested public log fields:

- `generation`, monotonic `attempt`, `phase`;
- `captureClosed`, `recorderBarrierComplete`;
- `journalPackets`, `acknowledgedPackets`, `backlogPackets`;
- `retryStreak`, scheduled delay milliseconds;
- operation kind (`factory`, `packet`, `finish`) and outcome (`started`, `acknowledged`, `recoverableFailure`, `terminalFailure`, `timedOut`, `cancelled`, `lateSuppressed`);
- safe failure kind (`network`, `timeout`, HTTP status, backend code, authentication, malformed, identityMismatch, cancelled, unknown`);
- elapsed milliseconds and cleanup reason (`terminalFinal`, `emptyFinal`, `drainExpired`, `security`, `permission`, `lifecycle`, `reset`, `failure`).

Explicitly forbidden: recognized text, text hashes, response body/message, audio bytes, credentials/tokens, Feishu stream ID, request headers, clipboard/target content, AX element values, or target application text. Existing response receipts may retain only length/count/diff metrics.

Minimum diagnostic sequence for one generation:

```text
generationStarted -> captureConfigured -> captureStarted
factoryStarted -> factoryReady
replayStarted/replayCompleted (when needed)
packetStarted -> packetAcknowledged ...
releaseRequested -> recorderBarrierComplete -> drainDeadlineArmed
finishStarted -> terminalFinalAccepted/emptyFinal
outputFinalized -> cleanup
```

Recovery inserts `operationTimedOut` or `recoverableFailure -> retryScheduled -> attemptRetired -> factoryStarted`. A successful packet receipt must show `retryStreak=0`. Late attempt/generation completions record `lateSuppressed` with counts only.

## Dependency-safe implementation order

1. **TDD custody:** land the RED lifecycle/final/retry/watchdog/privacy tests and record the failing baseline. Test authors do not edit production.
2. **Pure policy:** add `StreamingDrainPolicy` and its state tests. This is consumed by the coordinator and is the only production task independent of output finalization.
3. **Keyboard terminal primitive:** update `CurrentFocusAppendSession.finalize` and make its dedicated safety tests green. This touches a different production file and can proceed independently of the coordinator lifecycle because the existing protocol already accepts `finalText`.
4. **Coordinator lifecycle:** split capture closure from response/retry closure, continue factory/backoff/replay/in-flight/tail work after Fn-up, and route terminal authority. This consumes steps 2 and 3.
5. **Retry liveness:** separate monotonic attempt identity from consecutive failure streak and reset the streak on packet ACK. This shares `MainViewModel.swift` with step 4 and must be applied in sequence, not concurrently.
6. **Watchdogs and receipts:** wrap factory/send/finish with attempt-scoped deadlines, add the post-barrier drain deadline, and emit privacy-safe phase/retry receipts. This depends on the new lifecycle/attempt tokens and must follow steps 4-5.
7. **Independent review:** correctness/concurrency reviewer verifies single terminal mutation, attempt cancellation races, and cleanup ordering; security reviewer verifies fixed PID, Secure Input, interference epoch, unsafe text, and log privacy.
8. **Documentation/release:** after tests prove behavior, update `README.md`, `CHANGELOG.md`, `docs/architecture.md`, and `docs/api.md` with the verified release-drain/retry policy; then run full validation and build/install the next Release under the workflow's existing release mission.

Genuinely independent work is limited to: test authorship versus production, the pure policy model versus keyboard finalization, and later documentation drafting from already verified receipts. Coordinator lifecycle, retry identity, watchdogs, and coordinator receipts all modify and consume the same `MainViewModel` state and must be integrated in order.

## Failure routing and rollback gates

- If a RED test cannot distinguish capture close from true cleanup, improve the fake/seam; do not weaken the generation checks.
- If the factory/send/finish timeout race can await a noncooperative loser indefinitely, reject that implementation. The first terminal result must resume once, cancellation must be attempt-scoped, and late completion must be suppressed by generation+attempt.
- If keyboard final reconciliation would require a new PID, cursor sample, pasteboard fallback, or rollback after uncertain delivery, preserve the prior snapshot and return the existing preservation outcome instead.
- If a retry implementation drops a journal entry or action 2 can run before the tail ACK, keep the issue RED; do not shorten the drain to make the race disappear.
- If privacy review finds transcript, body, credential, target text, or a content-derived hash in a new receipt, remove it before any UAT build.
- The rollback unit is the complete lifecycle change. Do not ship terminal authority without post-release admission, or post-release retry without bounded watchdog/cleanup, because either partial change recreates truncation or silent-active failure.

## Exact validation sequence

Use an isolated DerivedData path so concurrent Xcode state cannot contaminate the verdict:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-release-drain-dd -only-testing:FeishuSpeechTests/StreamingCoordinatorStateTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/CursorTextSessionTests -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-release-drain-dd -only-testing:FeishuSpeechTests/FeishuStreamingSessionTests -only-testing:FeishuSpeechTests/StreamingAudioIngressTests -only-testing:FeishuSpeechTests/AudioRecorderStreamingIntegrationTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-release-drain-dd test
swiftlint --strict
xcodebuild -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/feishuspeech-issue27-release-drain-debug build
xcodebuild -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/feishuspeech-issue27-release-drain-release build
```

Release installation and owner UAT occur only after these gates and independent review pass. Automated validation must not launch the app or request macOS permissions.

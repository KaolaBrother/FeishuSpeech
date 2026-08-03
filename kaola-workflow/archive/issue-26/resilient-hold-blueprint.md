# Issue #26 resilient hold architecture blueprint

## Outcome

Implement one generation-owned **resilient hold**: after the Fn gate opens, recoverable
transport/session failures do not end the interaction or publish an error. The coordinator aborts
the failed provider stream when it was established, waits with bounded exponential backoff, creates
a fresh stream, and replays the ordered audio already captured for the same hold. This continues
until one of these terminal boundaries wins:

- Fn release or the existing 60-second cap seals capture and closes admission to another retry;
- a successful current attempt drains the sealed audio and returns one final result;
- a non-recoverable authentication, configuration, capture, permission, or security failure ends
  immediately with one fixed-content outcome;
- reset, sleep/wake, app cleanup, or generation invalidation cancels retry work and tears down once.

The current live AX writer already replaces opaque partials while Fn is held. The smallest safe
cursor extension in this issue is one opportunistic AX bind at the first non-empty partial when
startup was unbound, after which the destination is fixed for that hold. Blind CGEvent deletion,
Backspace/selection synthesis, and repeated paste are excluded. Universal continuous replacement
in AX-unsupported controls requires an input-source/IME composition provider and is deferred behind
an explicit product, signing, packaging, and permission decision.

This blueprint changes no production or test file. It is the dependency and test contract for the
separate test owner, implementer, reviewers, and documentation owner.

## Evidence and authoritative boundary

The live evidence proves:

- one stream accepted `action=1, sequence=0` and `action=0, sequence=1`;
- `action=0, sequence=2` then received HTTP 200 with business code `10024`;
- three later, genuinely new streams received the same code on `action=1, sequence=0`;
- every rejected response produced one application error state, not a recursive notification;
- no failed established stream emitted action 3 because `recordFailureIfActive` set `.failed`
  before `MainViewModel` called `cancel()`, and `cancel()` returned for every terminal state.

Current official Feishu/Lark material confirms 100–200 ms audio chunks, sequence starting at zero
and increasing by one per request, actions 1/0/2/3, a tenant-wide 20-stream maximum, and code zero
as the only success contract. It does **not** define `10024`, specify an inter-request delay, or
promise that abort/retry/replay recovers this response. Therefore:

- keep the current 6,400-byte (200 ms) packets and 3,200-byte minimum sealed tail;
- do not label `10024` as rate limiting, packet pacing, leaked-stream quota, or any other unproven
  provider meaning;
- classify `10024` as retryable only as a narrow, user-selected client recovery policy backed by
  the observed failure, not as an official Feishu guarantee;
- retain privacy-safe action, sequence, HTTP status, response byte count, business code, attempt,
  and delay diagnostics; never log transcripts, audio, credentials/tokens, stream IDs, focused
  text, application/window titles, or clipboard contents.

## Verifiable success criteria

1. A recoverable failure while Fn remains held causes no `.error`, no `HotKeyService.setError`, no
   overlay dismissal, no recorder cleanup, and no user notification.
2. A failed established session attempts exactly one bounded action 3 before a new session can be
   created. A failed first action 1 that was never accepted sends no action 3.
3. At most one HTTP request and one provider stream are active client-side at any time.
4. A fresh retry session has a fresh stream ID, starts at action 1 / sequence 0, and receives every
   retained packet in original order before it receives newer live packets.
5. Capture continues during abort, backoff, and replay. Audio is never dropped, reordered, or sent
   through the whole-file endpoint. Existing ingress overflow remains an explicit terminal capture
   failure.
6. Retry delays are hold-wide exponential backoff with bounded jitter and a hard cap. Release,
   duration cap, reset, sleep/wake, permission/security loss, capture failure, and cleanup cancel a
   pending delay and prevent a later retry from starting.
7. Fn release does not cause the first visible insertion on a live AX target: distinct non-empty
   partials have already replaced the one owned range while state is `.streaming`.
8. Retried replay responses do not visibly walk the target backward through old hypotheses. Only
   the latest accepted replay hypothesis is offered after the attempt catches up to the retained
   frontier.
9. A non-empty final is authoritative and commits once. An empty final or post-release recoverable
   failure preserves the last verified non-empty partial. One interaction produces at most one
   terminal feedback outcome.
10. Authentication, security, permission, invalid request/configuration, and capture failures do
    not create an outer session retry loop.
11. An unbound startup may bind once to a live AX destination at the first non-empty partial and
    then replaces continuously on that fixed destination. If AX still cannot prove ownership, no
    destructive provisional fallback is attempted.
12. Existing generation, Secure Input, `autoInsert=false`, clipboard, privacy, release/cap race,
    and successful action-2 behavior remain intact.

## State ownership

| State | Sole owner | Required invariant |
|---|---|---|
| Hold authority and released/sealed latch | `MainViewModel.activeSessionIdentity` plus `sealStarted` | Only the matching generation may mutate output, retry, finish, or report terminal feedback. `sealStarted` is monotonic. |
| Physical Fn transition and 60-second forced seal | `HotKeyService` / `MainViewModel` timer | Release and cap preserve the same identity and enter sealing at most once. They never manufacture a new generation. |
| Audio capture and pending backpressure | `AudioRecorder` plus one `ByteBoundedAudioIngress` | Capture is created once per hold and remains attached across provider attempts. The ingress is not failed merely because one provider attempt fails. |
| Replay journal | The single `consumerTask` in `MainViewModel` | Append each packet yielded by ingress exactly once, retain capture order, never mutate packet bytes, and enforce the existing 1,920,000-byte/60-second interaction budget. No second task reads ingress. |
| Current provider attempt | `MainViewModel.activeStreamingSession` | Contains only the newest session. The old session is cancelled/aborted and cleared before the provider may create the next one. |
| Per-stream action, sequence, token refresh, request serialization, and abort | `FeishuStreamingSession` actor | One request gate; sequence advances only after accepted responses; one same-sequence initial-token refresh; one action 3 at most; no action 3 after a successful action 2. |
| Retry ordinal and pending delay | `consumerTask`, with a coordinator-held cancellable delay task | Ordinal is monotonic for the whole hold and is not reset by a short-lived accepted packet. Release cancels the delay without cancelling already active useful work. |
| Last usable recognition | `MainViewModel` | Retain only the latest non-contentless accepted opaque value for fallback/finalization. Empty partials never erase it. |
| Provisional target ownership | `CursorTextSession` | The first successful write fixes process, element, range, caret, generation, and owned text. Every later write verifies them; invalidation never retargets or rolls back. |
| Terminal feedback | `MainViewModel` | One terminal path claims the generation before cleanup. Recoverable in-hold failures publish nothing. |

Do not move retry authority into `FeishuStreamingSession`. That actor represents exactly one Feishu
stream ID and cannot safely decide whether Fn is still held, whether audio should be replayed, or
whether a generation has been invalidated. Do not restart `AudioRecorder` for a provider retry;
doing so creates an audio gap and races the physical hold.

## Failure classification

Preserve sanitized numeric metadata in `StreamFailure` so the coordinator can decide without raw
response bodies or messages. Change the collapsed cases to carry safe values where needed:

- `httpStatus(Int)` instead of `.httpStatus`;
- `backend(code: Int)` instead of `.backend`.

Add an internal disposition used only by the resilient hold coordinator:

| Failure | Disposition while held | Reason and policy |
|---|---|---|
| `StreamFailure.network`, `.timeout`, `.malformedResponse` | retry fresh session | A new serialized stream may recover; repeated failures still use hold-wide backoff. |
| `StreamFailure.httpStatus(408/425/429/5xx)` | retry fresh session | Transient HTTP class. No parallel requests; capped backoff applies. Do not claim `10024` is this class. |
| `StreamFailure.backend(code: 10024)` | retry fresh session | Explicit product policy for the verified incident; the provider meaning remains unknown. |
| Other backend code | terminal unless the official-code lookup later adds it to a reviewed allowlist | Avoid request-storming a deterministic provider rejection. |
| `StreamFailure.authentication` | terminal after the existing one same-sequence first-packet refresh | Outer session recreation must not repeatedly fetch tokens or retry invalid credentials. |
| `StreamFailure.invalidRequest`, generic 400/401/403/404, `.responseIdentityMismatch` | terminal | Client/configuration/protocol class. Identity mismatch is currently unreachable because response echoes are intentionally ignored. |
| `StreamFailure.cancelled` / `CancellationError` | control-flow cancellation | Never report and never retry after authority is gone. |
| `FeishuAPIService.APIError.networkUnavailable`, `.connectionFailed`, `.networkError`, `.timeout`, invalid/malformed transient response, token endpoint 408/425/429/5xx | retry session creation | `networkUnavailable` is rejected locally before an HTTP call; it may poll only through capped cancellable backoff, so an offline hold does not emit requests. |
| `APIError.authFailed`, `.authenticationUnavailable`, token endpoint 400/401/403, invalid credentials/configuration | terminal | One fixed authentication/configuration outcome; no outer token loop. |
| `AudioIngressError`, `RecordingFailure`, permission loss, Secure Input, secure/unverifiable target | terminal/lifecycle | Reconnecting cannot repair missing or untrustworthy audio/output ownership. |

Unknown errors default to terminal. The classifier must be exhaustively unit-tested and must not use
`localizedDescription` text matching.

## Per-session abnormal teardown and action 3

`FeishuStreamingSession` currently conflates recognition outcome with teardown eligibility. Split
those concerns without changing request serialization:

1. Retain the terminal recognition outcome (`none`, completed event, or failed typed error).
2. Add an independent exact-once abort claim. Repeated `cancel()` calls observe the claim and return.
3. On `cancel()` from an active `.none` session, claim local `.cancelled` as today. On `cancel()`
   from `.failed`, preserve the original failure for callers but still evaluate abort eligibility.
4. Abort is eligible when at least one audio packet was accepted and no action 2 completed
   successfully. Merely emitting action 2 is not successful termination.
5. If action 0 or action 2 is in flight, cancel it, wait for the same serial request gate only
   within the existing one-second total abort deadline, and then send action 3 at `nextSequenceID`.
   If the sender ignores cancellation past the deadline, return without overlapping action 3.
6. A failed action 1 before acceptance is local-only. A failed established action 0 and a failed
   action 2 each attempt one action 3. A successful action 2 never emits action 3.
7. Abort response decoding is not promoted to recognition success and does not publish text. Its
   success/failure only controls diagnostics; retry admission remains coordinator-owned.

This repair must land before coordinator retry. Otherwise each new attempt may consume another one
of the provider's documented 20 concurrent streams while the preceding failed stream was never
explicitly released.

## Audio journal, replay, and ingress backpressure

Keep `ByteBoundedAudioIngress` as the single non-blocking capture boundary. Do not create one ingress
per network attempt. The coordinator's sole consumer maintains a local ordered journal:

1. Every packet yielded from ingress is appended to the journal before its first send. If that send
   fails, the failed packet therefore remains replayable.
2. The first session sends packets as they arrive and publishes accepted non-empty partials
   immediately.
3. A retry session starts at journal index zero. It sends retained packets sequentially through the
   session actor. It never re-chunks, combines, drops, or parallelizes them.
4. During catch-up, retain only the retry attempt's latest accepted non-empty partial; do not write
   each historical replay response into the target. When the retry reaches the journal frontier,
   offer that latest opaque value once, then resume normal live partial delivery.
5. Audio captured during abort, backoff, and replay remains queued in the same ingress. Once replay
   catches up to the prior frontier, the sole consumer resumes draining queued/new packets into the
   journal and current session.
6. Fn release seals the same ingress. Its one tail packet is journaled and sent by an already active
   current attempt. Release does not create a new attempt merely to consume the tail.
7. Retained journal bytes plus not-yet-drained ingress bytes are bounded by the existing 60-second,
   32,000-byte/second interaction cap. The journal also checks its own accumulated byte count
   against 1,920,000 and fails explicitly if the timer/callback boundary ever exceeds it.
8. Existing queued-byte overflow stays terminal. Do not discard oldest audio, skip ahead to live
   packets, or silently replace replay with `file_recognize`.

The official source recommends 100–200 ms **audio chunks**, not a mandatory HTTP inter-request
sleep. Keep the 200 ms packet bytes and strict serial gate. Do not introduce an invented pacing
claim. Attempt backoff, one active stream, and one in-flight request are the request-storm controls.

## Retry algorithm and exact timing

Use one internal `StreamingRetryPolicy` value, testable without wall-clock sleep:

- first retry base: 250 ms;
- multiplier: 2;
- raw cap: 4 seconds;
- jitter factor: uniformly injected in `[0.8, 1.2]`;
- final delay clamp: `[200 ms, 4 seconds]`;
- retry ordinal: one-based and monotonically increasing for the entire hold;
- total attempt count: no independent cap, because the user selected retry-until-release; the
  60-second hold cap is the absolute bound.

Compute `raw = min(4s, 250ms * 2^(ordinal-1))`, apply injected jitter, then clamp. Avoid integer
overflow by saturating before exponentiation. Tests inject fixed jitter and a controllable sleeper;
production uses `Task.sleep`. Do not use `Double.random` directly in deterministic tests.

Per recoverable failure:

1. Re-check generation authority and task cancellation.
2. Clear `activeStreamingSession` only after capturing the failed session locally.
3. Await its bounded `cancel()`/action-3 attempt.
4. Re-check authority and `sealStarted`.
5. If sealed, do not schedule or start another session; finalize from the best accepted result.
6. Otherwise increment the hold-wide ordinal, publish only a sanitized diagnostic, and await the
   cancellable delay.
7. Re-check authority and seal again immediately before `makeStreamingSession`.
8. Create a fresh session, assign it as current only while the generation is still active, and
   replay the journal.

Do not reset the ordinal merely because the new stream accepts one replay packet; the observed
pattern accepted a prefix and then failed, so resetting would collapse into a 250 ms loop. The
ordinal naturally disappears when the hold completes.

## Release, duration cap, reset, and sleep races

### Fn release / 60-second cap

Both continue to call `beginSealing` with the same identity. That method must:

- set `sealStarted` before any await;
- cancel only the pending retry-delay child task, not the entire consumer;
- stop capture and finish ingress exactly once;
- close admission to any `makeStreamingSession` that has not already begun.

An already active attempt may drain the now-sealed ingress and issue one action 2. A session factory
call already in flight may complete and be used once, but a failure after sealing cannot start a
replacement. A delay cancelled by sealing returns control to the consumer, which finalizes from the
last accepted result instead of treating delay cancellation as a stream error.

### Reset, sleep/wake, security/permission loss, capture failure, cleanup

These paths invalidate generation and cursor ownership first, cancel the retry-delay task, fail the
ingress, cancel consumer/sealing tasks, clear references, stop capture/timer/overlay, and await the
current session's bounded cancel where the public method is async. Reset/sleep/wake return idle and
publish no stream failure. Security, permission, and capture failures keep their existing one fixed
error. Late delay completions, session factories, packets, action-3 completions, partials, finals,
and failures are no-ops because identity authority is already gone.

`cleanup()` cannot guarantee remote action 3 if the process is exiting, but it must synchronously
cancel retry admission and local capture/task ownership. Do not delay application termination on an
unbounded network operation.

## Accepted partial and final semantics

- Every code-zero packet response is accepted for stream sequencing even when its text is absent or
  contentless.
- Only a non-contentless value replaces `lastAcceptedNonContentlessText` or mutates a target.
- A partial is a complete opaque hypothesis for its current attempt, never a delta.
- During retry replay, intermediate historical partials are suppressed; the last accepted replay
  hypothesis replaces the previous visible hypothesis once catch-up succeeds.
- A non-empty action-2 final is authoritative: replace/insert once, commit cursor ownership, and
  ignore late events.
- An empty action-2 final preserves the last verified visible AX provisional. For final-only or
  unbound one-shot fallback, use the last accepted non-empty value at release if no non-empty final
  exists, subject to the existing destination, Secure Input, control-character, and copy-recovery
  gates.
- A recoverable failure after release follows the same preservation rule and does not erase a
  visible partial. If no accepted non-empty value exists, publish one fixed `流式识别失败` outcome.
- Cancellation/reset/sleep/security invalidation never redirects or copies an accepted partial.

## Single feedback policy

While Fn is held, a recoverable failure produces diagnostics only. It must not:

- call `terminateAbnormally`;
- call `HotKeyService.setError`;
- set `RecordingState.error`;
- hide/re-show the overlay;
- call clipboard recovery or `UNUserNotificationCenter`.

At most one terminal user-facing outcome is allowed:

- successful non-empty final: normal idle completion, no duplicate insertion;
- empty/missing final with a retained value: existing fixed
  `.emptyFinalPreservedPartial` completion feedback once;
- ordinary final-only delivery uncertainty: existing `.manualRecoveryCopied` once;
- authentication/configuration fatality: one fixed authentication/configuration error;
- no usable result when sealed recovery ends: one fixed streaming error;
- reset/sleep/wake/user cancellation: idle with no error.

The generation is invalidated before the terminal feedback is assigned, so late callbacks cannot
publish a second outcome. Stream failures must never use the clipboard-fallback macOS notification.

## Continuous cursor output: smallest safe scope and decision gate

### Safe scope in this repair

1. Preserve current `.live` AX behavior: first non-empty partial writes before release; revised and
   shorter hypotheses replace the one verified owned range; duplicates are no-ops.
2. When startup is truly unbound because AX capture threw or returned
   `.accessibilityUnavailable`, and `autoInsert` is enabled, allow exactly one new
   `CursorTextSession.begin()` attempt on the first non-empty accepted partial.
3. That attempt samples the then-current focus. A `.live` result becomes the fixed destination for
   the rest of the hold and immediately handles that partial. This is the only safe interpretation
   of “current cursor” available without a startup destination: focus at the first visible value.
4. A secure result fails closed. A second unavailable/final-only result keeps the existing one-shot
   release fallback. It is not retried on every partial and does not synthesize provisional edits.
5. After the first successful visible write, any PID, focused element, caret/selection, owned-text,
   Secure Input, or generation mismatch permanently invalidates automatic provisional output for
   that hold. Preserve visible text; never follow focus to another field.
6. `autoInsert=false` performs no rebind, AX write, CGEvent, pasteboard write, or recovery copy.

This closes the transient-unbound gap and guarantees continuous output where the current focused
control can actually prove AX ownership. It does **not** claim universal continuous output.

### Deferred universal behavior

`SystemFinalTextCurrentFocusEventPoster` can insert Unicode once but cannot prove or replace an
app-owned prior range. Synthesizing Backspace, Shift+Arrow, select/delete, or repeated paste can
erase user edits, split Unicode, activate controls, or target a moved caret. It is not an acceptable
implementation of continuous replacement.

Universal replacement in AX-unsupported controls requires a composition-capable input-source/IME
provider that owns marked text. That is a separate value-laden capability because it adds a target,
installation/activation steps, signing/notarization/packaging work, possible permissions, and a new
system trust boundary. Before designing it, the user must approve that product surface and a
throwaway prototype must verify marked-text update/commit/cancel behavior, Secure Input, focus
changes, app termination, Unicode, undo, and supported hosts. Until then, issue #26 can be SUCCESS
for resilient transport and safe AX continuous output but only PARTIAL for universal unbound
continuous replacement.

## Exact files and method-level changes

### Production

1. `FeishuSpeech/Models/StreamingSpeechModels.swift`
   - make HTTP status and backend business code part of sanitized `StreamFailure`;
   - add the exhaustive internal retry disposition and deterministic `StreamingRetryPolicy`;
   - keep all types `Equatable + Sendable` and keep raw/private response content out.

2. `FeishuSpeech/Services/FeishuStreamingSession.swift`
   - update `send` to throw typed status/code failures;
   - separate terminal recognition outcome from exact-once abort eligibility;
   - change `cancel`, `attemptBestEffortAbort`, request-gate release signaling, and successful-finish
     tracking so failed established action 0/action 2 can emit one action 3 while successful action
     2 cannot;
   - retain one-second total abort deadline, strict serial requests, same-sequence initial token
     refresh, relaxed response identity/data parsing, and safe diagnostic sink.

3. `FeishuSpeech/ViewModels/MainViewModel.swift`
   - replace one-shot `consumeAudio -> consumePackets -> failure teardown` with a single
     generation-owned attempt loop;
   - keep a local ordered replay journal, byte count, current attempt, hold-wide retry ordinal,
     pending retry-delay task, and last non-contentless accepted value;
   - normalize thrown failures and `.failed(StreamFailure)` events through the same classifier;
   - abort/clear failed sessions before fresh creation, suppress historical replay partials, and
     resume live delivery after catch-up;
   - make `beginSealing`, `completeNormally`, `terminateAbnormally`, reset/sleep/wake, and `cleanup`
     cancel retry admission with the race rules above;
   - change `handlePartial`, `handleFinal`, and release failure finalization so empty values preserve
     the last usable value and terminal feedback is exact-once;
   - add the one-time first-partial AX rebind for truly unbound startup; do not change the captured
     `.finalOnly` destination into a new current-focus provisional target.

4. `FeishuSpeech/Services/ByteBoundedAudioIngress.swift`
   - no behavioral rewrite is expected; retain one capture ingress across retries;
   - change only if a small read-only byte-accounting hook is needed to prove the combined replay
     budget. Do not add multiple consumers, packet replay inside storage, or drop-oldest behavior.

5. `FeishuSpeech/Services/AudioRecorder.swift`
   - no production change expected. It must continue appending to the same ingress until seal or
     terminal lifecycle cleanup.

6. `FeishuSpeech/Services/CursorTextSession.swift`,
   `FeishuSpeech/Models/CursorTextModels.swift`, and
   `FeishuSpeech/Services/TextInputSimulator.swift`
   - no blind replacement change;
   - reuse `CursorTextSession` for the one-time unbound AX bind;
   - change these files only if a typed pre-mutation/security outcome is required by a RED test;
     preserve current no-rollback and one-shot final-output security boundaries.

No `HotKeyService` production change is planned. It already preserves identity through
`.streaming -> .sealing`, ignores repeated sealing, and prevents a new hold during sealing.

### RED test files

- `FeishuSpeechTests/FeishuStreamingSessionTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`
- `FeishuSpeechTests/StreamingCoordinatorStateTests.swift`
- `FeishuSpeechTests/StreamingAudioIngressTests.swift` only for retained-budget/backpressure
  assertions if the test owner needs an ingress accounting hook
- `FeishuSpeechTests/CursorTextSessionTests.swift` only if a new typed cursor outcome is introduced

The coordinator fakes must be upgraded so the provider can return a sequence of distinct sessions
and factory errors, each session can throw per-packet/per-finish errors, and the injected retry
sleeper can be observed and released deterministically. Do not reuse one mock session for all retry
attempts; that would fail to prove fresh stream ownership.

### Documentation after behavior is green

- `README.md` and `CHANGELOG.md`: user-visible retry-until-release and safe continuous-output scope;
- `docs/api.md`: typed status/code policy, action-3-after-failure rule, fresh-session replay,
  backoff, and the explicit unknown meaning of 10024;
- `docs/architecture.md` and `docs/streaming-speech-design.md`: one capture/many serial attempt
  lifecycle, journal/frontier semantics, release races, and AX/IME capability boundary;
- new `docs/decisions/D-26-01.md`: supersede only the D-25-01 statements that established streams
  never replay and every stream failure immediately terminates the hold; preserve D-25 cursor and
  security decisions;
- `docs/decisions/D-25-01.md`: add a short superseded-by pointer rather than rewriting history;
- `docs/README.md`: link the new decision if its index is explicit.

## TDD execution plan and dependencies

Test authors and production implementers must remain separate.

### Task 1 — RED transport abort contract

Owner: `tdd-guide`.

Add failing tests proving:

- accepted action 1, rejected action 0, then repeated cancel yields actions `[1, 0, 3]`, sequences
  `[0, 1, 1]`, one abort, and maximum one active request;
- rejected first action 1 plus cancel emits no action 3;
- rejected action 2 plus cancel emits one action 3 at the unconsumed sequence;
- successful action 2 plus cancel still emits no action 3;
- a cancelled in-flight action 0/action 2 whose sender ignores cancellation never overlaps abort
  and returns by the one-second deadline;
- status/business-code errors remain sanitized and carry only safe numeric metadata.

### Task 2 — Implement session teardown

Owner: `implementer`. Depends on Task 1 RED evidence.

Modify only streaming models/session until Task 1 passes. Run the focused session suite. Do not add
coordinator retry yet.

### Task 3 — RED resilient coordinator and retry policy

Owner: `tdd-guide`. Depends on the final error surface from Task 2, but is otherwise independent of
cursor rebind RED tests.

Add failing tests for:

- 10024 after accepted packets: no early error/cleanup, old session cancel once, fresh session,
  full ordered journal replay, same generation and recorder, then live continuation;
- network loss/session-factory failure: capture remains active, no HTTP-like attempt while the fake
  reports local offline, and recovery occurs after deterministic capped backoff;
- delay series at fixed jitter, saturation/overflow safety, 200 ms minimum, 4-second maximum, and
  monotonic hold-wide ordinal;
- replay suppresses intermediate historical partials and publishes only the catch-up frontier;
- retry failures never create parallel sessions or requests;
- release during backoff cancels delay and starts no next session;
- release during an already active retry lets that attempt drain/seal once but permits no following
  retry;
- release/60-second-cap race remains one recorder stop and one final outcome;
- reset, sleep, wake, Secure Input, permission loss, and cleanup cancel delay/attempts and reject all
  late callbacks;
- authentication/invalid request/configuration/capture/overflow are not retried;
- last accepted non-empty value survives empty partial/final and post-release failure; no accepted
  value produces one fixed error only;
- no transcript or raw backend content reaches status, overlay, diagnostics, or logs exposed to the
  test surface.

### Task 4 — Implement resilient coordinator

Owner: `implementer`. Depends on Tasks 2 and 3.

Modify `MainViewModel` and, only if RED evidence requires it, a small ingress accounting surface.
Make the focused coordinator, state, ingress, and session suites pass before broad tests.

### Task 5 — RED safe continuous current-focus scope

Owner: `tdd-guide`. This test production is genuinely independent of Tasks 1–2 because it targets
cursor capability/output fakes, but it should be merged before Task 6 because both implementations
touch `MainViewModel`.

Add failing tests proving:

- startup unbound, first partial live-capable: the partial is written before sealing, a later revised
  and shorter value replaces the same range, and the current-focus final adapter is unused;
- the unbound AX rebind is attempted once only;
- unavailable/final-only rebind sends no provisional CGEvent/paste/backspace and retains one-shot
  release fallback;
- secure rebind and Secure Input activation fail closed with no insertion/copy;
- focus/PID/caret/owned-text change after first visible value preserves it, disables further writes,
  and never redirects to the new focus;
- `autoInsert=false` performs zero rebind/output work;
- two accepted partials are visibly replaced while hot-key state is still `.streaming`, before a
  `.sealing` event is injected.

### Task 6 — Implement safe AX rebind

Owner: `implementer`. Depends on Tasks 4 and 5 because it shares `MainViewModel`.

Reuse `CursorTextSession`; do not extend the CGEvent final adapter into a provisional editor. If a
RED test exposes an ambiguity between pre-mutation failure and uncertain post-mutation failure,
add the smallest typed cursor outcome and cover it in `CursorTextSessionTests` before using it.

### Task 7 — Review, docs, and validation

Depends on all behavioral tasks.

- `code-reviewer`: concurrency, exact-once terminal ownership, replay order, release races,
  successful-final regression, and scope;
- `security-reviewer`: Secure Input, focus affinity, synthetic input/control characters, clipboard,
  credential/transcript privacy, and request-storm bounds;
- `doc-updater`: transcribe the verified implementation and explicitly state the unknown 10024
  meaning and deferred IME boundary;
- `build-error-resolver`: only for build/type/lint/tool failures;
- behavior failures return to `tdd-guide`; implementation defects return to `implementer`.

## Focused RED acceptance matrix

| Scenario | Required observable result |
|---|---|
| Mid-stream 10024 while held | Failed stream action 3 once; no error; fresh stream after delay; journal replay; same capture/generation. |
| Fresh action-1 10024 repeatedly | No action 3 before acceptance; delays grow and cap; no error until release; no parallel stream. |
| Network unavailable | Local make-session check emits no network request; cancellable backoff continues until release/recovery. |
| First session partial, retry replay partials | Old visible value remains during incomplete replay; latest catch-up value replaces once. |
| Fn release during retry sleep | Sleep wakes/cancels; no new factory call; sealed fallback produces one final outcome. |
| Fn release during active retry | Current attempt may finish once; a subsequent failure cannot start another attempt. |
| 60-second cap and physical release race | One seal, one stop, one finish/fallback, no later retry. |
| Reset/sleep/wake during retry | Identity invalid first; delay/task/session cancelled; idle; late events no-op. |
| Auth/config/security/capture failure | One fixed terminal error (or idle for lifecycle reset); zero outer retries. |
| Successful action 2 | One final commit; no action 3; no duplicate current-focus final. |
| Failed action 2 | One action 3 if established; no new attempt once sealed; preserve last usable value. |
| Unbound then live AX at first partial | First visible insertion before release; subsequent opaque replacement on fixed target. |
| AX unsupported at first partial | No blind provisional output; final-only behavior retained; universal requirement reported PARTIAL. |
| Focus/caret/Secure Input changes | Fail closed before next mutation; preserve verified text; never retarget/copy on security failure. |

## Build and validation sequence

Run from `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26` after implementation, in
this order:

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/FeishuStreamingSessionTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/StreamingAudioIngressTests -only-testing:FeishuSpeechTests/StreamingCoordinatorStateTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests -only-testing:FeishuSpeechTests/CursorTextSessionTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test
swiftlint
xcodebuild -scheme FeishuSpeech -configuration Debug build
xcodebuild -scheme FeishuSpeech -configuration Release build
```

Do not launch or install the app during RED/implementation work. After local tests, lint, and both
builds pass, owner UAT must use the separately verified Release and privacy-safe diagnostics. UAT
must cover a long hold with injected/real network interruption, repeated 10024 if reproducible,
partial visibility before release, revised/shorter replacement, release during reconnect, focus
change, and Secure Input. UAT must not capture transcript contents or raw response bodies.

## Rollback and failure routing

- If action 3 regresses successful completion, retain the terminal-outcome/abort separation but
  restore the last green eligibility condition; never remove the failed-established-stream RED
  test to make the regression disappear.
- If provider UAT shows fresh-session replay worsens 10024 or consumes quota, keep exact-once abort
  and cancellation fixes, disable the narrow 10024 retry allowlist, report PARTIAL, and escalate
  sanitized request IDs/timestamps to Feishu support. Do not reinterpret nonzero code as success.
- If replay cannot catch up without ingress overflow, fail once; do not drop audio or fall back to
  whole-file recognition.
- If retry timing causes a request storm, retain retry-until-release but increase the policy cap or
  wait on an authoritative provider/network readiness signal. Do not add a hidden parallel retry.
- If first-partial AX rebind cannot prove ownership, retain final-only behavior and report the
  universal cursor requirement PARTIAL. Do not ship synthetic destructive replacement.
- Any new input-source/IME target, entitlement, installer step, dependency, or public setting is
  outside this blueprint and requires explicit user approval before architecture or implementation.

## Follow-up decision: monotonic current-focus append fallback

### Decision and superseded scope

The user explicitly rejected release-only behavior when AX cannot confirm a replaceable cursor
range and selected a narrower immediate-output fallback: bind the initial frontmost process, insert
the first hypothesis, and append only a provably new suffix. This follow-up therefore supersedes the
earlier statements in this blueprint that an unavailable/final-only rebind must always remain
release-only. It does **not** supersede the ban on synthetic deletion/selection or the deferral of a
true universal replacement/IME provider.

The fallback is **conditionally acceptable as a best-effort, insert-only capability**, for these
reasons:

- it never deletes, selects, backspaces, pastes, rewrites, or rolls back user text;
- it posts no value unless the new opaque hypothesis is either the first value, an exact duplicate,
  or an exact UTF-16 extension of what this session already attempted to emit;
- it binds one frontmost PID for the hold, fails closed on detected process change or Secure Input,
  and never redirects to another process;
- `autoInsert=true` plus the user's explicit selection authorizes this lower-confidence immediate
  insertion tradeoff; `autoInsert=false` remains zero-output.

It must be named and documented as **monotonic current-focus append**, not replacement and not
verified cursor ownership. Unlike `CursorTextSession`, it cannot confirm that an event reached the
control, read back the inserted text, detect host autocorrection, or detect a caret/focus move
between controls inside the same PID. Direct event posting also has a preflight-to-delivery race.
Those are residual, non-removable risks of the selected fallback. If the product requires original
element/caret affinity rather than stable-process best effort, this fallback must be rejected and
the IME decision remains blocking.

### Capability ordering

The coordinator chooses exactly one output capability per generation, in this order:

1. **Verified AX replacement** when `CursorTextSession.begin()` returns `.live`. This remains the
   preferred path and supports opaque revisions and shortenings.
2. **Captured final-only destination** when AX returns `.finalOnly`. Keep its captured PID/element
   final path unless the product explicitly opts that capability into monotonic append; do not
   discard a stronger captured element merely to use PID-only current focus.
3. **Monotonic current-focus append** when startup AX capture throws or returns
   `.accessibilityUnavailable`, `autoInsert` is true, Secure Input is off, and a frontmost PID can
   be bound before the first provisional event.
4. **No automatic output** when no PID is available, security is unsafe/unverifiable, event creation
   fails, or `autoInsert` is false. Recognition may continue, but release cannot use an unbound
   one-shot insertion after append ownership became uncertain.

The one-time first-partial AX rebind from the earlier scope remains useful before the first direct
event: if it becomes `.live`, promote to verified AX and never create the append session. Once any
direct Unicode event is posted, migration to AX replacement is forbidden because the app cannot
safely derive or claim the already emitted range.

### Exact comparison rule

Store the exact UTF-16 code units that were successfully handed to the event poster. Do not use
localized comparison, case folding, Unicode normalization, grapheme count, `String.count`, or a
canonically equivalent prefix test.

For emitted units `E` and new hypothesis units `H`:

- `H` empty/contentless: no mutation and no state advance;
- `E` empty: the whole safe `H` is the first payload;
- `H == E`: duplicate no-op;
- `H` begins with exactly the same UTF-16 units as `E`: post only `H[E.count...]`;
- otherwise: revision/shortening divergence; post nothing and keep `E` authoritative for later
  prefix comparisons.

Because `E` was produced from a valid complete Swift string, its boundary cannot split a surrogate
pair. A decomposed and precomposed spelling is deliberately a divergence unless its UTF-16 units
are literally identical. The entire candidate and emitted suffix must pass
`TextInputSimulator.isSafeForAutomaticPaste` so C0/C1/DEL values cannot become action-capable key
input. Despite the existing helper name, this check does not authorize or perform a paste.

The stored value advances only after the poster returns `.posted`. `.posted` means an event was
submitted, not that the host accepted it. If posting is rejected or its result is uncertain, make
the session permanently non-emitting; never resend that suffix, because a late/unknown delivery
could make the retry a duplicate.

### Protocol and state ownership

Add an internal main-actor protocol dedicated to persistent provisional output; do not overload
the one-shot `FinalTextOutput` contract:

```text
CurrentFocusProvisionalOutputSession
  applyOpaqueHypothesis(text, generation, source) -> CurrentFocusAppendOutcome
  finalize(finalText?, lastAcceptedText?, generation) -> CurrentFocusAppendFinalOutcome
  invalidate()
```

`source` distinguishes a live packet from the single replay-catch-up frontier. It does not change
prefix rules. The protocol has no clipboard dependency and no method that accepts a selection or
deletion count.

One `CurrentFocusAppendSession` owns:

- the streaming generation;
- the initial bound frontmost PID;
- exact emitted UTF-16 units;
- whether any event was posted;
- a monotonic terminal state;
- injected Secure Input sampler, frontmost-PID sampler, active-application monitor, Unicode event
  poster, and no other output mechanism.

Its internal states are:

| State | Meaning | Allowed next states |
|---|---|---|
| `armed(boundPID)` | No event posted; PID captured for this generation. | `emitting`, `suspended`, `finalized`, `invalid`. |
| `emitting(boundPID, emittedUTF16)` | At least one payload was posted; later output is exact suffix only. | updated `emitting`, `suspended`, `finalized`, `invalid`. |
| `suspended(reason, emittedUTF16?)` | Destination/security/delivery ownership became unsafe. No more events. | `finalized` or `invalid` only. |
| `finalized(emittedUTF16?)` | Release/final outcome claimed once. | `invalid` only; late values are no-ops. |
| `invalid` | Generation/lifecycle authority is gone. | none. |

A divergent or shorter hypothesis is a suppressed candidate, not by itself a terminal suspension:
later hypotheses may again be exact extensions of `emittedUTF16`. PID change, activation away,
security rejection, poster failure/uncertainty, or generation invalidation is permanent suspension.

Use typed, transcript-free outcomes:

- apply: `insertedFirst`, `appendedSuffix`, `duplicate`, `contentless`,
  `revisionSuppressed`, `unsafeTextSuppressed`, `destinationChanged`, `securityRejected`,
  `deliveryUncertain`, `staleGeneration`;
- finalize: `exactCommitted`, `suffixCommitted`, `preservedDivergence`,
  `preservedDestinationLoss`, `preservedSecurityRejection`, `noUsableText`,
  `deliveryUncertain`, `staleGeneration`.

Outcome descriptions, logging, `CustomStringConvertible`, and test failure messages must never
contain the hypothesis, suffix, final, or emitted value.

### Mutation gate and focus handling

For every first or suffix event:

1. Check matching generation and nonterminal session state.
2. Reject contentless and unsafe-control values before touching system state.
3. Require the current frontmost PID to equal the initial bound PID.
4. Require Secure Input off.
5. Immediately re-sample PID and Secure Input; both observations must still be safe/bound.
6. Call the direct Unicode poster, which performs its own final Secure Input check at the event
   creation/post boundary and posts without pasteboard use.
7. Immediately sample PID and Secure Input again. If either changed, keep the payload recorded as
   attempted but suspend all future output; never roll back or repost it.

Subscribe to `NSWorkspace.didActivateApplicationNotification` (behind an injectable monitor) for
the append session lifetime. Any observed activation whose PID differs from the bound PID
permanently suspends the session, even if the user returns before the next partial. Pre/post samples
remain authoritative for event-time races.

This handles cross-process focus change. A focus/control/caret change inside the same PID is not
observable when AX capture is unavailable; document it as the residual risk rather than claiming it
is handled. Adding global mouse/key suppression could reduce but not eliminate that risk and would
expand the event-tap contract, so it is outside this surgical fallback.

### Replay catch-up

The resilient coordinator continues to suppress every historical replay response. Only after a
new stream has successfully replayed through the retained journal frontier may it call
`applyOpaqueHypothesis` once with that attempt's latest non-empty catch-up value.

- exact duplicate frontier: no event;
- exact extension: emit only the new suffix;
- shorter/revised frontier: suppress it and keep the previously emitted units;
- retry failure before the frontier: do not call the output session at all.

After catch-up, live packet hypotheses use the same rules. Retry never resets append-session state,
bound PID, or emitted units, and a fresh provider stream never authorizes duplicate first insertion.

### Release, final, and divergence

Fn release still closes retry admission. It calls append-session finalization at most once:

- non-empty final exactly equals emitted units: commit with no event;
- non-empty final is an exact UTF-16 extension: post only the final suffix after all gates, then
  commit;
- empty final: preserve emitted text; if nothing was emitted, use the last accepted non-empty
  hypothesis only when it passes the same first-event gates;
- revised/shorter final: preserve emitted text and post nothing;
- destination/security/delivery uncertainty: preserve what may already be visible and post/copy
  nothing.

The append capability must not fall through to `routeCurrentFocusFinal`, captured paste/Cmd+V, or
`copyForManualRecovery`, because any of those can duplicate an unconfirmed provisional value or
violate the no-pasteboard requirement. If a correct divergent final must be recoverable, that
requires a separate explicit user decision to permit clipboard recovery.

Use one fixed transcript-free completion feedback for a divergent/shorter final or a terminal
retry failure with emitted provisional text, for example a new
`RecordingState.provisionalTextPreserved` whose text states that realtime text was kept because the
final revision could not be applied safely. Exact/suffix commit completes normally. Security uses
the existing fixed security error. No-output ordinary failure uses one fixed streaming/output error.
Generation invalidation precedes feedback, and repeated final/failure/release callbacks are no-ops.

### Exact file changes for the accepted fallback

1. New `FeishuSpeech/Services/CurrentFocusAppendSession.swift`
   - declare the logger required by repository rules;
   - define the internal session/factory protocols, typed state/outcomes, exact UTF-16 prefix
     logic, process/security gates, activation monitoring, finalization, and invalidation;
   - keep it `@MainActor`; no pasteboard or Accessibility range mutation dependency.

2. `FeishuSpeech/Services/TextInputSimulator.swift`
   - expose or extract the existing direct Unicode poster, Secure Input provider, and frontmost PID
     provider for injection into the append session;
   - preserve `SystemFinalTextOutput.insertAtCurrentFocusOnce` for interactions that never created
     an append session;
   - do not add deletion, selection, previous-text length, or pasteboard behavior to the poster.

3. `FeishuSpeech/Models/CursorTextModels.swift`
   - host provider-neutral capability/outcome types only if they are shared by coordinator and
     service; otherwise keep them in the new service file;
   - do not represent the append session as `CursorTextSessionState.provisional`, because that name
     implies verified AX range ownership.

4. `FeishuSpeech/Models/RecordingState.swift`
   - add one fixed `provisionalTextPreserved` completion state if existing
     `.emptyFinalPreservedPartial` wording cannot truthfully describe final divergence;
   - keep transcript content out of icon/text/status surfaces.

5. `FeishuSpeech/ViewModels/MainViewModel.swift`
   - inject a current-focus append-session factory;
   - bind the initial frontmost PID during unbound capability setup and arm at most one append
     session per generation;
   - allow the one-time first-partial AX rebind before the first direct event, then choose AX or
     append capability permanently;
   - route initial/live/catch-up hypotheses and finalization through the selected capability;
   - disable `usesCurrentFocusFinalOutput`/`routeCurrentFocusFinal` whenever an append session was
     armed or emitted;
   - invalidate append state before retry/lifecycle asynchronous cleanup and preserve one terminal
     feedback owner.

6. `FeishuSpeech.xcodeproj/project.pbxproj`
   - no manual source entry is expected for the filesystem-synchronized app group; verify target
     membership through Debug/Release builds rather than hand-editing the project unless the build
     proves otherwise.

### Additional RED tests

Create `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift` under `tdd-guide` custody:

1. First safe non-empty partial posts the whole value once without pasteboard access.
2. Exact duplicate posts nothing.
3. Longer exact UTF-16 hypotheses post only each unseen suffix; concatenated posted payloads equal
   the latest emitted hypothesis.
4. Shorter and revised hypotheses post nothing; a later exact extension of the last emitted value
   may append again.
5. Precomposed/decomposed text is not treated as an exact prefix; emoji surrogate pairs, ZWJ
   sequences, CJK, and RTL suffixes are not split or duplicated.
6. C0/C1/DEL in either first value or suffix posts no event and triggers no paste/copy.
7. Any preflight or immediate recheck PID mismatch posts nothing and permanently suspends output.
8. Activation away and back is still permanent suspension. Stable same-PID samples permit output,
   with a test explicitly documenting the unobservable same-process caret risk.
9. Secure Input at any pre/post/poster sample posts nothing further, copies nothing, and returns a
   typed security outcome.
10. Poster failure/uncertainty never advances in a way that permits resend and duplicate output.
11. Stale generation, invalidate, repeated finalize, and late values are no-ops.
12. Final exact match posts nothing; final extension posts suffix once; final revision/shortening
    preserves emitted text and returns fixed-feedback disposition without pasteboard recovery.

Extend `StreamingMainViewModelTests.swift`:

13. Truly unbound interaction writes first and extending partials while hot-key state is still
    `.streaming`; release is not the first insertion.
14. Retry replay produces zero historical writes and at most one catch-up suffix; a failed replay
    before frontier produces none.
15. A fresh stream does not reset append state or duplicate the first value.
16. `autoInsert=false` creates no append session, posts no event, and touches no pasteboard.
17. PID change, Secure Input, reset, sleep/wake, release/retry race, and generation invalidation
    result in one feedback/cleanup and no late output.
18. Divergent final and empty final preserve attempted realtime text, never call
    `insertAtCurrentFocusOnce`, `insertOnce`, or `copyForManualRecovery`, and publish one fixed
    transcript-free completion result.
19. When first-partial AX rebind succeeds before any event, verified AX replacement wins and the
    append poster remains unused; after one event, no AX migration occurs.
20. Existing captured `.finalOnly` tests remain unchanged unless the user separately selects
    append behavior for that stronger captured-element capability.

This test production is independent of transport action-3 tests, but its implementation depends on
the resilient coordinator because both write `MainViewModel`. Land RED tests in parallel if useful;
implement session teardown, then coordinator retry, then append integration in that order.

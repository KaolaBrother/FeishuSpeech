# Architecture

Document system boundaries, major components, data flow, and deployment shape.

## Streaming speech and review-first architecture (issues #25/#26/#27/#28/#38/#39/#40)

Issue #25 accepted the initial design, issue #26 implemented the generation-bound streaming
pipeline, issue #27 corrects held response assembly to complete snapshot replacement, and
issue #28 splits capture from recognition so PCM is journaled even while Feishu factory hangs.
Issue #38 adds the review-first route as an independent third asynchronous axis, issue #40 adds an
application-bound fallback for ordinary non-secure AX misses and makes the review authority durable.
Every accepted interaction now uses that one preview/output route; the old issue #27 writer remains
only as dormant historical service code and cannot be restored through settings:

```text
HotKeyService
  -> MainViewModel (@MainActor generation owner)
      -> capture line: AudioRecorder -> byte-bounded PCM ingress -> HoldPacketJournal
      -> recognition line: factory / one send loop over HoldPacketJournal
          -> snapshot/replay ledger -> one fresh FeishuStreamingSession actor per attempt
      -> review line (all interactions): read-only streaming -> read-only sealing -> editable -> confirming
          -> explicit real UI intent -> captured original app + (exact AX selection | current focus)
             -> one tagged, modifier-free Unicode text pair to the captured PID
      -> legacy writer types (not constructed by accepted interactions): CursorTextSession or CurrentFocusAppendSession
```

If bounded drain expires before authoritative action 2, a safe non-empty latest snapshot may branch
from read-only sealing into durable `ReviewReadOnlyPhase.recovery` in the same panel. This recovery
surface is non-authoritative and LF-preserving: it has no editor, Send, qualified Return, or delivery
callback. Only action 2 plus the recorder barrier may continue the review line into authoritative
`.editable` and `confirming`.

The production hot-key state is `idle -> pending -> streaming -> sealing -> idle | error`.
`pending` retains the 0.3-second gate. `streaming` owns one recorder/ingress, one ordered packet
journal, one generation-scoped snapshot/replay ledger, at most one active Feishu session, and no
target writer before explicit review confirmation. A recoverable attempt
failure leaves the hold generation and capture alive, aborts an established failed stream once,
backs off, and replays the journal through a fresh serial session. In-attempt transport cancel
(`CancellationError`, `URLError.cancelled`, or transport-origin `StreamFailure.cancelled` while
retry is open and the attempt is current) classifies as recoverable timeout. Generation cancel
(`closeRetryAdmission`, identity invalidate, reset, sleep/wake, or the session-operation admission
guard) stays terminal `.cancelled`. Fn release or the 60-second cap
enters `sealing` and closes capture, but keeps the same generation's response/retry authority alive.
After the recorder crosses its callback barrier and flushes at most one audio tail, a 60-second
post-release drain budget covers queued/tail packets, recoverable fresh-session replay, and the
authoritative action-2 final. In the review route, action 2 plus that barrier freezes one draft in
the same panel; completion closes speech-session resources without revoking draft authority.
A new hold
cannot start while sealing. Reset, sleep/wake, cancellation, or terminal lifecycle failure
invalidates the active generation before cleanup so late callbacks are inert.

The legacy `reviewBeforeInsert` and `autoInsert` booleans remain Codable/decode-compatible, but both
values of both keys are runtime-inert. Every accepted Fn interaction captures a complete original
application identity before audio/network startup and opens
`idle -> streaming(read-only) -> sealing(read-only) -> editable -> confirming`.
An exact AX cursor/selection is preferred; an ordinary non-secure strict-AX miss binds the same
complete application for fixed-PID current-focus delivery. No setting can arm a live cursor writer,
keyboard writer, direct AX setter, or clipboard recovery path. Secure input, lost trust, incomplete
identity, PID reuse, or identity drift remains terminal.

### Streaming audio boundary

`AudioRecorder` sends converted 16 kHz mono signed Int16 PCM to
`ByteBoundedAudioIngress`, which coalesces capture-order bytes into 6,400-byte elements
(about 200 ms) before entering a non-blocking async stream. The retained 60-second cap is
1,920,000 bytes / 300 elements. This is a byte/duration bound, not a raw callback-count bound.
The ingress owns queued packets, pending coalescing bytes, delivered replay-retention accounting,
terminal state, and waiters under one lock. In production, drained packets remain charged because
the journal retains them for replay; the queued, pending, and delivered captured-byte total cannot
exceed 1,920,000 bytes. Explicit non-replay users still release exact capacity on dequeue. After the
real audio callback queue barrier, an established stream may pad its final non-empty tail to the
3,200-byte (100 ms) local minimum without charging generated silence as captured audio.
Overflow fails the hold explicitly; the pipeline never drops, reorders, re-chunks, or sends PCM
packets in parallel. After `beginStreaming` starts capture, a dedicated capture-drain task is the
sole ingress iterator: it appends every drained packet to a generation-scoped `HoldPacketJournal`
and never awaits factory, packet send, or finish. Recognition is a second unstructured `Task` that
waits on the journal (`waitForPacket(atOrAfter:)`), using one send loop from `sent = 0`. A fresh
attempt still sends those exact packet elements from index 0 while the same capture and ingress
continue accepting audio. `markCaptureComplete()` runs only after a successful `ingress.finish`;
iterator throw / `ingress.fail` cancels waiters and does not emit action=2. Production still uses
`retainsDeliveredPacketsForReplay: true`, so occupancy includes retained delivered bytes and peak
PCM is about 2× (ingress retain + journal). Overlay copy stays `正在聆听…` / `正在完成识别…`.

### Streaming transport boundary

`FeishuStreamingSession` is an actor with an explicit FIFO request gate. It owns stream ID, cached
token snapshot, sequence number,
first-packet acknowledgement, terminal intent, active request, and completion state. It serializes
`action=1` open, `action=0` continuation, `action=2` finish, and bounded best-effort `action=3`
abort requests; action 3 has one total one-second best-effort deadline and cannot overlap an audio
or finish request. Recognition outcome and abort eligibility are independent: a failed action 1
before acceptance needs no abort; a failed established action 0 or action 2 may emit action 3 once;
a successfully completed action 2 forbids it. Only the exact known invalid-token business code in
a bounded HTTP 400/401 response may refresh inside the first session, retrying that same first
action and sequence once.

The coordinator, not the transport actor, owns retry. Recoverable failures create a fresh stream
after consecutive-failure exponential backoff (250 ms base, doubling to a 4-second cap; jitter produces a
200 ms minimum). It serially replays the journal from zero. Each response carries the stable packet
index used for output ownership. Already-owned historical indices never own output again,
while a previously failed unowned index may claim once when replay first succeeds. Every successful
packet acknowledgement, including replay acknowledgement, resets the failure streak to zero;
monotonic attempt identity remains separate.

Streaming factory, token refresh, and `stream_recognize` POSTs use a per-attempt
`TransportAttemptContext`. Keep-alive is primary. The send path is `BoundTLSSocket`: bound UDP/53
DNS on the runtime wifi/wired interface (DHCP option 6, then recursor hostnames `dns.alidns.com` /
`public1.114dns.com`), skip `198.18.0.0/15` via bitmask, TCP `IP_BOUND_IF` to remaining A records,
CFStream TLS with peer name `open.feishu.cn` and chain validation on. There is no custom verify
block, no `en0` string, no CDN IP list, and no dotted-quad literals. `open.feishu.cn` is not
resolved with system `getaddrinfo`. A connected socket whose local IPv4 has prefix `198.18.` is
closed without HTTP. Slice budget fields are unchanged (factory 8+7+1 < 18, packet 14+14+1 < 30,
finish 15+15+1 < 45); per-request keep-alive deadlines are **direct** slices. Coordinator outer
backstops remain factory 18 s, packet 30 s, and finish min(drain, 45 s). Streaming no longer
hard-gates on `NWPathMonitor`; a tenant-token POST may proceed while the path is unsatisfied, and
is not sent if TLS to `open.feishu.cn` fails.

A keep-alive connect-class / no-HTTP miss **rethrows** and does **not** hop factory/packet/finish
to URLSession. Completed HTTP, including 4xx, does not hop. `CancellationError` does not hop.
Keep-alive leftover is sliced at the raw framed message end (Content-Length or complete chunked
trailers), not decoded `body.count`. Keep-alive success is sticky-direct for the rest of the
attempt. A new attempt context starts on keep-alive again. Abort uses keep-alive when a session is
present; URLSession only when keep-alive is absent. A first-send keep-alive miss on the production
path drops that session; coordinator outer retry reconnects on a new context. A mid-attempt
sticky-direct drop still does. Whole-file `recognizeSpeech` keeps the separate `executeURLRequest`
path. There is no whole-file fallback or parallel request chain.

Each successful response exposes one complete opaque recognition snapshot. Packet-index replay
ownership is independent: each eligible journal index may be admitted once, but an equal snapshot
does not mutate output, and a different snapshot replaces the held recognition state. A replayed
historical index remains suppressed even if a later attempt returns different text.

The response trust boundary deliberately differs from the request identity boundary. Requests
still carry the session-owned `stream_id`, `sequence_id`, and action, but code-zero responses do
not have to echo matching IDs. The parser prefers `data.recognition_text`, falls back to
`data.text`, and maps missing `data`/text to an empty event, matching KaolaTerminal's proven
streaming implementation. Nonzero business codes and malformed JSON fail that transport attempt;
the coordinator retries only its explicit recoverable subset. Business code `10024` is in that
subset because of the observed failure sequence, but its provider meaning is unknown: current
official Feishu/Lark documentation and SDK do not define it.

These packet sizes, tail padding, lowercase stream IDs, same-sequence token retry, strict
serialization, and exact-once terminal behavior are FeishuSpeech application invariants. Public
Feishu documentation does not guarantee their runtime acceptance or idempotency; credential-bearing
Release UAT remains pending.

### Review-first third axis and same-panel authority

`TranscriptionReviewState` is separate from `RecordingState` and from the two data lines:

```text
captureDrainTask: recorder ingress -> HoldPacketJournal
consumerTask:     factory/retry -> journal replay/live send -> action 2
review surface:   observe newly owned snapshots -> render one panel -> edit/confirm/discard
```

The first two task roots retain their issue #28 topology. `drainCapturedAudio` has no review
presenter reference. The recognition consumer does not await read-only presentation, editor
readiness, activation, focus, dismissal, or delivery. Review rendering adds no journal wake-up,
retry condition, replay ordering, buffer, `AsyncSequence`, or backpressure edge.

After identity-first destination capture succeeds, `MainViewModel` establishes a review ID and
publishes `.streaming(preview: "")`. Read-only rendering runs on a cancellable, revision-gated
fire-and-forget main-actor task; a newer snapshot can cancel a render that has not reached the
presenter. Each newly owned, changed, non-contentless opaque snapshot replaces the preview in full.
Equal values, historical replay, stale generations, closed admission, and late callbacks do not
render. Exact AX capture wins whenever available; an ordinary non-secure strict-AX miss uses the
already captured application's current-focus binding.

`ReviewWindowController` retains one `ReviewPanel`. During streaming/sealing it cannot become key
or main, ignores mouse events, is not closable, and shows `正在聆听…` or `正在完成识别…` without taking
focus from the captured target. Physical release changes the same panel to sealing and retains the
latest preview; it does not dismiss or recreate the surface. This review panel is separate from
the unchanged status-only `OverlayWindowController` / `RecordingOverlayView` pair.

The review panel keeps its initial 520x320 content size, minimum 420x240, and maximum 760x600. The
read-only transcript and native multiline editor share the 18pt transcript font; the font correction
does not enlarge those bounds. The panel omits `.fullSizeContentView`, so read-only content remains
below the titlebar/traffic-light controls rather than occupying the full titlebar region.

The authoritative action-2 result and recorder barrier freeze the draft and close response/retry
admission. A non-contentless final is used exactly. A contentless final falls back to the last usable
snapshot and marks it `可能不完整`; if neither value is usable, the surface returns to idle without
opening an empty editor. Action 2 starts a separate review-transition task. Only that task waits for
the existing recorder barrier and then projects the same panel directly to `.editable`, installing
edit/Send/Return callbacks before any presentation-focus await. The focus attempt is bounded, typed,
and advisory telemetry; it cannot change draft, revision, feedback, editability, or confirmation
authority. Neither data-line task stores or awaits this transition.

The editable panel accepts unmodified Return (including keypad Enter) as confirmation. Shift+Return
and Shift+Enter insert LF without confirming; Command+Return remains an explicit confirmation
shortcut. Return during marked text is passed to the input method. `发送`, `取消`, Escape, and
window close retain their explicit confirm/discard roles, and whitespace-only text remains editable
but cannot confirm. Only the actual Send button or qualified native Return/Enter path can construct
the opaque confirmation intent; no coordinator zero-argument or optional-revision bypass remains.
Discard performs no activation of the captured target, AX setter, target event, pasteboard operation,
or recovery copy. Human edits update the review state only, and late recognition cannot overwrite
them.

Issue #39 changes only this editable review keyboard policy. Original-target capture as amended by
issue #40, capture/journal production, recognition/retry/replay consumption, and the independent
review axis remain unchanged. V4 replaces the earlier review clipboard lifecycle with a text-only
Unicode delivery transaction; D-39's Return/Enter behavior is unchanged.

Confirmation consumes authority synchronously before the first await: it freezes the exact
untrimmed draft, changes to `.confirming`, advances the review revision, and keeps the same panel
visible while starting one delivery task. Repeated confirmation or stale callbacks cannot create a
second delivery. Focus failure is presentation telemetry only and cannot make the already editable
draft pending. A pre-submission delivery failure returns the same draft to `.editable` with fixed
feedback; a post-down or submitted-unverified result also never claims target consumption and keeps
the exact draft available for a new explicit confirmation. There is no retry-editing control,
automatic copy, retarget, or delivery retry. A pending editable/confirming review also prevents a
successor Fn interaction from replacing it.

The request to activate the accessory application is advisory only. Delivery safety remains
fail-closed against the actual predicates: the application is active, the panel is key, the editor
is materialized and attached to that panel, and the editor is the first responder. These predicates
protect the post-confirmation target transaction; they do not gate the already editable draft or
the Send/Return confirmation controls. An activation request result alone never grants delivery
authority.

### Review original-application and text-only delivery boundary

Before audio/network startup, review capture requires a complete application identity (PID, bundle
identifier, executable URL, and launch date) and confirms that the running process and frontmost
application agree. It then asks AX for a typed outcome. Accessibility trust, Secure Event Input
off, a supported non-secure editable role/subrole, focused-element PID equal to the frontmost PID,
a valid selected range, and settable focus plus selected-range attributes are required for the
preferred exact binding. A strict capability miss after final live security checks yields an
`applicationCurrentFocus` binding to the already captured identity. Global/affirmative secure
input, lost trust, incomplete identity, PID reuse, and post-capture identity drift fail startup.

The exact token keeps the `AXUIElement` and selection in memory. The fallback token keeps neither;
it cannot be used as an implicit exact cursor. Capture performs no AX setter and does not query
whether `kAXSelectedTextAttribute` is settable. Review-first never falls through to a compatibility
writer or an application discovered after panel activation.

On confirmation, `SystemReviewDestinationDelivery` verifies the complete process-reuse-safe
identity, requests activation of that exact application once, and waits at most two seconds. The
exact branch restores focus only to the captured AX element, verifies that exact focused element,
restores and rereads the original selection, and rechecks application/frontmost/security state
before mutation. The fallback branch performs no AX setter or later AX recapture; it requires two
consecutive composite samples, each ordered Secure Input at start -> raw captured PID ->
running/frontmost complete identities -> Secure Input at end, and then uses the review-only Unicode
pair to post once directly to the captured PID. Postflight uses the equivalent composite safety
shape. The fallback proves the original application, not the original control or caret inside it.

Binding-specific AX/application identity, trust, Secure Input, and frontmost validation completes
before the short submission gate is entered. The fixed-order activation-then-input critical section
then performs only live activation/input epoch checks, the final combined-session Command/Shift/
Control/Option/Fn/Caps Lock modifier sample, and submission of the already prepared pair. Blocking
AX/application validation is never held inside that short gate; any physical or activation
transition observed before the first down therefore fails pre-boundary with zero posts.

The delivery helper accepts LF as multiline data without normalizing the draft, while rejecting
NUL, tab, carriage return, DEL, and C1 controls before event construction. It enforces a product
maximum of 16,384 UTF-16 code units, constructs one complete modifier-free Unicode key-down/key-up
pair, tags and targets both events, and reads back source identity, phase, flags, payload, and
target PID before the first post. It never reads, writes, snapshots, restores, or polls the general
pasteboard and never emits Cmd+V. `CGEventPostToPid` has no consumption acknowledgement: a down
crosses the submission boundary, up is still attempted, and any post-boundary result is
`submittedUnverified`/uncertain rather than cancellation or consumed success.

Activation, identity, target, security, text, key-pair, modifier, input-epoch, activation-epoch, or
postflight failure is terminal for the current delivery attempt and never retargets. The same exact
frozen draft returns to the retained panel with transcript-free fixed feedback; cancellation,
focus failure, and delivery uncertainty perform no recovery copy. A later delivery exists only
after explicit user confirmation. The draft authority is in-memory and generation/revision fenced;
only explicit discard or lifecycle cleanup may revoke it in the uncertain path.

Pre-audio destination/security rejection has no draft to retain. After a draft is frozen, ambient
permission loss, Secure Input, or target-security change preserves the exact draft/panel with fixed
feedback for edit, explicit confirmation, or discard. Explicit reset, sleep/wake cleanup, abnormal
termination, lifecycle cancellation, or user discard may revoke the review ID/revision, cancel
presentation/transition/delivery tasks, clear transcript state and callbacks, and dismiss the panel.
A stale task cannot remount, deliver, or copy. Transcript content is never added to logs, diagnostics,
window titles, fixed feedback, notification text, persistence, or transcript-derived hashes. The
image-only clipboard measured after the rejected installed candidate is user-owned and is not
cleared or normalized by startup or migration.

### Historical compatibility cursor-writing boundary

This section documents retained issue #27 service contracts for historical context and dormant code
only. D-40-01 v2 supersedes the `reviewBeforeInsert == false` runtime branch: no accepted
interaction constructs these writers, and Settings cannot restore them. The current route always
captures a review destination before audio/provider startup and gates all external output on
explicit Send or Return/Enter. The fixed-target, HID, LF/control, and uncertainty rules below remain
protected implementation facts for those dormant services.

`CursorTextSession` captures the original frontmost PID, focused `AXUIElement`, selected-text
range, and session generation once. A live session requires settable selected-text/range
attributes plus range read-back support. Each different eligible snapshot replaces the
coordinator's latest snapshot; the writer replaces one app-owned provisional range with it:

1. verify generation, process, focused element, caret, and previous range text;
2. select the owned range;
3. set the complete latest snapshot as selected text;
4. read back the resulting caret and text before updating ownership.

The owned range comes from Accessibility's returned ranges, not Swift character counts. Equal
snapshots are no-ops. Shorter, longer, or revised snapshots replace the one verified range.
LF/newline content is written through AX as multiline text data; this route does not synthesize a
Return key event.
Any focus,
selection, caret, text, element, or generation mismatch permanently invalidates that writer.
Late events are dropped and are never redirected to a newly focused control.

The AX writer does not use per-partial clipboard writes, synthetic Backspace, or Shift+Arrow
selection. D-27-01 permits Backspace only in the generic keyboard route described below.
If a safe editable element was captured but lacks verified range replacement, startup immediately
arms a `CurrentFocusAppendSession` bound to the captured PID and exact element. If the first-partial
rebind returns final-only, it arms the same kind of owner and applies that triggering partial before
returning. Every eligible current-generation packet response, including a response produced while
draining already-recorded audio after release, may own its journal index once; only a different
complete snapshot is offered to output. Release cannot open or retarget a writer; it retains the
already selected owner until terminal settlement.

If no AX destination can be captured or confirmed at startup, the first non-empty partial triggers
one final AX binding attempt. A live result takes the normal captured-range path. If that probe does
not yield live capability,
`CurrentFocusAppendSession` binds the then-current frontmost PID for this hold. It reconciles each
different complete snapshot against the snapshot it successfully submitted: exact longest common
prefix by Swift `Character`, then one serialized transaction containing the required Backspace
down/up pairs followed by the replacement suffix. Equal snapshots post nothing. Replay cannot
re-own historical indices, but may own a previously failed index once.

The keyboard path checks Secure Input, generation/admission, and bound PID immediately before and
after each transaction. Before a snapshot can be claimed or posted on this route, LF and every
other C0/C1/DEL action control are rejected so recognition text cannot become Return, submit, or
execute input. Captured sessions also validate the captured
token's current security, original PID, and exact focused `AXUIElement` identity through `CFEqual`
before and after each mutation. Any PID/element/security/delivery uncertainty permanently suspends
the owner for the hold.

The existing HID `CGEventTap` is the synchronous physical-interference authority. Monitor
installation and baseline capture occur atomically under one shared `NSLock` gate. The generic
writer acquires that gate for each Backspace or insertion pair, verifies the armed epoch, and keeps
the lock continuously from synthetic key-down through key-up. Physical key-down, non-Fn
modifier-change, mouse-down, and mouse-drag events acquire the same gate before advancing the
epoch, and the tap cannot return them for dispatch until a synthetic pair releases it. An epoch
change permanently suspends output without rollback. Fn transitions and FeishuSpeech-tagged
synthetic events do not advance the epoch. Tap timeout/user-input disable advances the epoch as
loss of input observability before recovery.

Local and global AppKit event monitors supplement this ordering guard with early main-actor
suspension. They are not the authority; production requires both to arm, and arm failure fails
closed before keyboard output.

The low-level poster creates one tagged `.privateState` source and constructs every required event
before posting: modifier-neutral Backspace down/up pairs, then a Unicode suffix down/up pair when
needed, all to the same positive bound PID. Any construction failure or final security rejection
produces zero posts. The shared gate serializes each complete pair against physical epoch advance;
an intervening physical event runs after the current pair, then stops the remaining transaction and
permanently suspends the owner. The prior snapshot advances only after the complete ordered
transaction is submitted. There is no target acceptance acknowledgement, so a local `.posted`
result cannot prove visible replacement.

After destination/security loss, external caret-affecting input, or delivery uncertainty, the owner
never rolls back, selects, navigates, resends a full value, switches target, uses Cmd+V, or falls
through to clipboard recovery. Backspace is allowed only inside a validated transaction and never
exceeds this hold's recorded owned tail. Release-time one-shot/final-only insertion and manual-copy
recovery remain removed.
Without an AX range, the unbound owner cannot observe a caret move
inside the same PID; that residual targeting risk is explicit. A safe differing action-2 final uses
the same exact grapheme replacement transaction while the original monitors and fixed PID remain
armed. If safety validation fails, output remains unchanged rather than attempting destructive
repair; an equal final emits no duplicate event.

All routes reject action-capable C0/C1/DEL controls except that verified AX range replacement may
carry LF as multiline text data. The generic keyboard route rejects LF as well. An affirmatively
detected secure target or Secure Event Input is fail-closed and receives
neither synthetic input nor recovery copy. **Historical writer rule only:** `autoInsert=false`
produced no target or pasteboard mutation. Issue #40 v4 makes both legacy values converge on the
review route, where only explicit Send/Return confirmation may deliver. Usable held recognition is
tracked separately from output eligibility, so unsafe or ownerless historical output is not
misreported as empty recognition or a stream failure.

### Shared finalization and privacy

Release closes capture, not current-generation recognition authority. The recorder barrier first
proves that queued callbacks and the accepted tail are closed; the coordinator then drains every
journaled packet, retries recoverable attempts within the remaining budget, and waits for action 2.
A safe non-empty action-2 snapshot is authoritative. It freezes the review draft and starts the
independent recorder-barrier/editable transition; there is no accepted compatibility output branch.
Callbacks from a stale generation, retired/timed-out
attempt, expired drain, or completed terminal boundary are transcript-free suppressed inputs and
cannot mutate output. Because PID posting has no target
acceptance acknowledgement, this is retained local submission state rather than proof that text is
visible. A failure before the first write causes no target mutation.

Each factory, packet, and finish operation has a 30-second watchdog. Once the recorder barrier
completes, all post-release work shares one 60-second budget. Deadline admission is checked inside
the same lock-backed winner gate as operation completion, so an at-or-after-deadline success cannot
outrun cleanup. If action 2 and the recorder barrier have frozen a review draft,
  focus/delivery/security uncertainty preserves that exact draft in the same panel with
  fixed feedback; there is no automatic copy, direct output, retry, or retarget. Without a usable
draft, the coordinator reports only fixed neutral feedback and never claims successful external
delivery; late results are suppressed. A successful packet ACK resets the consecutive retry streak,
including after repeated backend `10024` responses.

If the bounded post-release drain expires while the same generation still owns a non-empty, safe,
bounded preview eligible for recovery, `expirePostReleaseDrain` snapshots that preview before
interaction cleanup, fences late review-transition callbacks, clears review-surface authority, and
renders the exact text in the same panel as the non-authoritative read-only
`ReviewReadOnlyPhase.recovery`. LF remains inert text data and is retained exactly. The recovery
surface displays fixed incomplete-recognition/read-only feedback, has no draft/edit/Send/qualified
Return callbacks, and cannot reach delivery; only authoritative action 2 plus the recorder barrier
may install `.editable`. It performs no append, AX write, Unicode/keyboard output, pasteboard/copy,
retry, or retarget. Empty, unsafe, oversized, stale-generation, or otherwise ineligible snapshots
continue through the fixed failure/preservation branch.

The recording overlay remains status-only and is unchanged. The retained review panel is the editing
surface for every accepted interaction; target applications are touched only after explicit Send or
qualified Return/Enter. Before that intent, every review phase has zero target AX writes, target
keyboard/CGEvent posts, pasteboard operations, copy/paste, delivery calls, retries, and retargets.
The final delivery is one capped, provenance-checked Unicode pair; any post-boundary result remains
submitted-unverified and keeps the draft editable. Empty-recognition and uncertain-output outcomes
use fixed, neutral, generation-guarded feedback presented for two seconds even though the coordinator
has already returned to idle. The neutral strings do not claim that a target accepted an event or that
visible text was preserved. Logs may include
typed state/eligibility/ownership/output outcomes, generations, attempt and journal indices,
snapshot decision, previous/new/common-prefix UTF-16 and `Character` counts, Backspace/insertion
counts, and route/outcome, but never transcript text or hashes, audio,
credentials/tokens, stream IDs, focused-control identities or contents, application/window titles,
or clipboard payloads.

A recoverable provider/transport event owns one attempt transition, not an abnormal hold exit. The
coordinator cancels the failed attempt, waits with cancellable backoff, and admits a successor only
while the same generation retains response/retry authority and, after release, has drain budget.
It publishes no user-facing error, overlay
transition, clipboard recovery, or notification. A non-recoverable terminal event immediately
invalidates the generation and every cursor writer, fails the ingress, cancels the
consumer/transport, and hides the overlay. An already-running recorder-stop barrier is not awaited
before those authority revocations; it is retained only to block a successor and delay the final
idle/error publication until the old recorder has actually stopped. Identical reflected hot-key
errors cannot re-enter teardown.

An authentication-provider failure is surfaced only as `认证失败，请检查应用凭据`. The associated
backend detail is not a public diagnostic surface.

## AudioRecorder — session lifecycle and recovery

`AudioRecorder` wraps `AVCaptureSession` with a `forceCleanup()` recovery contract (issue #1,
see `docs/decisions/D-1-01.md`):

- `startRecording()` calls `forceCleanup()` before the `isRecording` guard so stale state from
  a prior cancel or error path is always cleared before a new session begins.
- `handleCancelledState()` and `handleErrorState()` both call `forceCleanup()` to keep
  `isRecording` consistent with the actual `AVCaptureSession` state on every abnormal exit.
- `resetService()` calls `forceCleanup()` so a deliberate reset from the UI recovers a stuck
  mic without an app restart.

`forceCleanup()` is idempotent — calling it on an already-stopped session is a no-op.

Issue #15 adds a fail-fast failure contract for capture failures and conversion-error
exhaustion (see `docs/decisions/D-15-01.md`):

- `AudioRecorder` publishes `@Published private(set) var failure: RecordingFailure?`.
  `RecordingFailure` distinguishes `.runtime`, `.interrupted`, `.deviceLost`, and
  `.formatConversion`.
- `AVCaptureSession.runtimeErrorNotification` maps to `.runtime`,
  `AVCaptureSession.wasInterruptedNotification` maps to `.interrupted`, and
  `AVCaptureDevice.wasDisconnectedNotification` maps to `.deviceLost`.
- Repeated sample-buffer or converter failures increment the conversion-error counter; reaching
  `maxConversionErrors` aborts the recording with `.formatConversion`.
- If the abort is delivered off-main, `AudioRecorder` dispatches to the main queue before
  calling `forceCleanup()` and publishing `failure`. `forceCleanup()` still runs
  `AVCaptureSession.stopRunning()` and session teardown on `sessionQueue`, so blocking session
  work remains off the main actor.
- `MainViewModel` observes `audioRecorder.$failure`; on failure it hides the overlay,
  force-cleans the recorder, stops the max-duration timer, sets a specific error status, and
  puts `HotKeyService` into `.error` with the same localized message. This path does not call
  `stopRecording()` and does not start transcription.

## AppSettings — credential storage and migration

Issue #18 moves Feishu App ID and App Secret storage behind `CredentialStoring`
(see `docs/decisions/D-18-01.md`). `AppSettings.credentialStore` defaults to
`KeychainCredentialStore`, which stores generic password items through
Security.framework using service `Siji.FeishuSpeech.credentials` and account
values `appId` / `appSecret` in the login keychain (issue #18). Issue #35
data-protection storage is withdrawn (issue #36): those reads returned -34018
and blanked settings.

`AppSettings` still exposes `appId` and `appSecret` to the app at runtime, but
its custom `Codable` implementation does not encode those fields into
`FeishuSpeechSettings`. That user-defaults payload is limited to `autoInsert`,
`playSound`, `launchAtLogin`, and `reviewBeforeInsert`. Both decoding layers use
`decodeIfPresent(Bool.self, forKey: .reviewBeforeInsert) ?? true`, so an older valid payload
without the field safely migrates without discarding other preferences. Both legacy booleans remain
decodable/preservable for migration, but their runtime values are inert: explicit `false` no longer
restores the issue #27 compatibility route or bypasses the review gate.

Loading settings performs a guarded migration from legacy credentials:

- encoded `FeishuSpeechSettings` credentials are read if present;
- standalone user-default keys `appId` and `appSecret` are also read;
- standalone values take precedence over encoded values;
- legacy defaults are removed only after credential-store migration succeeds and
  the migrated credentials can be read back;
- when migration or credential read/write fails, legacy values remain available
  as the fallback and later saves avoid deleting the only remaining copy.

`SettingsView` keeps credential edits in transient `@State` fields and saves via
`MainViewModel.updateSettings(...)`, which calls `AppSettings.save()`. It does
not use `@AppStorage` for App ID or App Secret.

`AppDelegate.applicationDidFinishLaunching` applies
`LoginItemService.setEnabled(AppSettings.launchAtLoginPreference(from: .standard))`
and does not call `AppSettings.load()`. `launchAtLoginPreference` decodes
`launchAtLogin` from the given UserDefaults and does not touch
`AppSettings.credentialStore`. Missing payload is false. `MainViewModel.init`
still loads credentials once (the remaining launch read and the migration trigger).

## AppDelegate and MainViewModel — sleep/wake lifecycle

Issue #19 defines the system sleep/wake recovery contract (see
`docs/decisions/D-19-01.md`). `AppDelegate` registers
`NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification` through
`NSWorkspace.shared.notificationCenter` when the app finishes launching. The
observer tokens are retained in `workspaceObserverTokens` and removed during
application termination.

Workspace lifecycle delivery is routed through `MainViewModel`. If a sleep or
wake notification arrives before `setViewModel(_:)`, `AppDelegate` queues the
event and replays the queued lifecycle events once the view model is injected.

`MainViewModel.handleSystemWillSleep()` and `handleSystemDidWake()` both use the streaming terminal
path: invalidate the active identity and cursor ownership first; fail the ingress; cancel consumer
and transport work; release captured destination/session references; force-clean the recorder; and
stop the timer and overlay. If recorder sealing is already in flight, the terminal path retains and
awaits that barrier before returning coordinator and hot-key state to idle. It then calls
`FeishuAPIService.resetStateForWake()`.

The wake handler also calls `HotKeyService.recoverAfterWake()` after the API
wake reset.

## HotKeyService — state-machine contract

`HotKeyService` drives `idle -> pending (0.3 s) -> streaming(sessionID) ->
sealing(sessionID) -> idle`. The following rules keep `HotKeyService` and `MainViewModel` in sync:

- **The 0.3-second gate allocates the identity.** Each accepted gate increments a monotonically
  increasing generation and publishes it with `.streaming`.
- **Release and duration cap converge on sealing.** Fn release and the 60-second timer both move
  that same identity from `.streaming` to `.sealing`; repeated transitions are ignored and a new
  Fn press during sealing cannot open another session.
- **Reset/error/stop/wake clears identity before cleanup.** Late audio, network, AX, timer, and
  overlay callbacks compare the captured generation and cannot revive or redirect a retired hold.
- **`MainViewModel` holds `stateCancellable: AnyCancellable?` for the single `$state`
  subscriber.** `startHotKeyMonitoring` assigns it (replacing any prior subscriber);
  `stopHotKeyMonitoring` nils it before calling `stopMonitoring()`. At most one live
  `$state` subscriber exists at any time.
- **App teardown uses the same hot-key stop path as normal monitoring shutdown.**
  `MainViewModel.cleanup()` calls `stopHotKeyMonitoring()`, so cleanup releases
  `stateCancellable` before delegating to `HotKeyService.stopMonitoring()`. Teardown must not
  bypass `stopHotKeyMonitoring()` or leave a live `$state` subscriber behind.

## HotKeyService — tap-lifecycle and threading contract

The CGEventTap machinery was redesigned in issues #5, #9, and #10 (see
`docs/decisions/D-5-01.md`). The key invariants are:

**Threading model**

| Thread / Queue | Owns |
|---|---|
| Tap thread (private `CFRunLoop`) | CGEventTap callback, `CFRunLoopSource` |
| `sessionQueue` (serial background) | `AVCaptureSession.startRunning()` / `stopRunning()`, `isRecording` flip |
| `@MainActor` | `monitoringState` publish, all UI updates, `MainViewModel` state |

The tap source is added to a private dedicated `Thread`+`CFRunLoop`, not
`CFRunLoopGetMain()`. This eliminates contention with `AVCaptureSession.startRunning()`,
which blocks the run loop and previously caused sporadic hotkey event drops.

**`MonitoringState` observable**

`HotKeyService` publishes `@Published var monitoringState: MonitoringState` with three
cases: `.stopped`, `.active`, and `.failed(TapFailureReason)`. `MainViewModel` subscribes
and surfaces `.failed` as the fixed error status `热键不可用，请检查辅助功能权限`.

When monitoring later publishes `.active`, `MainViewModel` auto-clears only that specific
stale hot-key monitoring error and returns to `.idle`. The clear is guarded by both the
tracked hot-key monitoring failure flag and the current status value, so unrelated errors
such as speech-recognition failures are preserved. The retry policy is unbounded capped
exponential backoff (1 s -> 2 s -> ... -> 30 s cap) instead of the previous hard 3-attempt
limit.

**`previousFlags` lifecycle**

`stopMonitoring()` resets `previousFlags` to `.init()` so a restart begins with a clean
key-flag baseline. After each backoff delay, `CGEventSource.flagsState(.combinedSessionState)`
is sampled to detect a held Fn key and cancel any stale pending/recording state before the
tap is re-created.

**Wake recovery**

`recoverAfterWake()` cancels pending transitions, returns the state machine to
`.idle`, and clears `previousFlags` before checking tap health. For real taps,
tap health is read through `CGEvent.tapIsEnabled(tap:)`. If the tap exists and
is enabled, monitoring remains active. If the tap is missing or disabled, wake
recovery restarts monitoring through the normal `stopMonitoring()` /
`startMonitoring()` lifecycle.

The DEBUG test hook drives the same recovery branch without a real
`CFMachPort`, and its result exposes only `restartCount`.

**Secure keyboard entry**

`PermissionManager` polls `IsSecureEventInputEnabled()` every 2 seconds. When active, the
menu bar shows an orange "安全输入已启用，热键暂不可用" warning (issue #10). The hotkey
suppression itself is enforced by the OS kernel; detection and display is the only recourse.

The same 2-second `AppDelegate` poll also refreshes accessibility, microphone authorization,
and secure-input status (issue #15). `PermissionManager.refreshMicrophoneStatus()` reads the
current microphone authorization status without prompting and recomputes
`allPermissionsGranted`, so permission changes made in System Settings are reflected at runtime.

**Current-focus interference epoch**

Issue #27 extends the existing HID event tap mask to physical key-down, non-Fn modifier changes,
mouse-down, and mouse-drag events. At the start of the tap callback, before the event is returned
for dispatch, `CurrentFocusInputInterferenceEpoch` acquires the same `NSLock` used to guard complete
synthetic pairs and increments the epoch. Monitor installation plus baseline capture is atomic under
that lock. The generic writer uses this synchronous gate rather than AppKit monitor callback timing
to guard destructive replacement. Tap-disable events advance the epoch before recovery because
input observability was lost. FeishuSpeech's tagged synthetic events and the Fn transition itself
are excluded. Local/global AppKit monitors remain supplemental; failure to install either prevents
the writer from arming.

## TextInputSimulator — dormant compatibility input and v4 review delivery contract

The following issue #27 compatibility behavior is retained as a dormant service contract only; the
Issue #40 v4 coordinator does not construct it and no setting can re-enable it. It historically:

- permits LF only on the verified AX range path, where it is multiline text data; the generic
  keyboard-event path rejects LF and all other C0/C1/DEL controls before claim/post;
- when a destination token exists, targets that captured process with `CGEvent.postToPid` and
  validates the captured element and security state before and after delivery;
- when AX capture/confirmation is unavailable, re-probes AX once on the first non-empty partial;
  if still unavailable, binds the frontmost PID and posts grapheme-aware Backspace-plus-Unicode
  replacement transactions while Secure Input stays clear, atomic arming captures the HID epoch,
  the shared lock covers every complete synthetic pair, and the PID stays stable;
- treats local/global AppKit event monitors as supplemental suspension signals and fails closed if
  either monitor cannot arm;
- gives captured final-only-capability targets the same continuous owner, additionally checking the original
  PID and exact AX element before/after each mutation; after any post attempt or uncertainty it
  never falls through to a full resend, Cmd+V, another target, or clipboard recovery;
- never performs release-time one-shot/final-only insertion or manual clipboard recovery.

Issue #38's historical review paste transaction and Cmd+V path are removed by Issue #40 v4. The
current review delivery is separate from the compatibility writer and is text-only:

- action 2 plus the recorder barrier publishes `.editable` immediately; focus/activation work is
  advisory telemetry and never grants or revokes confirmation authority;
- only the real Send button or qualified native Return/Enter creates the opaque confirmation intent;
- after binding-specific exact/application identity, PID, Accessibility trust, Secure Input, and
  frontmost validation completes outside the short gate, the fixed activation-then-input critical
  section rechecks live activation/input epochs and the final combined-session Command/Shift/
  Control/Option/Fn/Caps Lock modifier sample before posting;
- the poster constructs exactly one complete modifier-free Unicode key-down/key-up pair before that
  final gate; a physical or activation transition before the first down fails with zero posts;
- both events must read back the complete UTF-16 payload, LF/non-BMP data, empty flags, fixed tag,
  `eventSourceUnixProcessID == getpid()`, common source, and captured positive target PID before
  the first post; a 16,384 UTF-16-unit cap is enforced before construction;
- the general pasteboard is never read, written, snapshotted, restored, or polled, and no Cmd+V or
  recovery copy exists. After key-down, key-up is still attempted and the outcome is
  `submittedUnverified`/uncertain because `CGEventPostToPid` has no consumption receipt. The exact
  frozen draft remains editable; a later attempt requires a new explicit confirmation.

The older issue #13 helper remains only as a historical/non-review API surface; it is not reachable
from an accepted Issue #40 interaction and does not weaken the sole explicit review output gate. Its
historical mechanics are:

- **Full snapshot before write.** Before placing the transcribed text on the pasteboard, the
  simulator reads every `type` from `NSPasteboard.general` and stores a
  `[(type: NSPasteboard.PasteboardType, data: Data)]` array. All types — not just the first
  string item — are captured so non-string content (RTF, images, etc.) survives the round-trip.
- **changeCount-based confirmation.** After sending Cmd+V, the simulator polls
  `NSPasteboard.general.changeCount` at a short interval up to a bounded timeout. The
  changeCount advances each time an application reads from the pasteboard. Restoration is
  deferred until that increment is observed, ensuring the target application has read the
  transcribed text before the old data is written back.
- **Fallback notification on timeout.** If the changeCount does not advance within the
  timeout, the simulator restores the pasteboard unconditionally and posts a user notification.

The `maxDurationTimer` in `HotKeyService` is scheduled with `RunLoop.main.add(timer,
forMode: .common)` so it fires in both `.default` and `NSEventTrackingRunLoopMode` (e.g.
while the menu-bar menu is open) — issue #16.

## OverlayWindowController — generation guard

`OverlayWindowController` maintains a monotonically incrementing `Int` generation counter
to prevent hide/show races (issue #17, see `docs/decisions/D-13-01.md`):

- Each `show()` call increments the counter and captures the new value in its animation
  completion closure.
- Each `hide()` call captures the current generation at call time.
- Any completion block that fires with a stale (mismatched) generation is a no-op and does
  not close or modify the window.

This prevents a `hide()` completion from a superseded call from closing a window that a
newer `show()` has already claimed.

Issue #26 extends the same guard to completion feedback. A requested interval is clamped to one
through five seconds (the coordinator always requests two); show, hide, or replacement feedback
cancels the previous delayed hide and advances the generation, so stale feedback cannot hide a new
recording overlay.

## Verification boundary

The final issue #39 candidate passes 40/40 focused tests and a full run of 423 executed tests with
1 skipped and 0 failures. The final R4 Issue #40 v4 focused matrix passes 265 tests with 0 skipped
and 0 failures; all 105 `StreamingMainViewModelTests` execute and the R4 selectors pass 3/3. The
full serialized macOS target passes 483 tests with 1 unrelated live-TCP environmental skip and 0
failures. It covers direct freeze-to-editable, real Send/qualified Return intent, zero pre-confirm
side effects, no-pasteboard/no-Cmd+V output, 16,384 UTF-16 limits, Unicode pair
readback/provenance, final modifier/epoch/PID/tag ordering, non-authoritative LF-preserving
recovery, action-2 confirmation authority, and retained drafts. This automated evidence does not
include replacement Release installation, target consumption, or owner UAT; final independent
review/build gates remain separate.

Issue #26's 272/272 lifecycle-free evidence predates the issue #27 correction and must not be used
as proof of snapshot reconciliation. Issue #27 requires focused and full-suite evidence for
duplicate, extension, shorter, revision, replay, Unicode grapheme, ordered transaction, suspension,
and release-drain cases. The final issue #27 candidate at Release 1.0 build 8 passes 316/316 full
tests, strict SwiftLint, and Debug and Release builds. Automated coverage includes authoritative
terminal replacement, release during retry/replay/in-flight work, repeated-`10024` recovery,
operation watchdogs, deadline races, delivery-state expiry, and stale callback suppression.
Automated evidence still cannot prove target-control acceptance or credential-bearing service
behavior.

Credential-bearing Feishu behavior, real WindowServer panel activation/key focus, and
cross-application Accessibility/Unicode-pair compatibility remain live UAT. Issue #40 specifically needs
one ordinary non-secure final-only/editable AX target that previously showed `无法确认输入位置`,
one exact-AX target, secure/password rejection, app switching during confirmation, multiline
confirmation, and forced post/postflight uncertainty with retained-draft explicit retry/discard.
Installed build 5 recorded 66 HTTP-200 transactions over 13.55 seconds while visible output
stopped after one word. This proves continuing transport, not response shape, output ownership, or
target acceptance. The snapshot-replacement policy, subsequent actions, terminal encoding, real
text/token-refresh behavior, PCM/tail handling, slow networks,
native/browser/Electron/terminal/rich-text targets, focus/caret interference, Unicode, and undo
remain owner-UAT gates. No broad application compatibility is claimed yet.

In particular, `CGEventPostToPid` has no target acceptance acknowledgement. A locally submitted
Unicode pair with no visible target text remains PARTIAL and must not trigger global HID posting,
retries, rollback, retargeting, or a second automatic delivery path after uncertainty. The D-40
fallback proves the original application only, not the original control or caret within it. The v3
installed candidate was stopped after its Cancel-only/Return failure and residual image-paste risk;
no v4 Release is installed yet.

# Streaming speech and review-first design

Status: Issue #40 v9 one-route review-first plus issue #39 editable keyboard policy, application-bound
non-secure AX-miss fallback, snapshot replacement, release-drain lifecycle, resilience watchdogs,
and the atomic HID interference gate are implemented locally. V5 adds the nonblocking submission
executor/control-plane, fixed opaque target lease, final security sandwich, and per-AX cancellation/
deadline checkpoints; v6 retries lifecycle observer installation when Accessibility authorization lands
after initialization, and v7 reads initial focus only from the frozen original-application AX root rather
than ambient system-wide focus. V8 changes no behavior: it persists the existing value-only capture
identity, frontmost, Secure Input, trust, and AX step/result trace at info level so an installed failure
identifies one exact fail-closed branch without reading transcript or target text. V9 classifies a
successfully read non-native focus role such as `AXWebArea` as an ordinary non-secure AX capability miss,
so the already-designed frozen-application fallback is used instead of rejecting preview startup. Secure
Input, trust, identity, cancellation, and deadline failures remain fail closed. The former issue #27 direct/compatibility output branch remains historical/dormant
and cannot be restored through settings. The final focused matrix passes 324 executed / 0 skipped /
0 failures; all 105 streaming tests execute, and the v9 full serialized target passes 539 tests with 1
expected live-TCP environmental skip / 0 failures.
The authorized Apple Development-signed v6 Release failed original-target capture and was stopped.
The signed v9 replacement is installed as the sole application copy; owner UAT remains pending and no
target-consumption or general compatibility claim is made.

## 1. Outcome

Holding Fn for the existing 0.3-second gate starts a Feishu streaming-recognition interaction.
Regardless of the persisted `reviewBeforeInsert` or `autoInsert` value, the coordinator first
captures a complete original application identity and prefers the exact AX element and selection.
If an ordinary non-secure target misses the strict AX cursor contract, it retains that same
application as an application-current-focus binding. During the physical hold, one nonactivating
panel shows each newly owned, changed complete opaque snapshot as a full read-only replacement.
Release changes that same panel to read-only sealing while capture closes and queued/tail audio,
recoverable replay, and action 2 settle. Only the authoritative action-2 result plus the recorder
barrier may freeze the same panel directly into `.editable`; Send and qualified Return/Enter callbacks
are installed before any presentation-focus await. The user can change the multiline draft and must
explicitly Send or press Return/Enter before one fail-closed delivery to the captured application;
discard performs no target write.

Review presentation is a third asynchronous axis. It observes already-owned events through
cancellable fire-and-forget main-actor rendering and never becomes a prerequisite or backpressure
edge for the capture-to-journal producer or the recognition consumer/retry/replay line. The existing
recording overlay remains status-only and unchanged; the transcript-bearing review surface is a
separate panel.

The historical issue #27 route once offered direct/continuous output when `reviewBeforeInsert` was
false and sampled `autoInsert`. That branch is no longer a user-selectable route; retained writer
types are dormant and no accepted interaction constructs them. All external output now waits for
the one explicit review gate. Verified AX may carry LF as multiline data; the fixed-PID fallback
still rejects action controls where required. No target AX setter, target keyboard/CGEvent, pasteboard
operation, copy/paste, delivery, activation, retry, or retarget occurs before that real UI intent. The
nonactivating panel accepts only panel-local Send or qualified Return/Enter; blank/IME/modified/repeated/
wrong-window/non-descendant Return is rejected. The executor builds/reads back one immutable,
provenance-checked, modifier-free Unicode pair capped at 16,384 UTF-16 units, then performs the final
security sandwich with per-AX cancellation/deadline checks. Exactly one down and mandatory up are
attempted; its result is terminal `submitted-unverified` because `CGEventPostToPid` has no target
consumption acknowledgement.

It also ports KaolaTerminal's response compatibility boundary: response identity echoes are not
trusted as acknowledgements, code-zero missing data is an empty value, and `recognition_text` is
preferred with `text` as fallback. Request-side stream identity/action/sequence remain owned by the
session.

## 2. Evidence and verified boundaries

### Local reference implementation

- KaolaTerminal commit
  [`96b9422`](https://github.com/KaolaBrother/KaolaTerminal/commit/96b94223315b7f96776a9988b317f2d8b2486447)
  introduced D-148: strict serial `stream_recognize`, 6,400-byte target packets,
  opaque-replacement partials, and fail-current-stream behavior.
- KaolaTerminal commit
  [`397ad67`](https://github.com/KaolaBrother/KaolaTerminal/commit/397ad675c4f92499f642df6b79dd67a22cf60c3c)
  introduced D-149: raw callbacks are coalesced before a byte/duration-aware bounded ingress;
  long holds cannot overflow merely because callback cadence differs from packet cadence.

### External contracts

- The official
  [Feishu streaming speech API](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/reference/ai/speech_to_text-v1/speech/stream_recognize)
  confirms the endpoint, real-time chunked recognition, and the recommended 100–200 ms audio
  fragment size.
- Apple documents selected-text ranges as character ranges for editable Accessibility elements,
  provides
  [`kAXStringForRangeParameterizedAttribute`](https://developer.apple.com/documentation/applicationservices/kaxstringforrangeparameterizedattribute)
  for range verification, and provides
  [`AXUIElementIsAttributeSettable`](https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable)
  for capability checks.

### Explicitly unverified

Feishu responses are complete opaque recognition snapshots: a later value may be equal, longer,
shorter, or revised. This observed replacement contract does not claim stabilization or permit
normalization/inference. Packet index remains replay identity only; it is never a text delta rule.

Accessibility behavior is application-dependent. Native AppKit, WebKit, Electron, terminal, and
document-editor targets require live UAT before broad compatibility claims are made.

Issue #26's lifecycle-free 272/272 evidence and issue #27's 316/316 evidence predate review-first.
Issue #38 adds focused review/destination/pasteboard suites; issue #39 adds focused editor-keyboard
and IME suites and a new full-suite run; issue #40 adds focused identity/fallback/output suites;
no automated suite replaces installed UAT. In particular, `CGEventPostToPid` exposes no target-control
acceptance acknowledgement, so submitted-unverified cannot prove visible text consumption.

The latest installed build-5 evidence recorded 66 HTTP-200 transactions over 13.55 seconds while
visible output stopped after one word. It proves continued transport, not response shape,
coordinator ownership, or target acceptance. The rejected installed v3 candidate also left an
image-only pasteboard after a delayed review Cmd+V/restore race was diagnosed; the process was
stopped and the user-owned pasteboard was not modified during diagnosis. V5 removes that path.
Earlier observations of undefined business code
`10024` remain transport history; neither observation proves provider text semantics.

## 3. Goals and non-goals

### Goals

- Default to a same-panel read-only streaming/sealing preview, then an editable multiline draft
  whose explicit confirmation is the only target-mutation authority.
- Bind review delivery to the exact original application identity, preferring the AX element and
  selection; for an ordinary non-secure strict-AX miss, use only that application's current focus.
  Never retarget, retry uncertainty, or silently submit a draft.
- Preserve the protected issue #27 capture/replay topology; its former held target writer is
  historical and cannot be re-enabled by a setting.
- Preserve the 0.3-second Fn gate, 60-second maximum hold, multi-display status overlay, sleep/wake
  cleanup, microphone/accessibility permissions, and Keychain credential storage.
- Keep capture/journal production, recognition/retry/replay consumption, and review UI as three
  independently progressing asynchronous axes.
- Keep audio memory and network backpressure bounded.
- Keep cancellation, reset, and error paths idempotent and generation-safe.
- Preserve recognition when output is disabled, unsafe, or ownerless without inventing an output,
  empty-result, or stream-failure outcome.

### Non-goals

- Making `RecordingOverlayView` transcript-bearing or editable; the review panel is separate.
- Making UI rendering, animation, activation, or focus part of capture/journal or recognition
  progress.
- Whole-file fallback after a stream has been established.
- Translation, speaker diarization, punctuation controls, or multiple simultaneous streams.
- A universal input-method extension or custom IME.
- Removing the existing `autoInsert` or `reviewBeforeInsert` keys; they remain decode/preservation
  inputs only and cannot change the runtime route.
- Changing the compatibility-only whole-file API into a fallback for a streaming interaction.

## 4. End-to-end architecture

```text
private CGEventTap thread -> HotKeyService -> MainViewModel (@MainActor)
                                              |
                                              +-> capture task
                                              |     AudioRecorder -> bounded ingress -> packet journal
                                              |
                                              +-> recognition task
                                              |     factory/retry -> replay/live send -> action 2
                                              |                         |
                                              |                         v
                                              |                   snapshot ledger
                                              |
                                              +-> review task/UI (all interactions)
                                                    read-only streaming -> sealing -> editable -> confirming
                                                                                                  |
                                                                                                  v explicit Send/qualified Return
                                                                    original-app (exact AX | current focus) Unicode pair once
```

The review surface receives recognition observations but owns no audio or transport progress. Its
read-only rendering and later presentation-focus aid cannot block or wake the packet journal and
cannot gate factory, retry, replay, send, finish, or action-2 settlement. The panel/draft authority can
remain live after speech-session cleanup returns the hot-key axis to idle.

Retained compatibility writer services (`CursorTextSession` and `CurrentFocusAppendSession`) are
historical/dormant and are not constructed by the v5 coordinator. The transport does not know about
focus or UI, and the current review delivery boundary does not know about audio, credentials, or
HTTP. No target mutation occurs before explicit Send/Return.

## 5. State model

### Hot-key state

```text
idle
  -> pending(startedAt)
      -> idle/cancelled               Fn released or another modifier/key before 0.3 s
      -> streaming(sessionID)         gate elapsed, target and capture start accepted
          -> sealing(sessionID)       Fn release or 60 s cap
          -> streaming               recoverable attempt failure; abort/backoff/fresh replay
          -> error                    non-recoverable capture/auth/security/configuration failure
      -> idle                         data-line terminal settlement; review axis may remain editable
```

`transcribing` is retired from the production state because recognition now overlaps capture.
`sealing` is explicit: it prevents a second Fn hold from racing the first stream's tail and final
response. `MainViewModel` separately rejects a new accepted hold while an editable/confirming review
authority remains unresolved, even after the hot-key axis returned idle.

### Session generation

Every accepted hold receives a monotonically increasing generation. Audio callbacks, stream
events, cursor writes, timers, overlay updates, and cleanup capture that generation. Reset,
sleep/wake, permission loss, manual service reset, and terminal failure invalidate the active
identity and cursor ownership before cancelling work. A callback whose identity is no longer
current is a no-op.

### Review state (all accepted interactions)

```text
idle
  | verify/reinstall lifecycle observers -> complete original-app capture
  | -> exact AX or current-focus binding -> streaming(preview: "")
streaming
  | changed usable snapshot        -> streaming(replacedPreview)
  | physical Fn release            -> sealing(latestPreview)
sealing
  | non-empty action 2 + recorder barrier -> editable(authoritativeDraft)
  | empty action 2 + usable snapshot      -> editable(snapshot, possiblyIncomplete)
  | empty action 2 + no usable snapshot   -> idle
editable
  | human edit                     -> editable(updatedDraft)
  | Shift+Return / Shift+Enter     -> editable(updatedDraft + LF)
  | Send, Return/Enter (unmodified), Command+Return -> confirming
  | Cancel / Escape / close        -> idle (zero delivery)
confirming
  | pre-boundary delivery failure/cancellation -> editable(sameDraft, feedback)
  | key-down boundary crossed -> submitted-unverified (terminal; no resend)
```

The review ID, revision, opaque handle, and terminal-pending flags fence stale render, recognition,
window, and delivery callbacks. Confirmation creates one immutable envelope asynchronously. A draft
blocks a successor hold; pre-boundary delivery failure retains it for editing or discard, while a
key-down boundary is terminal `submitted-unverified` and cannot reopen ordinary Send/Return. No
pending UI or retry-editing control exists. No automatic copy, direct output, delivery retry, resend,
activation, or retarget exists.

### Historical writer state (dormant compatibility services only)

The following state machine records the former issue #27 writer for historical compatibility
analysis. Issue #40 v2 does not construct it, and persisted settings cannot select it.

```text
unavailable
  | safe AX target lacks range support -> capturedAppend(bound PID + exact AX element)
  | AX destination unavailable        -> rebindOnFirstPartial
  | capability probe passed -> armed(destination, originalSelection)

armed
  | first non-empty partial -> provisional(range, lastText)
  | invalidation            -> invalid

provisional
  | replacement verified    -> provisional(updatedRange, newText)
  | non-empty final         -> committed
  | empty final / failure   -> preserved
  | destination mismatch    -> invalid

rebindOnFirstPartial
  | first non-empty partial + live AX  -> provisional
  | first non-empty partial + finalOnly -> capturedAppend(bound PID + exact AX element)
  | AX still unavailable              -> currentFocusAppend(boundPID, emittedUTF16)

capturedAppend / currentFocusAppend
  | each eligible current-generation journal index -> admit complete snapshot at most once
  | equal snapshot              -> no event
  | different snapshot          -> replace owned keyboard tail by Character LCP
  | historical replay index     -> no-op
  | route-unsafe/contentless    -> no ownership or output
  | release                     -> retain existing owner through bounded drain
  | safe action-2 final         -> reconcile authoritatively, then close
  | PID/element/security/delivery change -> suspended
  | external caret-affecting input        -> suspended

currentFocusAppend
  | same-PID caret movement remains unobservable
```

`invalid`, `committed`, and `preserved` are terminal for that hold. No later callback can revive
the writer.

## 6. Audio and backpressure

The recorder converts capture to 16 kHz, mono, signed Int16 PCM and, in production streaming mode,
routes it to ordered streaming elements rather than the compatibility whole buffer:

- raw `AVCaptureAudioDataOutput` callbacks remain on `audioQueue`;
- converted PCM is coalesced on the serial buffer boundary;
- each yielded normal element is exactly 6,400 bytes (200 ms);
- stop flushes at most one non-empty tail;
- after `action=1` is accepted, a tail shorter than 3,200 bytes is padded with PCM silence to the
  100 ms minimum before normal finish;
- if no first packet was emitted, release cancels locally and sends neither finish nor abort;
- yielded elements enter a custom non-blocking async stream bounded by exact captured bytes. In
  production replay mode, a delivered packet remains charged against the same hold-wide budget;
  non-replay users release exact queued capacity on dequeue.

Capacity calculation for the retained 60-second maximum:

```text
16,000 samples/s * 2 bytes/sample = 32,000 bytes/s
32,000 bytes/s * 60 s             = 1,920,000 bytes maximum
1,920,000 / 6,400                 = 300 full elements
```

The bound is a safety ceiling, not a desired queue depth. Under healthy network conditions the
consumer drains near real time, but replay-retained delivered bytes remain charged alongside
queued and pending capture. Tail silence added only to meet the 100 ms network minimum is not
double-charged as captured audio. If the producer would exceed the byte ceiling, capture and stream
fail explicitly with `ingressOverflow`; no PCM is silently dropped, reordered, re-chunked, or sent
in parallel. The coordinator's sole consumer journals each drained element before first send. A
recoverable replacement session replays those exact elements from index zero while the same
recorder and ingress continue accepting capture.

## 7. Feishu streaming protocol

One `FeishuStreamingSession` actor owns all mutable transport state:

```text
streamID
nextSequenceID
token
didAcknowledgeFirstPacket
didRefreshFirstPacket
recognitionOutcome: none | completed | failed
abortEligible
didAttemptAbort
currentRequestTask
```

Request rules:

| Moment | Action | Audio | Sequence |
|---|---:|---|---:|
| first packet | 1 | non-empty 100–200 ms PCM | 0 |
| continuation | 0 | non-empty 100–200 ms PCM | 1...n |
| normal seal | 2 | empty | next |
| abort accepted unfinished stream | 3 | empty | next unconsumed |

- Exactly one request may be in flight. Actor isolation alone is insufficient if cancellation and
  request work use child tasks, so the session retains an explicit serial request gate.
- A token-invalid response before the first accepted packet may clear the token cache, fetch once,
  and retry the same action/sequence. It does not consume a new sequence number.
- After acceptance, any HTTP, backend, decoding, timeout, or connectivity failure terminates that
  transport session. The hold coordinator may recover through a fresh streaming session; it never
  calls `file_recognize`.
- After valid JSON and `code == 0`, response `stream_id` / `sequence_id` echoes are ignored;
  `recognition_text` is preferred, `text` is the fallback, and missing data/text returns an empty
  event. Nonzero business codes and malformed JSON remain failures.
- `finish()` and `cancel()` are idempotent. An accepted stream remains independently abort-eligible
  until action 2 succeeds. A failed action 0 or action 2 therefore attempts action 3 once; a failed
  first action 1 sends none; successful action 2 suppresses it. Abort has one total one-second
  deadline and remains strictly behind an established in-flight continuation/finish.
- Public errors are sanitized. Raw response bodies and backend messages do not reach UI or logs.

The provider obtains a tenant token before creating this actor or sending `action=1`. A token
business rejection at that stage is therefore pre-stream authentication failure and maps to the
fixed public message `认证失败，请检查应用凭据`; no associated backend detail is exposed. The latest
installed-Release UAT passed that boundary and accepted two packets before HTTP 200 / business code
`10024` failed the third. Current official sources do not define `10024`; no pacing, quota, tenant,
or lifecycle meaning is asserted. The new abort/retry behavior still requires owner UAT.

Events exposed to the coordinator are typed:

```text
partial(String)
final(String)
cancelled
failed(StreamFailure)
```

### Resilient hold coordinator

The transport actor owns one attempt; `MainViewModel` owns the resilient hold. Recoverable
classifications are network, timeout, HTTP 408/425/429/5xx, backend code `10024`, and the
coordinator's timeout/network-unavailable/connection/network factory failures. Malformed or
identity-mismatched responses, invalid request/response, authentication, recognition-contract,
unknown/unclassified, other backend, and other HTTP failures are not retried. Capture/ingress and
permission/security failures remain lifecycle-owned; destination/security changes suspend output
rather than authorizing reconnect or retargeting.

After a recoverable failure, the coordinator cancels the failed session once, increments a
consecutive failure streak, and awaits cancellable exponential backoff. Base delays are 250 ms,
500 ms, 1 s, 2 s, then 4 s; jitter is clamped to 0.8–1.2 and final delay to 200 ms–4 s. There is no
independent attempt limit. Every successful packet acknowledgement, including replay ACK, resets
the streak to zero; the attempt identifier remains monotonic for stale-callback suppression.

A fresh session replays the exact ordered packet journal from zero. Responses keep their stable
journal indices: already-owned history is suppressed, a previously failed unowned index may claim
once when replay succeeds, and later live packets continue at new indices.
Recoverable failures publish diagnostics only: no early `.error`, hot-key error, overlay hide/show,
clipboard recovery, or notification. Factory, packet-send, and finish operations each have a
30-second attempt-scoped watchdog. Fn release sets `captureClosed` before any await but does not
close response/retry admission or cancel current factory/backoff/replay work. The recorder stop
barrier flushes and closes ingress, then arms one 60-second drain budget. Recovery and full journal
replay continue inside that budget until every packet is acknowledged and action 2 settles.

A safe non-empty action-2 snapshot is authoritative and freezes the coordinator-owned review draft
before admission closes. Expiry preserves only a non-authoritative recovery surface or reports fixed
delivery uncertainty; it never invokes a dormant writer, copies text, retargets, or emits external
output without explicit confirmation. If bounded drain expires while a same-generation, non-empty,
safe, <=16,384 UTF-16 preview remains eligible for recovery, `expirePostReleaseDrain` snapshots it
before cleanup, fences late review callbacks, clears review-surface authority, and renders the exact
text in the same panel as `ReviewReadOnlyPhase.recovery`. LF remains inert text data and is retained
exactly. The recovery surface is read-only/sealing, shows incomplete-recognition/read-only feedback,
has no draft/edit/Send/qualified Return callbacks, and cannot reach delivery; only authoritative
action 2 plus the recorder barrier may install `.editable`. This path performs no append,
AX/Unicode/keyboard output, pasteboard/copy, retry, or retarget. Empty, unsafe, oversized, stale,
or otherwise ineligible previews continue through fixed failure/preservation branches. The same panel
is `.editable` only after the authoritative transition; focus telemetry, editing, delivery failure,
or explicit Discard do not create a pending/retry-editing authority.
Deadline/cancellation winners retire their attempt; late results cannot mutate output.
An abnormal lifecycle event does not wait on that barrier to revoke authority: generation/output
writers and transport are cancelled immediately, while the independently retained recorder barrier
continues to block a successor and final idle/error publication.

## 8. Historical compatibility cursor-bound text replacement (dormant)

Issue #40 v2 does not construct this writer from an accepted interaction. The section remains as
historical implementation context and must not be read as a setting-selectable output route.

### Capability probe

The post-UAT correction supersedes the original rule that a confirmed AX destination was required
before capture/network startup. AX probing now selects an output capability; failure to capture or
confirm a cursor/focused element arms one first-partial rebind and does not reject recording or
streaming.

At the transition from `pending` to `streaming`, `CursorTextSession.begin()`:

1. Confirms Accessibility trust and rejects Secure Event Input.
2. Reads the system-wide focused UI element once.
3. Captures its PID and verifies it is still the frontmost application.
4. Rejects a secure-text subrole, non-editable element, or role/subrole whose safety cannot be
   established.
5. Reads the original `kAXSelectedTextRangeAttribute`.
6. Requires selected-text and selected-range attributes to be settable.
7. Requires string-for-range support for read-back verification.
8. Creates an in-memory destination token; it is never persisted or logged with control content.

An affirmatively safe editable target that lacks usable selection/range verification selects a
captured append owner bound to its PID and exact element. If that owner cannot be created,
recognition continues without release-time insertion or copy. Failure to obtain or confirm any AX
destination selects the first-partial AX/current-focus
path described below. An affirmatively detected secure text target or Secure Event Input still
rejects the interaction before audio/network work; this security rejection is not downgraded.

### First partial

Before the first write, the session verifies that generation, PID, focused element, and original
selection still match. It then sets `kAXSelectedTextAttribute` on the captured element, replacing
the original selection. It reads the resulting collapsed caret and the string for the candidate
range. Only a successful exact read-back establishes ownership.

The base location comes from the original selection. The owned range length comes from the
post-write caret/range values returned by Accessibility, not from Swift character counting.

### Later partials

For each different admitted snapshot:

1. Verify the destination token and generation.
2. Verify the same process and focused element.
3. Verify a collapsed caret at the owned range end.
4. Read the owned range and require exact equality with `lastWrittenText`.
5. Set the selected range to the owned range on the captured element.
6. Set selected text to the complete raw latest snapshot.
7. Read back the caret and new range; update ownership only on exact success.

Equal snapshots are no-ops. Extensions, shorter values, and revisions all replace the same verified
AX range. The AX writer never deletes by simulated key count; Accessibility-returned ranges define
its ownership. Emoji, combining marks, CJK, bidirectional text, and newlines remain AX acceptance
cases; LF is written as range data and never synthesized as Return.

### Interference and stale destinations

Keyboard/mouse activity and AX focus/selection notifications may proactively invalidate the
session, but every write still performs the checks above. A focus move never retargets the stream.
Writes always address the originally captured element. If the element is invalid, the process is
no longer frontmost, the caret moved, or the owned text changed, live writing stops permanently for
that hold.

There is no universal atomic transaction across the FeishuSpeech process and another application's
Accessibility server. Pre/post verification and captured-element addressing minimize the race and
ensure that a stale result cannot be intentionally routed to a newly focused field.

### Release and failures

- Release: stop capture, cross the recorder callback barrier, then drain queued/tail audio and
  recoverable replay within the same generation; do not retarget or reopen an owner.
- Safe action-2 final: reconcile the existing owned range/tail authoritatively, then close.
- No safe recognition after bounded drain: if no eligible recovery preview remains, release ownership
  and surface the fixed failure outcome; an eligible safe preview is retained in the same panel as
  non-authoritative read-only recovery text and cannot confirm or deliver.
- Stream failure after visible partial: keep the last verified text, release ownership, surface
  typed preservation feedback rather than ordinary success.
- Failure before visible text: zero target mutation.
- Destination invalidation: no later write and no automatic rollback.

Preserving visible text is deliberate. Once ownership becomes uncertain, deleting the range could
delete user edits or unrelated content.

## 9. Historical compatibility captured and unbound keyboard replacement (dormant)

Issue #40 v2 does not construct this writer from an accepted interaction. The fixed-PID and HID
invariants remain recorded for historical safety review; external output still requires explicit
Send/Return through the review panel.

For a captured non-secure editable control that cannot support verified live replacement:

1. Startup `.finalOnly`, or a first-partial rebind returning `.finalOnly`, creates a continuous
   owner bound to the captured PID and exact `AXUIElement`; the rebound triggering partial is
   applied before its callback returns.
2. Every eligible current-generation packet response, including post-release drain responses, may
   claim its journal index once;
   an equal complete snapshot emits nothing and a different snapshot is offered immediately.
3. Before and after each replacement transaction, validation requires live Secure Input to be off, the
   captured token's security to remain affirmatively safe, the original PID to remain frontmost,
   and the current focused AX element to be exactly `CFEqual` to the captured element.
4. It replaces only this hold's keyboard text using the grapheme reconciliation algorithm below.
5. External caret-affecting input, destination/security failure, or delivery uncertainty permanently
   closes all full-text resend, one-shot current-focus, Cmd+V, alternate-target, and clipboard
   fallback paths.
6. Release keeps this owner armed through bounded drain. The safe action-2 final uses the same
   fixed-target replacement transaction before monitoring closes; it never opens a new owner,
   Cmd+V, or copy path.

For an interaction where no AX cursor/focused element can be captured or confirmed:

1. Audio and Feishu requests still stream normally; AX failure is not a startup error.
2. The first non-empty partial triggers exactly one new AX capability probe. A live result becomes
   the fixed verified AX destination for the rest of the hold.
3. A `.finalOnly` probe result creates the captured owner above. If the probe remains unavailable,
   `CurrentFocusAppendSession` captures the then-frontmost PID and begins activation monitoring.
4. It receives the same complete snapshots and applies the same replacement transaction.
5. Historical replay indices, contentless values, and LF/C0/C1/DEL-bearing values do not own or
   post on the generic keyboard route.
   A previously failed index may own once when replay first succeeds. There is no selection,
   navigation, pasteboard write, or uncertain resend.
6. Generation/admission, Secure Input, and the bound PID are rechecked immediately before and after
   a transaction. Monitor installation and baseline capture are atomic under the shared HID gate.
   The epoch is checked pre-transaction; the same lock is then held continuously across each
   complete Backspace or insertion key-down/key-up pair.
   App activation away, PID mismatch, external keyboard/mouse input, security rejection, epoch
   change, or delivery uncertainty permanently suspends output. Fn transitions and
   FeishuSpeech-tagged synthetic events are exempt.
7. Eligible action-2 and packet values may reconcile this owner only while the same generation and
   drain budget remain authoritative. Terminal/expiry cleanup suppresses all later values.

For the generic keyboard owner, reconciliation uses Swift extended grapheme clusters without
normalization:

```text
oldCharacters = Array(previousSnapshot)
newCharacters = Array(nextSnapshot)
commonCount   = exact longest-common-prefix count
deleteCount  = oldCharacters.count - commonCount
insertText   = String(newCharacters.dropFirst(commonCount))
```

`deleteCount` never uses UTF-8 bytes or UTF-16 units and never exceeds this hold's recorded owned
tail. The shared poster validates the positive PID, creates one tagged `.privateState` source, and
constructs every Backspace down/up pair followed by the modifier-free Unicode insertion down/up
pair, when needed, before posting anything. Construction or final security failure produces zero
posts. LF and all other action controls are rejected before snapshot claim/event construction. It
submits Backspaces and then the suffix in order to the one captured PID. Each pair acquires the
shared gate, verifies the armed epoch, and retains the lock until both key-down and key-up have been
posted. The previous snapshot advances only after
the complete transaction is submitted successfully. If the epoch changes after visible deletion,
the remaining transaction stops, the owner suspends, and the partial mutation is never rolled back.

This unbound path is best effort. The existing HID `CGEventTap` is the synchronous interference
authority: physical key-down, non-Fn modifier-change, mouse-down, and mouse-drag events acquire the
same gate before epoch advance, and the tap callback cannot return them for dispatch until a held
synthetic pair finishes. Tap timeout/user-input disable advances the epoch as loss of observability
before recovery. Local/global AppKit monitors are supplemental early-suspension signals; both must
arm or the writer fails closed. Application-initiated
caret movement inside the same PID still cannot be proven without AX. Fixed
PID, permanent suspension, and no resend contain but do not eliminate that residual risk. The app
does not ask for cursor confirmation and does not request a new runtime permission during the hold.
Secure fields remain fail-closed. With `autoInsert=false`, unsafe text, or no owner, recognition
remains available but neither path mutates the target/pasteboard or reports missing output as
missing recognition.

`CGEventPostToPid` does not report whether the destination control accepted, transformed, ignored,
or displayed the replacement. A `.posted` transaction therefore closes only the local submission
contract. Installed owner UAT is still required; no visible output after submission is PARTIAL and
does not authorize retry, global HID posting, rollback, or clipboard fallback after
uncertainty.

## 10. Review-first surface and original-target delivery

### Identity-first capture before recording

Review-first captures a complete application identity before starting audio/network work. The
identity contains PID, bundle identifier, executable URL, and launch date, preventing a reused PID
from satisfying the token; the running process and frontmost application must agree before and
after the AX attempt. A safe exact AX cursor remains preferred and requires Accessibility trust,
Secure Event Input off, a supported non-secure editable role/subrole, focused-element PID equal to
the frontmost PID, a valid selected range, and settable focus plus selected-range attributes.

AX capture returns a typed result. An ordinary non-secure capability miss after final live security
checks binds `applicationCurrentFocus` to the already captured complete application. Global Secure
Input, an affirmatively secure AX role, lost Accessibility trust, incomplete identity, PID reuse,
or identity drift rejects startup; these conditions do not enter the fallback. Capture performs no
AX setter and never queries or writes `kAXSelectedTextAttribute`. The fallback token contains no AX
element or selection and cannot be treated as exact cursor authority.

### One panel from held preview to human edit

`ReviewWindowController` retains one `ReviewPanel`. Streaming and sealing reuse it with key/main,
mouse, close, and editor authority disabled. Changed snapshots replace a read-only value in full.
After action 2 freezes a non-empty final, or an exact incomplete fallback from the latest usable
snapshot, a separate transition waits for the recorder barrier and gives the same nonactivating panel
durable `.editable` authority before any presentation-focus aid. Focus telemetry is typed and bounded
but never activates either application, hides Send, disables Return, revokes the draft, or becomes a
delivery gate. If the panel cannot become key, visible Send remains the bounded fallback; no global
Return monitor or target Return suppression is installed. There is no pending/retry-editing state.

The review panel keeps its 520x320 initial size, 420x240 minimum, and 760x600 maximum. Streaming
preview text and the native multiline editor use the shared 18pt transcript font. The panel omits
`.fullSizeContentView`, constraining read-only content below the titlebar/traffic-light controls;
the font correction does not enlarge the panel.

The editor preserves multiline text. Unmodified Return (including keypad Enter) confirms the current
draft; Shift+Return/Shift+Enter inserts one newline without confirming; Command+Return remains an
explicit confirmation shortcut. Return during marked text is passed to the input method. Escape, `取消`,
or window close discards. Whitespace-only text cannot confirm. A late recognition callback cannot
replace human-edited state, and a new Fn interaction cannot displace an unresolved draft.

### Exact-once fail-closed confirmation

Before any await, confirmation freezes the exact untrimmed draft, marks `.confirming`, revokes
repeat callback authority, and creates one immutable envelope/opaque handle without blocking MainActor.
Only the actual
Send button or qualified native Return/Enter creates the opaque intent; no zero-argument or optional-
revision coordinator seam can authorize output. The review-safe text classifier admits LF but
rejects NUL, tab, carriage return, DEL, and C1 controls before event construction.

Delivery never activates either application and uses only the captured complete identity, positive PID,
opaque target ID, and lease. The exact branch keeps the captured AX element/selection; the
application-current-focus branch performs no AX setter or later ambient recapture. The executor builds
and reads back one modifier-free Unicode key-down/key-up pair carrying the exact full UTF-16 draft,
including LF and non-BMP surrogate pairs, and posts only to the captured PID. Both events carry fixed
tag/source/PID provenance and read back exact payload, phase, empty flags, and target before the first
post. The product cap is 16,384 UTF-16 code units. Pair construction/readback precedes the final
leading/trailing security sandwich; each AX message has cancellation/deadline checkpoints.

Binding-specific AX/application identity, trust, Secure Input, and frontmost validation completes in
the final leading/trailing security sandwich after pair build/readback. Cancellation and deadline are
checked before and after every synchronous AX message, with cancellation first; no AX validation runs
under the final commit locks. Any physical, identity, security, or epoch transition before the first
down fails pre-boundary with zero posts.

Any identity, destination, security, text, modifier, epoch, deadline, cancellation, pair construction,
post, or postflight uncertainty before down is terminal for that attempt: no retarget, AX recapture,
automatic retry, or second delivery is authorized. Before key-down, all failure paths post zero. Once
key-down crosses the submission boundary, key-up is still attempted and the result is terminal
`submittedUnverified`, never consumed success; no resend or ordinary Send/Return re-exposure follows.
No failure path reads, writes, restores, copies, or pastes the clipboard. Discard performs no target
or pasteboard operation. The application-current-focus fallback proves the original application,
not the original control or caret within it.

### No pasteboard transaction

V5 removes the review pasteboard snapshot/write/restore scheduler and Cmd+V entirely. Every review
phase, including explicit confirmation, successful pair submission, failure, cancellation, focus
completion, and per-character editing, records zero review pasteboard reads/writes/restores/change-
count polls. The prior image-only pasteboard was measured after the rejected installed candidate;
it is user-owned and is not inspected or normalized by startup/migration. This removes the old
delayed-consumption race instead of trying to infer target reads from `changeCount`.

## 11. Coordinator and concurrency ownership

| Boundary | Owner | Rule |
|---|---|---|
| CGEventTap callbacks | private tap thread | marshal state changes; never run capture or AX work inline |
| input interference gate | private tap thread + `NSLock` | atomically arm/capture baseline; serialize physical epoch advance against each complete synthetic pair; tap-disable advances loss-of-observability |
| capture session start/stop | existing `sessionQueue` | blocking `AVCaptureSession` work stays off main |
| PCM conversion/coalescing | audio/buffer serial queues | preserve order; never block capture on network |
| Feishu sequence/token state | `FeishuStreamingSession` actor | one strict request chain per attempt; at most one active attempt |
| packet journal/retry admission | `MainViewModel @MainActor` | one recorder/ingress per hold; fresh sessions replay in order |
| snapshot/replay ledger | `MainViewModel @MainActor` | own each eligible journal index once; independently replace `latestSnapshot` |
| UI/status/session generation | `MainViewModel @MainActor` | single coordinator verdict for every callback |
| review read-only presentation | cancellable `@MainActor` task | fire-and-forget revision/ID gate; never awaited by capture or recognition |
| review editable transition | separate `@MainActor` task | action 2 + recorder barrier publish `.editable`; focus aid is separate, bounded, and advisory |
| review original application/delivery | `SystemReviewDestinationDelivery @MainActor` | exact app with AX/selection preferred, or app-bound current focus after a non-secure AX miss; one captured-PID Unicode pair; no retarget/retry |
| AX destination and owned range | `CursorTextSession @MainActor` | all target writes serialized and verified |
| historical keyboard destination | `CurrentFocusAppendSession @MainActor` | dormant fixed PID/exact AX checks; not constructed by the Issue #40 review route |

The coordinator starts capture and stream setup without blocking the main actor. It consumes audio
and stream events in generation-bound tasks. A recoverable attempt failure first claims/cancels the
current session, preserves generation/capture/output ownership, awaits backoff, and admits a fresh
session only after rechecking that the generation retains retry authority and, after release, drain
budget.

Review-first does not alter that topology. `captureDrainTask` never references the review presenter;
`consumerTask` never awaits panel work. Read-only surface updates are lossy presentation commands,
not recognition acknowledgements. Action 2 launches a third transition task, so recorder-barrier or
editor-readiness delay cannot stop journal admission, retry, replay, or terminal response settlement.

Normal terminal cleanup follows authoritative final reconciliation; abnormal cleanup order is:

1. invalidate the active identity and every output writer;
2. fail ingress, cancel consumer/transport work, and hide the overlay;
3. retain any already-running recorder-stop barrier independently and force-clean recorder state;
4. release transient destination, audio, token-session, and timer state;
5. await bounded transport cancellation and the retained recorder barrier when present;
6. only then return hot-key and view-model state to idle or the bounded error state.

A non-recoverable terminal packet or provider exception takes this sequence exactly once and cannot fall through
to normal finishing. The overlay is hidden before recorder/transport cleanup. Once the active
identity has been cleared, reflecting the same error back from `HotKeyService` updates no active
interaction; identical hot-key errors are not published again. These guards prevent recursive
teardown from continuously advancing the overlay generation and leaving its window visible.

## 12. UI and settings

- `reviewBeforeInsert` and `autoInsert` remain Codable/decode-compatible; both stored-settings
  decoders treat a missing legacy field as true. Both values are runtime-inert, and Settings cannot
  restore a compatibility/direct-output route or bypass review.
- Settings changes cannot reroute an active hold or unresolved draft. Every accepted interaction
  creates one review authority before capture/provider startup.
- The recording overlay continues to appear on the screen containing the mouse pointer and remains
  status-only. Its implementation and issue #37 owner-UAT gate are unchanged.
- The separate review panel is one retained `NSPanel`: nonactivating/read-only while listening and
  sealing, then `.editable` immediately after action 2 and the recorder barrier. Send/qualified
  Return is installed before the separate presentation-focus aid completes; no pending or retry-
  editing UI exists, and focus failure cannot hide or disable confirmation.
- The panel remains 520x320 initially, with 420x240 minimum and 760x600 maximum. The streaming
  preview and native editor share an 18pt transcript font without enlarging those bounds. Removing
  `.fullSizeContentView` keeps read-only content below the titlebar/traffic-light controls.
- Transcript content appears only as the intended review body/editor, where assistive technology
  can naturally expose it. It never appears in the window title, fixed feedback, menu bar, logs,
  notifications, or added accessibility label/help metadata.
- `playSound` may retain start/final feedback but must not play once per partial.
- `autoInsert` cannot bypass explicit confirmation. Send, unmodified Return/Enter, or Command+Return
  confirms; Shift+Return/Shift+Enter inserts LF without confirming; Cancel/Escape/window close
  discards; Return during marked text is left to the input method; whitespace-only cannot confirm.
- The former issue #27 `autoInsert=true/false` writer branches are historical/dormant; no accepted
  interaction constructs them. Secure target probing and delivery remain fail-closed.
- A target capability warning is per interaction; it does not silently change the saved setting.
  An ordinary non-secure strict-AX cursor miss is not a review startup error: it uses the captured
  application's current-focus binding. Secure Input, secure/password AX roles, lost trust,
  incomplete identity, PID reuse, and identity drift remain fail-closed startup errors.
- Empty-recognition and pre-boundary failure feedback are fixed transcript-free strings. Review delivery
  failures before down use the retained draft feedback (`输入失败；草稿已保留，请编辑后显式发送。`)
  and never claim that a target accepted or displayed text. After down, `submittedUnverified` is the
  terminal non-consumption result: no resend and no ordinary Send/Return re-exposure.
- Authentication failure uses the fixed private feedback `认证失败，请检查应用凭据`; provider detail,
  credentials, and transcript content never appear in that message.
- Recoverable in-hold failures have no user-facing error or system notification; only the eventual
  terminal hold outcome may produce one fixed feedback state.

## 13. Privacy, security, and diagnostics

Allowed diagnostic fields:

- typed lifecycle/capability/failure, eligibility, ownership, shape, and output enums;
- generation, monotonic attempt identifier, retry failure streak, journal index, source, and event kind;
- review lifecycle tags, revision/identity authority decisions, and typed activation/delivery results;
- packet action, sequence number, byte count, bounded-queue occupancy, snapshot decision,
  previous/new/common-prefix UTF-16 and `Character` counts, Backspace/insertion counts, route, and
  transaction outcome.

Forbidden diagnostic fields:

- partial, final, provisional, selected, or clipboard text;
- PCM or encoded audio;
- App ID, App Secret, bearer token, stream ID, URL body, or raw backend message;
- focused-control value, application/window title, document name, or clipboard snapshot.

Diagnostics never include a transcript hash. Response shape is diagnostic only and cannot change
journal-index ownership. Review state, editable draft, and destination tokens are in-memory only;
the v5 review route has no clipboard snapshot. Every pre-confirm phase has zero target/synthetic
output side effects. Explicit confirmation builds one capped Unicode pair before the final security
sandwich; focus, delivery, ambient security, cancellation, and deadline failures before down retain
the exact draft and never copy it, retry it, activate, or retarget it. Down-crossed outcomes are
submitted-unverified only.

No cursor destination survives the process lifetime or is persisted to UserDefaults.

## 14. Implemented slices and remaining live gate

1. **Contract seams and fakes — complete**
   - Typed stream events/failures, audio-ingress configuration, Accessibility client, streaming
     provider, output, and overlay seams are present and test-owned.
2. **Bounded streaming recorder — complete**
   - Capture-order coalescing, exact drain-aware byte accounting, callback-barrier sealing, tail,
     overflow, interruption, and cleanup behavior are implemented and covered.
3. **Feishu streaming actor — complete locally**
   - Request models, stream ID generation, explicit serial gate, first-packet token refresh,
     exact-once finish, failed-established-stream exact-once abort, typed numeric failures, and
     sanitized diagnostics are implemented and covered.
4. **Historical cursor writer services — retained locally, dormant in v2**
   - AX replace/read-back and fixed destination boundaries remain in the retained service types. The
     issue #26 suffix-only generic writer and blanket Backspace prohibition are replaced by the issue
     #27 transaction contract for historical callers; accepted Issue #40 interactions do not invoke
     these writers.
     Earlier atomic race tests landed in `8ebf31e` and the unified seam in `81dbfc8`; production
     `ec4ddd6` atomically arms/captures the baseline and holds the shared gate across each pair,
     while `cd1132c` directly exercises that production poster and epoch gate together.
5. **Shared coordinator/state pipeline — implemented locally**
   - Production hot-key work uses one generation-owned recorder/ingress, ordered journal, fresh
     serial session attempts, ACK-reset consecutive-failure backoff, journal-indexed replay
     ownership, capture-only release followed by bounded drain, attempt-scoped operation watchdogs,
     and identity-owned cleanup. Whole-file recognition remains compatibility-only.
6. **Review state, same panel, and destination delivery — implemented locally (issues #38/#39/#40)**
   - Unconditional streaming/sealing preview, recorder-barrier direct `.editable` transition,
     durable human-editable draft, real Send/qualified Return intent, complete application identity
     with exact AX preference or application-current-focus fallback, bounded focus telemetry, one
     captured-PID Unicode pair, terminal uncertainty, no-copy/no-pasteboard failure return, and
     16,384 UTF-16/provenance/epoch gates are implemented locally. Drain expiry preserves an eligible
     safe exact-LF preview in the same panel as non-authoritative `ReviewReadOnlyPhase.recovery`
     without Send/Return, editing, output, retry, or retarget; authoritative action 2 plus the
     recorder barrier remain required for `.editable`. Independent final review and replacement
     installation remain outstanding.
7. **UI/settings docking — complete**
   - `reviewBeforeInsert` and `autoInsert` safely decode legacy payloads but are runtime-inert. The
     separate review panel exposes the intended transcript while the unchanged overlay remains
     status-only; `playSound` is unchanged.
8. **Live installed-Release gate — pending owner UAT**
   - Credential-bearing abort/retry/replay, real same-panel WindowServer/focus behavior, original-
     target AX restoration, process-targeted Unicode-pair consumption, and exact versus
     application-bound current-focus review delivery must be tested in the installed Release before
     general availability. The v7 replacement is installed, but owner UAT remains open.

Test/production custody separation was preserved for the automated implementation cycle.

## 15. Automated test evidence

### Transport

- action/sequence order for one packet, many packets, release, max duration, and cancel;
- no parallel requests;
- first-packet token refresh reuses action/sequence exactly once;
- failed first action 1 emits no abort; failed established action 0/action 2 emits action 3 once;
  successful action 2 suppresses it and no request overlaps;
- finish/cancel idempotence and bounded abort;
- empty, malformed, non-200, backend-error, timeout, and cancellation responses are sanitized.
- code-zero missing data/text returns an empty event; response identity echoes and unexpected echo
  types are ignored; `recognition_text` takes precedence over the `text` fallback.

### Audio

- production conversion remains 16 kHz mono Int16 at 32,000 bytes/s;
- arbitrary callback sizes coalesce into ordered 6,400-byte elements;
- the 60-second bound is 1,920,000 bytes / 300 elements;
- stop flushes no more than one tail;
- an established short tail pads to 3,200 bytes; a stream with no first packet cancels locally;
- overflow fails explicitly without drop or reorder; fresh sessions replay the journal's exact
  packet boundaries in order;
- interruption, device loss, conversion exhaustion, reset, and deinit close all continuations.

### Historical cursor writer with fake AX client (issue #27 evidence)

These cases document the retained AX writer service, not an accepted Issue #40 v2 route. The
current review route keeps snapshots in the same panel until explicit confirmation; its readiness,
delivery, and security failure cases are listed below.

- collapsed cursor and non-empty initial selection;
- first insert, duplicate no-op, longer/shorter/revised replacement, and non-empty final;
- emoji, combining marks, CJK, right-to-left text, and newline content using returned AX ranges;
- frontmost PID, focused element, caret, selection, generation, and owned-text mismatch;
- element invalidation and `kAXErrorCannotComplete` before/after mutation;
- empty final and stream failure preserve last verified partial;
- secure field rejection and unsupported target final-only selection;
- AX destination capture/confirmation failure selects unbound fallback instead of blocking startup;
- late partial/final after commit, invalidation, reset, or new generation writes nothing.

### Historical current-focus snapshot replacement writer (issue #27 evidence)

- exact duplicate posts nothing; extension, shorter, and revision examples produce the exact
  grapheme-counted Backspaces and replacement suffix;
- emoji ZWJ, combining marks, flags, CJK, and RTL use `Character` deletion counts;
- LF/newline is rejected before generic keyboard ownership/posting and remains accepted only as AX
  range data;
- all Backspace and insertion events are constructed before the first post and submitted in order
  to the captured PID; construction failure produces zero mutation;
- monitor installation and baseline epoch capture are atomic under the shared gate;
- the HID tap epoch is checked pre-transaction; the shared lock remains held across each complete
  Backspace or insertion key-down/key-up pair, and physical input acquires the same gate before
  epoch advance/dispatch;
- tap timeout/user-input disable advances loss-of-observability and permanently suspends;
- local/global AppKit monitors are supplemental, both must arm, and arm failure is fail-closed;
- app activation/PID, security, generation, or delivery uncertainty permanently suspends; tagged
  synthetic events and Fn transitions do not self-suspend;
- no rollback, selection, navigation, pasteboard mutation, uncertain resend, or one-shot fallback;
- same-PID caret movement remains unobservable and is an explicit installed-UAT risk.

### Review-first state, UI, destination, and zero-side-effect output (issues #38/#40)

- missing legacy `reviewBeforeInsert` decodes to true; both legacy setting values round-trip without
  changing credentials and cannot change the runtime route;
- Settings changes cannot reroute an active hold or draft;
- one panel shows read-only streaming and sealing, then the same instance gains `.editable`
  authority immediately after action 2 and the recorder barrier; Send/qualified Return is available
  before presentation-focus telemetry completes;
- capture/journal and recognition/action-2 progress while read-only presentation is gated; editor
  readiness failure cannot block either data line;
- complete changed snapshots replace in full; duplicates and historical replay are suppressed;
- contentless action 2 uses the exact last usable snapshot with incomplete warning, or closes
  without an empty editor when no usable value exists;
- human edits survive late recognition; whitespace cannot confirm; focus/delivery failures,
  discard/close/Escape, and stale callbacks produce zero automatic output/copy; an editable draft
  rejects a successor Fn interaction;
- identity-first capture, exact-AX preference, ordinary non-secure strict-AX miss fallback, and
  complete application identity, AX element, focus, original selection, Secure Input, and pre/post
  mutation ordering are covered, including PID reuse, wrong-app activation, and bounded timeout;
- fixed-PID application-current-focus delivery requires two consecutive composite samples, each
  ordered Secure Input at start -> raw captured PID -> running/frontmost complete identities ->
  Secure Input at end; postflight uses the equivalent shape, preserves multiline bytes, posts one
  Unicode pair, and never performs an AX recapture;
- confirmation preserves exact LF-delimited multiline drafts while rejecting tab, CR, NUL, DEL,
  and C1 controls before event construction; the 16,384 UTF-16 cap rejects 16,385 with zero post;
- both Unicode events read back exact payload, phase, empty flags, tag, source PID, common source,
  and captured target PID; binding-specific validation runs in the final security sandwich after pair
  build/readback, with per-AX cancellation/deadline checks and no application activation;
- repeated confirmation has one local submission attempt; all uncertainty is terminal and never
  retargets or retries; pre-boundary failure posts zero, post-boundary failure still attempts key-up
  and returns terminal submitted-unverified without resend or ordinary confirmation re-exposure;
- every review phase, including explicit confirmation, has zero pasteboard reads/writes/restores/
  change-count polls and no Cmd+V construction or post;
- the final v5 focused Issue #40 serialization passes 324 executed tests, skips 0 tests, and has 0
  failures; all 105 streaming tests execute. The full serialized target passes 537 tests with 1
  expected live-TCP environmental skip and 0 failures; this does not prove WindowServer focus or
  target Unicode-pair consumption.

### Coordinator

- state order `idle -> pending -> streaming -> sealing -> idle`;
- release and 60-second cap race emits one finish;
- new Fn press during sealing is ignored;
- sleep/wake and manual reset invalidate before cleanup;
- recoverable 10024/network failures keep one capture active, abort one failed session, back off,
  create one fresh session, and replay the full ordered journal without early error feedback;
- packet ACK resets the consecutive retry streak, delays cap at 4 seconds, and attempts never overlap;
- release during backoff retains same-generation recovery inside the post-barrier budget;
  reset/security/lifecycle invalidation makes late retry work inert;
- terminal capture/auth/configuration failure cannot leave mic, overlay, writer, or hot-key state active;
- an immediate terminal provider event and a provider-auth exception each hide the overlay and
  clean the active generation exactly once;
- repeated identical hot-key errors publish once and cannot re-enter coordinator teardown;
- [Historical issue #27 writer evidence] initial final-only-capability, rebound final-only-capability,
  and unbound routes admit each eligible journal index once while independently suppressing equal
  snapshots; historical replay never re-owns, while a previously failed index may own once;
- release closes capture but keeps current-generation response/retry authority through a 60-second
  post-barrier drain; factory/send/finish each have a 30-second watchdog;
- action 2 plus the recorder barrier freezes the exact draft in the same panel and publishes
  `.editable` immediately; pre-boundary focus, delivery, and security failures retain that draft for
  editing or explicit discard with fixed, transcript-free feedback and no automatic copy/direct
  output/retry/retarget. Down-crossed delivery is terminal submitted-unverified. No pending UI or retry-editing control exists; Send/qualified Return is
  installed before the separate focus aid completes;
- [Historical issue #27 writer evidence] safe action-2 text reconciles the existing AX/fixed-PID
  owner before closure; expired, retired, stale, or post-terminal callbacks never create, append,
  rewrite, Cmd+V, or copy compatibility output;
- [Historical issue #27 writer evidence] output-disabled, unsafe, and ownerless usable held
  recognition completes without false empty-result/stream-error feedback and with zero output/copy;
- [Historical issue #27 writer evidence] the PID poster constructs the whole tagged private-source
  Backspace-plus-Unicode transaction before the final Secure Input sample, rejects LF/action controls,
  and submits events in order to the bound PID only through complete-pair atomic gate operations
  while the epoch remains unchanged;
- both `autoInsert` values produce the same review route; review always requires explicit confirmation
  regardless of the persisted legacy value;
- logs and feedback never contain recognized text.

### Live UAT matrix

- same review panel remains visible/nonactivating while held and sealing, then exposes editable
  Send/Return immediately after action 2; focus completion is advisory and should be observed
  separately;
- edit, bare Return/Enter confirmation, Shift+Return/Enter newline, Command+Return/Send,
  Cancel/Escape/close, and rapid repeated confirm;
- TextEdit/AppKit text view and text field;
- Notes or another native rich-text editor;
- Safari/Chrome editable web control;
- VS Code or another Electron editor;
- Terminal, iTerm2, and Ghostty command lines where Accessibility exposes safe ranges;
- a document editor with an undo stack;
- one ordinary non-secure final-only/editable AX target that previously showed `无法确认输入位置`
  because strict cursor capture missed, plus one target with an exact AX cursor;
- password and Secure Event Input rejection;
- focus switch, mouse caret move, user typing, target close, and app termination mid-hold;
- original target key-window/selection behavior for the exact route, current-focus behavior for
  the fixed-PID fallback, and no clipboard reads/writes/change-count mutation;
- forced focus and fallback pre-boundary failure with same-draft retention, plus post-boundary
  submitted-unverified/no-resend behavior and no automatic copy; verify that the fallback proves the original
  application, not the original control or caret;
- no target output while holding Fn, recognizing, streaming, sealing, rendering, typing individual
  draft characters, or awaiting focus; exactly one tagged Unicode down/up pair only after Send or
  qualified Return/Enter;
- multiline LF, emoji/non-BMP surrogate pairs, 16,384 accepted versus 16,385 rejected, held
  modifiers/epoch drift fail-closed, and terminal submitted-unverified semantics;
- 60-second speech under normal and deliberately slow network conditions;
- credential-bearing observation of Feishu partial evolution, recorded only as semantic shape, never
  with transcript content.

## 16. Completion boundary

Issue #25 supplied the initial contract. Issue #26 supplied the production implementation,
RED-first tests, independent correctness/security review, and documentation docking. Initial UAT
then superseded the strict AX destination startup gate. Later UAT isolated a real HTTP-200 business
failure after accepted packets, motivating [D-26-01](decisions/D-26-01.md). The latest build-5 leg
then recorded 66 HTTP-200 transactions over 13.55 seconds while visible output stalled after one
word, motivating issue #26's journal-indexed local frontier. Release 1.0 build 6 later proved that
this concatenated complete snapshots and repeated text. [D-27-01](decisions/D-27-01.md) replaces
that assembly rule with opaque snapshot replacement while retaining replay ownership and
fixed-target safety. Build 7 UAT then proved that immediate response-admission closure at Fn-up
discarded valid tail packets and the action-2 final. The current correction makes release a capture
boundary followed by recorder-barrier drain, recoverable replay, and authoritative terminal
reconciliation, with 30-second operation watchdogs and a 60-second post-barrier budget. Release 1.0
build 8 passed its historical 316/316 gate. [D-38-01](decisions/D-38-01.md) adds the review-first
third axis while preserving that capture/journal and recognition/retry/replay topology. It routes
complete snapshots to one read-only streaming/sealing panel, waits for action 2 and the recorder
barrier only in a separate editable-transition task, and makes edited explicit confirmation the
sole original-target delivery authority. [D-39-01](decisions/D-39-01.md) changes only the
editable review keyboard policy: unmodified Return/Enter confirms, Shift+Return/Enter inserts a
newline, Command+Return remains an explicit confirmation shortcut, and marked-text Return stays with the
input method. [D-40-01](decisions/D-40-01.md) then preserves exact AX preference while admitting an
ordinary non-secure strict-AX miss as an application-current-focus binding: the original complete
application is captured before panel/audio/provider startup, confirmation uses two consecutive
composites ordered Secure Input start -> raw PID -> running/frontmost identities -> Secure Input
end, then one fixed-PID Unicode pair; postflight uses the equivalent safety shape, and the fallback
proves the application rather than the original control or caret. D-40-01 v5 deletes the
`editablePending` authority and review pasteboard/Cmd+V transaction: action 2 plus the recorder
barrier publishes `.editable` immediately, focus is advisory telemetry, and only a real
Send/qualified Return creates the opaque confirmation intent. The pair is capped at 16,384 UTF-16
units, read back for provenance, and reports terminal submitted-unverified after mandatory up without
resend or ordinary confirmation re-exposure. V6 additionally repairs the delayed-Accessibility-grant
ordering defect by verifying the complete lifecycle observer set and reinstalling it immediately before
original-target capture when initialization preceded authorization. A failed bounded retry remains
pre-boundary and cannot emit any target signal. V7 then constrains initial focus capture to the frozen
application AX root. The final v7 focused matrix passes 324 executed tests,
skips 0 tests, and has 0 failures; all 105 streaming tests execute, and the full serialized target
passes 537 tests with 1 expected live-TCP environmental skip and 0 failures. The issue #27 writer remains historical
dormant service code only; persisted settings cannot disable review-first or restore it. The repaired
drain-expiry path retains an eligible safe same-generation preview, including exact LF, as
non-authoritative `ReviewReadOnlyPhase.recovery` in the same panel; it has no Send/Return/edit/delivery
authority, and authoritative action 2 plus the recorder barrier remain required for `.editable`.
Unsafe, oversized, empty, or stale previews still use fixed failure/preservation behavior.

General-availability closure remains intentionally separate: the owner will self-test the replacement
installed Release with real Feishu credentials and the live target-application matrix above. Until
the installed v7 replacement passes owner UAT, snapshot replacement, review WindowServer
activation/focus, original-target Accessibility restoration, actual Unicode-pair consumption,
action-3 acceptance, retry/replay recovery, release races, PCM/tail behavior, slow-network handling,
same-PID caret risk, and broad cross-application compatibility remain unverified. No
cumulative/delta/revision provider semantic is inferred beyond complete opaque replacement. Local
`CGEventPostToPid` transaction submission cannot substitute for the visible target-acceptance
observation required from owner UAT and never authorizes an uncertainty retry. The rejected v3
installed candidate was stopped; the authorized v6 replacement was also rejected after capture failure.

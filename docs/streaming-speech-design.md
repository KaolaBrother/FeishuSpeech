# Cursor-bound streaming speech design

Status: issue #27 snapshot replacement, release-drain lifecycle, resilience watchdogs, and the
atomic HID interference gate are implemented. Release 1.0 build 8 passes the final 316/316 test
suite, strict SwiftLint, and Debug and Release builds; installed Release credential-bearing and
cross-application UAT remains pending.

## 1. Outcome

Holding Fn for the existing 0.3-second gate starts a Feishu streaming-recognition interaction.
When a safe AX range is available, each different complete snapshot replaces one provisional text
range at the cursor that was active when the interaction began.
If an affirmatively safe target is captured but lacks live AX range replacement, startup now arms a
continuous keyboard owner bound to its original PID and exact `AXUIElement`. If AX cursor/focus
capture is unavailable, recording and streaming still proceed; the first non-empty hypothesis
re-probes AX once, and a final-only rebound arms the same captured owner while a still-unavailable
result arms an unbound PID-only owner. Each eligible held packet response owns its journal index
once, independently of recognition state. Equal complete snapshots emit nothing; a different
snapshot replaces `latestSnapshot` and is offered immediately while Fn remains held. Release
stops capture but leaves the existing generation and owner active while queued/tail audio drains,
recoverable attempts replay, and action 2 produces the authoritative terminal snapshot. The owner
closes only after that snapshot is reconciled or a bounded terminal outcome wins. Release never
retargets output. The FeishuSpeech overlay reports neutral state only; it
does not host a transcript preview,
editable draft, or send button and does not claim that a target accepted synthetic input.

The implementation ports KaolaTerminal's stream transport and bounded-ingress rules, but deliberately
replaces its preview/review UI with an opportunistic macOS Accessibility writer plus a guarded
same-PID grapheme-aware keyboard replacement writer when no AX destination can be established.
Verified AX may carry LF as multiline text data. The generic keyboard route rejects LF and every
other action control so recognition never becomes Return, submit, or execute input.

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

Issue #26's lifecycle-free 272/272 evidence predates the issue #27 correction. Issue #27 requires
new focused and full-suite evidence; neither automated suite replaces installed UAT. In particular,
`CGEventPostToPid` exposes no target-control acceptance acknowledgement, so `.posted` cannot prove
visible text.

The latest installed build-5 evidence recorded 66 HTTP-200 transactions over 13.55 seconds while
visible output stopped after one word. It proves continued transport, not response shape,
coordinator ownership, or target acceptance. Earlier observations of undefined business code
`10024` remain transport history; neither observation proves provider text semantics.

## 3. Goals and non-goals

### Goals

- Show recognized text in the original target application while the user speaks when verified AX
  range replacement is supported.
- Preserve the 0.3-second Fn gate, 60-second maximum hold, multi-display status overlay, sleep/wake
  cleanup, microphone/accessibility permissions, and Keychain credential storage.
- Use verified AX replacement when available; otherwise reconcile only this hold's keyboard text
  with grapheme-counted Backspaces followed by the replacement suffix.
- Never redirect a captured AX write. The current-focus fallback binds one frontmost PID on first
  output and permanently suspends after a detectable process/security/delivery change.
- Keep audio memory and network backpressure bounded.
- Keep cancellation, reset, and error paths idempotent and generation-safe.
- Preserve recognition when output is disabled, unsafe, or ownerless without inventing an output,
  empty-result, or stream-failure outcome.

### Non-goals

- A transcript preview, editable review panel, or explicit Send/Discard UI.
- Whole-file fallback after a stream has been established.
- Translation, speaker diarization, punctuation controls, or multiple simultaneous streams.
- A universal input-method extension or custom IME.
- Removing or redefining the existing `autoInsert` preference.
- Changing the compatibility-only whole-file API into a fallback for a streaming interaction.

## 4. End-to-end architecture

```text
private CGEventTap thread
        |
        | Fn held 0.3 s / released / cancel
        v
HotKeyService ------------------------------+
        |                                    |
        v                                    v
MainViewModel (@MainActor)          CursorTextSession (@MainActor)
        |                                    |
        | generation + lifecycle             | captured AXUIElement
        |                                    | owned provisional range
        v                                    | verify -> replace -> verify
AudioRecorder                                v
        | ordered 16 kHz Int16 PCM      original target application
        | 6,400-byte coalesced chunks
        v
bounded AsyncThrowingStream<Data>
        |
        v
ordered per-hold packet journal
        |
        v
one FeishuStreamingSession (actor) per attempt
        | strict action/sequence POST chain; fresh-session replay after recoverable failure
        v
partial / final / cancelled / failed
        |
        +--------------> MainViewModel generation gate
                                |
                                +--> snapshot ledger: own journal index once + replace latest snapshot
                                                |
                                                +--> one AX or PID-bound owner
```

Verified AX writes belong only to `CursorTextSession`. Captured final-only-capability destinations
and AX-unavailable destinations use `CurrentFocusAppendSession`; the captured variant binds the
original PID plus exact AX element, while the unbound variant binds one frontmost PID. Both post
one ordered Backspace-plus-Unicode replacement transaction after security/destination checks. They
reject LF/action controls, use no selection, cursor navigation, or per-partial pasteboard mutation.
The transport does not know about
focus or UI, and no output boundary knows about audio, credentials, or HTTP.

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
      -> idle                         final applied or fallback completed
```

`transcribing` is retired from the production state because recognition now overlaps capture.
`sealing` is explicit: it prevents a second Fn hold from racing the first stream's tail and final
response.

### Session generation

Every accepted hold receives a monotonically increasing generation. Audio callbacks, stream
events, cursor writes, timers, overlay updates, and cleanup capture that generation. Reset,
sleep/wake, permission loss, manual service reset, and terminal failure invalidate the active
identity and cursor ownership before cancelling work. A callback whose identity is no longer
current is a no-op.

### Writer state

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

A safe non-empty action-2 snapshot is authoritative and is reconciled through the existing AX or
fixed-PID keyboard owner before admission closes. Expiry preserves verified committed output,
distinguishes delivery uncertainty, and emits one fixed error only when no safe output exists.
Deadline/cancellation winners retire their attempt; late results cannot mutate output.
An abnormal lifecycle event does not wait on that barrier to revoke authority: generation/output
writers and transport are cancelled immediately, while the independently retained recorder barrier
continues to block a successor and final idle/error publication.

## 8. Cursor-bound text replacement

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
- No safe recognition after bounded drain: release ownership and surface the fixed failure outcome.
- Stream failure after visible partial: keep the last verified text, release ownership, surface
  typed preservation feedback rather than ordinary success.
- Failure before visible text: zero target mutation.
- Destination invalidation: no later write and no automatic rollback.

Preserving visible text is deliberate. Once ownership becomes uncertain, deleting the range could
delete user edits or unrelated content.

## 9. Captured and unbound keyboard replacement

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

## 10. Coordinator and concurrency ownership

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
| AX destination and owned range | `CursorTextSession @MainActor` | all target writes serialized and verified |
| keyboard destination | `CurrentFocusAppendSession @MainActor` | fixed PID/exact AX checks; serialize owned-tail Backspace plus suffix replacement |

The coordinator starts capture and stream setup without blocking the main actor. It consumes audio
and stream events in generation-bound tasks. A recoverable attempt failure first claims/cancels the
current session, preserves generation/capture/output ownership, awaits backoff, and admits a fresh
session only after rechecking that the generation retains retry authority and, after release, drain
budget. Normal terminal cleanup follows authoritative final reconciliation; abnormal cleanup order is:

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

## 11. UI and settings

- The overlay continues to appear on the screen containing the mouse pointer.
- Listening state remains visually distinct from sealing/finalizing state.
- Transcript content never appears in the overlay, menu bar, logs, notifications, or accessibility
  labels owned by FeishuSpeech.
- `playSound` may retain start/final feedback but must not play once per partial.
- `autoInsert=true` enables verified AX live replacement or captured/fixed-PID grapheme-aware
  keyboard replacement when AX is unavailable. AX may write multiline data; keyboard replacement
  rejects LF/action controls. Release-time fallbacks are removed.
- `autoInsert=false` keeps streaming recognition active but discards cursor-writing capability and
  performs no target or pasteboard mutation. Secure target probing remains fail-closed.
- A target capability warning is per interaction; it does not silently change the saved setting.
- Empty-recognition and uncertain-output feedback are fixed transcript-free strings
  shown for two seconds; coordinator state may already be idle while the generation-guarded overlay
  remains visible. Preservation statuses use neutral wording (`未返回可用最终文本` and
  `自动输入状态不确定，请检查光标处内容`) and never claim that a target accepted or displayed text.
- Authentication failure uses the fixed private feedback `认证失败，请检查应用凭据`; provider detail,
  credentials, and transcript content never appear in that message.
- Recoverable in-hold failures have no user-facing error or system notification; only the eventual
  terminal hold outcome may produce one fixed feedback state.

## 12. Privacy, security, and diagnostics

Allowed diagnostic fields:

- typed lifecycle/capability/failure, eligibility, ownership, shape, and output enums;
- generation, monotonic attempt identifier, retry failure streak, journal index, source, and event kind;
- packet action, sequence number, byte count, bounded-queue occupancy, snapshot decision,
  previous/new/common-prefix UTF-16 and `Character` counts, Backspace/insertion counts, route, and
  transaction outcome.

Forbidden diagnostic fields:

- partial, final, provisional, selected, or clipboard text;
- PCM or encoded audio;
- App ID, App Secret, bearer token, stream ID, URL body, or raw backend message;
- focused-control value, application/window title, document name, or clipboard snapshot.

Diagnostics never include a transcript hash. Response shape is diagnostic only and cannot change
journal-index ownership.

No cursor destination survives the process lifetime or is persisted to UserDefaults.

## 13. Implemented slices and remaining live gate

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
4. **Cursor text session and issue #27 continuous output — implemented locally**
   - AX replace/read-back and fixed destination boundaries remain. The issue #26 suffix-only generic
     writer and blanket Backspace prohibition are replaced by the issue #27 transaction contract;
     Earlier atomic race tests landed in `8ebf31e` and the unified seam in `81dbfc8`; production
     `ec4ddd6` atomically arms/captures the baseline and holds the shared gate across each pair,
     while `cd1132c` directly exercises that production poster and epoch gate together.
5. **Coordinator/state migration — implemented locally**
   - Production hot-key work uses one generation-owned recorder/ingress, ordered journal, fresh
     serial session attempts, ACK-reset consecutive-failure backoff, journal-indexed replay
     ownership, capture-only release followed by bounded drain, attempt-scoped operation watchdogs,
     and identity-owned cleanup. Whole-file recognition remains compatibility-only.
6. **UI/settings docking — complete**
   - Status-only listening/sealing/final-only and fixed completion feedback preserve `autoInsert`
     and `playSound` semantics without exposing recognized text.
7. **Live compatibility gate — pending owner UAT**
   - Credential-bearing abort/retry/replay and cross-application AX/current-focus behavior must be
     tested in the installed Release before declaring general availability.

Test/production custody separation was preserved for the automated implementation cycle.

## 14. Automated test evidence

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

### Cursor writer with fake AX client

- collapsed cursor and non-empty initial selection;
- first insert, duplicate no-op, longer/shorter/revised replacement, and non-empty final;
- emoji, combining marks, CJK, right-to-left text, and newline content using returned AX ranges;
- frontmost PID, focused element, caret, selection, generation, and owned-text mismatch;
- element invalidation and `kAXErrorCannotComplete` before/after mutation;
- empty final and stream failure preserve last verified partial;
- secure field rejection and unsupported target final-only selection;
- AX destination capture/confirmation failure selects unbound fallback instead of blocking startup;
- late partial/final after commit, invalidation, reset, or new generation writes nothing.

### Current-focus snapshot replacement writer (required issue #27 evidence)

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
- initial final-only-capability, rebound final-only-capability, and unbound routes admit each
  eligible journal index once while independently suppressing equal snapshots; historical replay
  never re-owns, while a previously failed index may own once;
- release closes capture but keeps current-generation response/retry authority through a 60-second
  post-barrier drain; factory/send/finish each have a 30-second watchdog;
- safe action-2 text reconciles the existing AX/fixed-PID owner before closure; expired, retired,
  stale, or post-terminal callbacks never create, append, rewrite, Cmd+V, or copy output;
- output-disabled, unsafe, and ownerless usable held recognition completes without false
  empty-result/stream-error feedback and with zero output/copy;
- the PID poster constructs the whole tagged private-source Backspace-plus-Unicode transaction
  before the final Secure Input sample, rejects LF/action controls, and submits events in order to
  the bound PID only through complete-pair atomic gate operations while the epoch remains unchanged;
- `autoInsert=false` produces no target writes;
- logs and feedback never contain recognized text.

### Live UAT matrix

- TextEdit/AppKit text view and text field;
- Notes or another native rich-text editor;
- Safari/Chrome editable web control;
- VS Code or another Electron editor;
- Terminal, iTerm2, and Ghostty command lines where Accessibility exposes safe ranges;
- a document editor with an undo stack;
- password and Secure Event Input rejection;
- focus switch, mouse caret move, user typing, target close, and app termination mid-hold;
- 60-second speech under normal and deliberately slow network conditions;
- credential-bearing observation of Feishu partial evolution, recorded only as semantic shape, never
  with transcript content.

## 15. Completion boundary

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
build 8 passes 316/316 tests, strict SwiftLint, and Debug and Release builds. Installed Release
credential-bearing and cross-application verification remains pending.

General-availability closure remains intentionally separate: the owner will self-test the installed
Release with real Feishu credentials and the live target-application matrix above. Until the
repaired build passes owner UAT, snapshot replacement, visible target mutation, action-3 acceptance,
retry/replay recovery, release races, PCM/tail behavior, slow-network handling, same-PID caret risk,
and broad cross-application compatibility remain unverified. No cumulative/delta/revision provider
semantic is inferred beyond complete opaque replacement.
Local `CGEventPostToPid` transaction submission cannot substitute for the visible target-acceptance
observation required from owner UAT.

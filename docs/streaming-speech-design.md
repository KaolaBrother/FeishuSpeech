# Cursor-bound streaming speech design

Status: accepted design for issue #25; implementation has not started.

## 1. Outcome

Holding Fn for the existing 0.3-second gate starts a Feishu streaming-recognition interaction.
While Fn remains held, each recognized hypothesis replaces one provisional text range at the
cursor that was active when the interaction began. Releasing Fn seals the stream and replaces the
same range with the final response. The FeishuSpeech overlay reports state only; it does not host a
transcript preview, editable draft, or send button.

The design ports KaolaTerminal's proven stream transport and bounded-ingress rules, but deliberately
replaces its preview/review UI with a macOS Accessibility writer bound to the original editable
control.

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

Feishu does not state whether intermediate `recognition_text` is a delta, cumulative text,
stabilized segments, or a revisable hypothesis. No implementation may claim one of those forms
without credential-bearing live evidence. Every partial is therefore treated as the complete
opaque replacement state for the current moment.

Accessibility behavior is application-dependent. Native AppKit, WebKit, Electron, terminal, and
document-editor targets require live UAT before broad compatibility claims are made.

## 3. Goals and non-goals

### Goals

- Show recognized text in the original target application while the user speaks.
- Preserve the 0.3-second Fn gate, 60-second maximum hold, multi-display status overlay, sleep/wake
  cleanup, microphone/accessibility permissions, and Keychain credential storage.
- Never append an opaque partial blindly.
- Never redirect a late result to a new focus or cursor.
- Keep audio memory and network backpressure bounded.
- Keep cancellation, reset, and error paths idempotent and generation-safe.
- Provide a deterministic final-only mode where verified live replacement is unavailable.

### Non-goals

- A transcript preview, editable review panel, or explicit Send/Discard UI.
- Whole-file retry after a stream has been established.
- Translation, speaker diarization, punctuation controls, or multiple simultaneous streams.
- A universal input-method extension or custom IME.
- Removing or redefining the existing `autoInsert` preference.
- Swift production or test changes in issue #25.

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
StreamingAudioRecorder                       v
        | ordered 16 kHz Int16 PCM      original target application
        | 6,400-byte coalesced chunks
        v
bounded AsyncThrowingStream<Data>
        |
        v
FeishuStreamingSession (actor)
        | strict action/sequence POST chain
        v
partial / final / cancelled / failed
        |
        +--------------> MainViewModel generation gate
```

No component other than `CursorTextSession` writes to the target application. The transport does
not know about focus or UI. The writer does not know about audio, credentials, or HTTP.

## 5. State model

### Hot-key state

```text
idle
  -> pending(startedAt)
      -> idle/cancelled               Fn released or another modifier/key before 0.3 s
      -> streaming(sessionID)         gate elapsed, target and capture start accepted
          -> sealing(sessionID)       Fn release or 60 s cap
          -> error                    capture/stream/destination startup failure
      -> idle                         final applied or fallback completed
```

`transcribing` is retired from the production state because recognition now overlaps capture.
`sealing` is explicit: it prevents a second Fn hold from racing the first stream's tail and final
response.

### Session generation

Every accepted hold increments a monotonically increasing generation. Audio callbacks, stream
events, cursor writes, timers, overlay updates, and cleanup capture that generation. Reset,
sleep/wake, permission loss, manual service reset, and terminal failure increment it before
cancelling work. A callback whose generation is not current is a no-op.

### Writer state

```text
unavailable
  | capability probe failed -> finalOnly
  | capability probe passed -> armed(destination, originalSelection)

armed
  | first non-empty partial -> provisional(range, lastText)
  | invalidation            -> invalid

provisional
  | replacement verified    -> provisional(updatedRange, newText)
  | non-empty final         -> committed
  | empty final / failure   -> preserved
  | destination mismatch    -> invalid
```

`invalid`, `committed`, and `preserved` are terminal for that hold. No later callback can revive
the writer.

## 6. Audio and backpressure

The current recorder already converts capture to 16 kHz, mono, signed Int16 PCM. The redesign
changes ownership from one complete `Data` buffer to ordered streaming elements:

- raw `AVCaptureAudioDataOutput` callbacks remain on `audioQueue`;
- converted PCM is coalesced on the serial buffer boundary;
- each yielded normal element is exactly 6,400 bytes (200 ms);
- stop flushes at most one non-empty tail;
- after `action=1` is accepted, a tail shorter than 3,200 bytes is padded with PCM silence to the
  100 ms minimum before normal finish;
- if no first packet was emitted, release cancels locally and sends neither finish nor abort;
- yielded elements enter a non-blocking `AsyncThrowingStream<Data>` bounded by bytes.

Capacity calculation for the retained 60-second maximum:

```text
16,000 samples/s * 2 bytes/sample = 32,000 bytes/s
32,000 bytes/s * 60 s             = 1,920,000 bytes maximum
1,920,000 / 6,400                 = 300 full elements
```

The bound is a safety ceiling, not a desired queue depth. Under healthy network conditions the
consumer drains near real time. If the producer would exceed the byte ceiling, capture and stream
fail explicitly with `ingressOverflow`; no PCM is silently dropped, reordered, replayed, or sent in
parallel.

## 7. Feishu streaming protocol

One `FeishuStreamingSession` actor owns all mutable transport state:

```text
streamID
nextSequenceID
token
didAcknowledgeFirstPacket
didRefreshFirstPacket
terminalIntent: none | finish | cancel
terminalActionEmitted
isCompleted
currentRequestTask
```

Request rules:

| Moment | Action | Audio | Sequence |
|---|---:|---|---:|
| first packet | 1 | non-empty 100–200 ms PCM | 0 |
| continuation | 0 | non-empty 100–200 ms PCM | 1...n |
| normal seal | 2 | empty | next |
| active cancel | 3 | empty | next |

- Exactly one request may be in flight. Actor isolation alone is insufficient if cancellation and
  request work use child tasks, so the session retains an explicit serial request gate.
- A token-invalid response before the first accepted packet may clear the token cache, fetch once,
  and retry the same action/sequence. It does not consume a new sequence number.
- After acceptance, any HTTP, backend, decoding, timeout, or connectivity failure terminates that
  stream. There is no replay, retry loop, or `file_recognize` fallback.
- `finish()` and `cancel()` are idempotent. Cancellation abort has a short bounded deadline and is
  best-effort.
- Public errors are sanitized. Raw response bodies and backend messages do not reach UI or logs.

Events exposed to the coordinator are typed:

```text
partial(String)
final(String)
cancelled
failed(StreamFailure)
```

## 8. Cursor-bound text replacement

### Capability probe

At the transition from `pending` to `streaming`, `CursorTextSession.begin()`:

1. Confirms Accessibility trust and rejects Secure Event Input.
2. Reads the system-wide focused UI element once.
3. Captures its PID and verifies it is still the frontmost application.
4. Rejects a secure-text subrole or non-editable element.
5. Reads the original `kAXSelectedTextRangeAttribute`.
6. Requires selected-text and selected-range attributes to be settable.
7. Requires string-for-range support for read-back verification.
8. Creates an in-memory destination token; it is never persisted or logged with control content.

Failure at steps 4–7 selects final-only mode. Secure-input failure rejects the interaction
entirely.

### First partial

Before the first write, the session verifies that generation, PID, focused element, and original
selection still match. It then sets `kAXSelectedTextAttribute` on the captured element, replacing
the original selection. It reads the resulting collapsed caret and the string for the candidate
range. Only a successful exact read-back establishes ownership.

The base location comes from the original selection. The owned range length comes from the
post-write caret/range values returned by Accessibility, not from Swift character counting.

### Later partials

For each distinct non-empty response:

1. Verify the destination token and generation.
2. Verify the same process and focused element.
3. Verify a collapsed caret at the owned range end.
4. Read the owned range and require exact equality with `lastWrittenText`.
5. Set the selected range to the owned range on the captured element.
6. Set selected text to the complete new response.
7. Read back the caret and new range; update ownership only on exact success.

This is replace-not-append. If Feishu changes `hello worl` to `hello world`, the writer replaces
the entire prior range. If it revises the hypothesis to `yellow world`, the same operation remains
correct.

The writer never deletes by simulated key count. It never computes deletion length from UTF-8
bytes, Unicode scalar count, or Swift grapheme count. Emoji, combining marks, CJK, and bidirectional
text are acceptance cases for the Accessibility adapter.

### Interference and stale destinations

Keyboard/mouse activity and AX focus/selection notifications may proactively invalidate the
session, but every write still performs the checks above. A focus move never retargets the stream.
Writes always address the originally captured element. If the element is invalid, the process is
no longer frontmost, the caret moved, or the owned text changed, live writing stops permanently for
that hold.

There is no universal atomic transaction across the FeishuSpeech process and another application's
Accessibility server. Pre/post verification and captured-element addressing minimize the race and
ensure that a stale result cannot be intentionally routed to a newly focused field.

### Final and failures

- Non-empty final: verified full-range replacement, caret at end, ownership released.
- Empty final after visible partial: keep the partial, release ownership, surface warning.
- Stream failure after visible partial: keep the last verified text, release ownership, surface
  failure.
- Failure before visible text: zero target mutation.
- Destination invalidation: no later write and no automatic rollback.

Preserving visible text is deliberate. Once ownership becomes uncertain, deleting the range could
delete user edits or unrelated content.

## 9. Final-only fallback

Unsupported editable controls do not receive experimental key-event replacement. Instead:

1. Audio and Feishu requests still stream normally.
2. The coordinator retains only the latest opaque response in memory.
3. The overlay shows that output will be inserted on release.
4. On non-empty final, the app revalidates the original PID and focused element.
5. If valid, `TextInputSimulator` performs one pasteboard/Cmd+V insertion.
6. If stale, the app posts no synthetic input, leaves the final text on the clipboard for manual
   recovery, and reports the reason.

This mode preserves compatibility without pretending to provide safe live replacement. Secure
fields are rejected rather than downgraded.

## 10. Coordinator and concurrency ownership

| Boundary | Owner | Rule |
|---|---|---|
| CGEventTap callbacks | private tap thread | marshal state changes; never run capture or AX work inline |
| capture session start/stop | existing `sessionQueue` | blocking `AVCaptureSession` work stays off main |
| PCM conversion/coalescing | audio/buffer serial queues | preserve order; never block capture on network |
| Feishu sequence/token state | `FeishuStreamingSession` actor | exactly one request chain per hold |
| UI/status/session generation | `MainViewModel @MainActor` | single coordinator verdict for every callback |
| AX destination and owned range | `CursorTextSession @MainActor` | all target writes serialized and verified |

The coordinator starts capture and stream setup without blocking the main actor. It consumes audio
and stream events in generation-bound tasks. Cleanup order is:

1. advance generation and mark the interaction terminal;
2. stop accepting cursor events;
3. stop recorder/ingress;
4. finish or best-effort cancel the Feishu stream as appropriate;
5. cancel consumer tasks and timers;
6. release transient destination, audio, token-session, and overlay state;
7. return hot-key and view-model state to idle or the bounded error state.

## 11. UI and settings

- The overlay continues to appear on the screen containing the mouse pointer.
- Listening state remains visually distinct from sealing/finalizing state.
- Transcript content never appears in the overlay, menu bar, logs, notifications, or accessibility
  labels owned by FeishuSpeech.
- `playSound` may retain start/final feedback but must not play once per partial.
- `autoInsert=true` enables live cursor writing and final-only target fallback.
- `autoInsert=false` retains its existing no-insertion meaning. Redefining it is outside issue #25.
- A target capability warning is per interaction; it does not silently change the saved setting.

## 12. Privacy, security, and diagnostics

Allowed diagnostic fields:

- typed lifecycle/capability/failure enum;
- generation and monotonic session number;
- packet action, sequence number, byte count, and bounded-queue occupancy;
- booleans such as `usedFinalOnlyFallback` and `destinationStillValid`.

Forbidden diagnostic fields:

- partial, final, provisional, selected, or clipboard text;
- PCM or encoded audio;
- App ID, App Secret, bearer token, stream ID, URL body, or raw backend message;
- focused-control value, application/window title, document name, or clipboard snapshot.

No cursor destination survives the process lifetime or is persisted to UserDefaults.

## 13. Implementation slices for a later issue

1. **Contract seams and fakes**
   - Define typed stream events/failures, audio-ingress configuration, and an Accessibility client
     seam. Add no behavior until tests own these contracts.
2. **Bounded streaming recorder**
   - Coalesce converted PCM to fixed elements, expose a byte-bounded async stream, and prove stop,
     tail, overflow, interruption, and cleanup behavior.
3. **Feishu streaming actor**
   - Add request models, stream ID generation, strict sequencing, first-packet token refresh, finish,
     bounded abort, and sanitized errors.
4. **Cursor text session**
   - Add capability probe, captured destination, replace/read-back loop, invalidation, final commit,
     and final-only fallback policy behind a fake AX client.
5. **Coordinator/state migration**
   - Replace the whole-file production path with streaming/sealing tasks and generation-owned
     cleanup. Keep legacy code only where an explicit compatibility test still requires it.
6. **UI/settings docking**
   - Add status-only listening/sealing/fallback feedback and preserve current settings semantics.
7. **Live compatibility gate**
   - Run credential-bearing Feishu and cross-application Accessibility UAT before declaring general
     availability.

Each implementation slice should preserve test/production custody separation required by
`CLAUDE.md`.

## 14. Test blueprint

### Transport

- action/sequence order for one packet, many packets, release, max duration, and cancel;
- no parallel requests;
- first-packet token refresh reuses action/sequence exactly once;
- no retry or whole-file fallback after first acceptance;
- finish/cancel idempotence and bounded abort;
- empty, malformed, non-200, backend-error, timeout, and cancellation responses are sanitized.

### Audio

- production conversion remains 16 kHz mono Int16 at 32,000 bytes/s;
- arbitrary callback sizes coalesce into ordered 6,400-byte elements;
- the 60-second bound is 1,920,000 bytes / 300 elements;
- stop flushes no more than one tail;
- an established short tail pads to 3,200 bytes; a stream with no first packet cancels locally;
- overflow fails explicitly without drop, replay, or reorder;
- interruption, device loss, conversion exhaustion, reset, and deinit close all continuations.

### Cursor writer with fake AX client

- collapsed cursor and non-empty initial selection;
- first insert, duplicate no-op, longer/shorter/revised replacement, and non-empty final;
- emoji, combining marks, CJK, right-to-left text, and newline content using returned AX ranges;
- frontmost PID, focused element, caret, selection, generation, and owned-text mismatch;
- element invalidation and `kAXErrorCannotComplete` before/after mutation;
- empty final and stream failure preserve last verified partial;
- secure field rejection and unsupported target final-only selection;
- late partial/final after commit, invalidation, reset, or new generation writes nothing.

### Coordinator

- state order `idle -> pending -> streaming -> sealing -> idle`;
- release and 60-second cap race emits one finish;
- new Fn press during sealing is ignored;
- sleep/wake and manual reset invalidate before cleanup;
- capture or stream failure cannot leave mic, overlay, writer, or hot-key state active;
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

Issue #25 is complete when this design, D-25-01, architecture docking, and API docking agree and no
production or test source has changed. Implementation requires a separate issue with RED-first
tests, focused suites, full build/test/lint validation, and live microphone/target-application UAT.

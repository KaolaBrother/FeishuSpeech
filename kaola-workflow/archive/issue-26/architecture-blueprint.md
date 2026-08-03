# Issue #26 production implementation blueprint

Date: 2026-08-03

Implementation worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`

Branch: `workflow/issue-26`

Contract authority: `docs/decisions/D-25-01.md` and `docs/streaming-speech-design.md`

## 1. Outcome and hard boundaries

Issue #26 replaces the production whole-file interaction with one generation-bound streaming
interaction:

```text
idle -> pending -> streaming(session identity) -> sealing(same identity) -> idle | error
```

One accepted hold owns one `AudioRecorder` capture, one byte-bounded PCM ingress, one strictly
serial `FeishuStreamingSession`, and, when safe and enabled, one `CursorTextSession` bound to the
original Accessibility element. The target application remains the only transcript surface. The
menu and overlay show lifecycle/capability status only.

This implementation must not:

- change a `public` Swift API, the deployment target, build settings, entitlements, dependencies,
  credential storage, or the meaning of `autoInsert`;
- route an established stream through `recognizeSpeech`, `withRetry`, `file_recognize`, or any
  whole-audio fallback;
- write a partial with pasteboard/key events, query a new destination for a late result, synthesize
  deletion/navigation/Return, or roll back text after ownership becomes uncertain;
- log transcript text, PCM/Base64 audio, tokens/credentials, stream IDs, request/response bodies,
  backend messages, target contents, app/window titles, or clipboard payloads;
- edit `FeishuSpeech.xcodeproj/project.pbxproj` merely to add source files. Both source roots are
  `PBXFileSystemSynchronizedRootGroup`s and new files join their targets automatically.

The current project deployment setting is `26.2`, despite the documentation describing macOS 13+.
Issue #26 must not resolve that discrepancy. If an implementation cannot compile without changing
the deployment target, stop and escalate that public compatibility decision.

## 2. Current RED and success criteria

Four test-owned, untracked RED files are present in the claimed worktree:

- `FeishuSpeechTests/StreamingAudioIngressTests.swift`
- `FeishuSpeechTests/FeishuStreamingSessionTests.swift`
- `FeishuSpeechTests/CursorTextSessionTests.swift`
- `FeishuSpeechTests/StreamingCoordinatorStateTests.swift`

They are target members without a project-file edit. A focused `xcodebuild` attempted on 2026-08-03
compiled the whole synchronized test target and failed on the expected missing issue-26 symbols,
starting with `StreamingSessionIdentity`, streaming/sealing state, and their test hooks. Therefore
`-only-testing` does not isolate compilation from the other RED files. All declaration surfaces
must exist before any focused suite can become independently runnable; do not remove/exclude tests
or edit project membership to bypass that compile barrier.

Implementation success requires all of the following:

1. The four test-owned RED suites compile and pass without weakening their assertions.
2. Existing hot-key, coordinator, API, permissions, settings, and capture-failure suites are
   migrated where the accepted state contract intentionally supersedes whole-file behavior, then
   pass.
3. Converted PCM is delivered in capture order through the byte-derived bound, with explicit
   overflow and exactly one terminal result.
4. Streaming requests are one-at-a-time even under overlapping actor calls; only the first known
   invalid-token attempt may refresh/retry, using the same first action/sequence as required by the
   accepted local contract and RED test.
5. Live AX replacement always targets the captured element and proves ownership before and after
   every write; final-only output posts at most one paste and only after same-target revalidation.
6. Release and the 60-second timer race to one sealing transition and one finish. Reset, sleep,
   wake, capture failure, stream failure, and teardown invalidate identity before cleanup.
7. No transcript reaches FeishuSpeech UI or diagnostics, and `autoInsert=false` causes no target or
   pasteboard mutation.
8. Debug build, complete test target, and SwiftLint pass. Credential-bearing transport and
   cross-application AX UAT must pass before claiming general availability.

## 3. Chosen component and file layout

The following is the smallest coherent split that keeps transport, audio, AX, and UI ownership
separate while honoring the names fixed by the RED tests.

### New production files

| File | Sole responsibility |
|---|---|
| `FeishuSpeech/Models/StreamingSpeech.swift` | `StreamingSessionIdentity`, `StreamingFailure`, `StreamingRecognitionEvent`, and the internal `SpeechStreamingSession` protocol. All value types are `nonisolated`, `Equatable`, and `Sendable` where valid. |
| `FeishuSpeech/Services/ByteBoundedAudioIngress.swift` | `AudioIngressConfiguration`, `AudioIngressError`, and the single-consumer `ByteBoundedAudioIngress`. It knows packet/tail/queue bytes, not AVFoundation or Feishu. |
| `FeishuSpeech/Services/FeishuStreamingSession.swift` | Private wire models/request encoding plus the exact-serial actor required by the RED transport contract. |
| `FeishuSpeech/Services/AccessibilityClient.swift` | `CursorTextRange`, `CursorDestinationToken`, capability/rejection types, the testable `AccessibilityClient` seam, and the production macOS AX adapter. |
| `FeishuSpeech/Services/CursorTextSession.swift` | `CursorTextSession` state/ownership algorithm and the pure `FinalOnlyFallbackDecision`; no audio, HTTP, pasteboard, or fresh-target routing. |

Every new file must declare the required private subsystem logger. Pure value files must not use
that as permission to log associated strings.

### Existing production files to modify

| File | Required change |
|---|---|
| `FeishuSpeech/Services/AudioRecorder.swift` | Keep AVCaptureSession and conversion ownership; route converted PCM to an active ingress in streaming mode; add ordered async seal/cancel integration; map ingress overflow/capture errors to typed terminal cleanup. Preserve legacy whole-buffer methods only for compatibility tests, not as the production fallback. |
| `FeishuSpeech/Services/FeishuAPIService.swift` | Add an internal streaming-session factory and no-retry raw request/token-refresh closures. Scrub existing sensitive whole-file logs/errors. Do not make `getAccessToken` or raw HTTP generally public. |
| `FeishuSpeech/Services/HotKeyState.swift` | Add identity-bound `.streaming(sessionID:)` and `.sealing(sessionID:)`; retire production use of `.recording`/`.transcribing`. |
| `FeishuSpeech/Services/HotKeyService.swift` | Allocate an identity only when the 0.3-second gate succeeds; release/cap transition that identity to sealing once; reject new presses in sealing; clear active identity before reset/error/stop/wake cleanup. |
| `FeishuSpeech/Models/RecordingState.swift` | Replace the whole-file presentation path with non-transcript `.streaming`, `.finalOnly`, and `.sealing` states plus existing idle/error behavior. |
| `FeishuSpeech/Services/TextInputSimulator.swift` | Add copy-only manual recovery and an injectable internal final-output adapter. Live partials never call this file. |
| `FeishuSpeech/ViewModels/MainViewModel.swift` | Become the authoritative generation/lifecycle coordinator; own the interaction bundle, stream consumer, final-only latest value, sealing guard, and invalidation-before-cleanup order. |
| `FeishuSpeech/Views/RecordingOverlayView.swift` | Render a passed status model, never transcript content. |
| `FeishuSpeech/Controllers/OverlayWindowController.swift` | Accept/update status while preserving its independent animation-generation race guard. |

`MenuBarView.swift` and `FeishuSpeechApp.swift` already render `RecordingState` generically and need
no transcript surface or mandatory edit. `PermissionManager.swift` remains the app-wide permission
poller; the per-interaction secure/focused-element decision belongs to the AX adapter. Keep
`SpeechResult.swift`, `AppSettings.swift`, `AppDelegate.swift`, entitlements, and the Xcode project
unchanged unless a verified compiler error proves a narrowly scoped need. New streaming wire models
belong in `FeishuStreamingSession.swift`, not in the legacy whole-file model file.

## 4. Exact internal contracts

These are internal/testable contracts, not new public API.

### Shared streaming values

`StreamingSessionIdentity` contains the monotonically increasing `UInt64 generation` fixed by the
RED coordinator test. `StreamingRecognitionEvent` has exactly the test-owned cases
`.partial(String)`, `.final(String)`, `.cancelled`, and `.failed(StreamingFailure)`.

`StreamingFailure` must expose only typed/sanitized cases, sufficient for `.timeout`, `.network`,
invalid response, authentication, safe HTTP/business codes, cancellation, and invalid state. It
must not carry raw bodies, backend `msg`, URLs with secrets, tokens, stream IDs, or transcript
strings. `localizedDescription` and `String(reflecting:)` must remain safe.

The internal `SpeechStreamingSession: Sendable` contract is:

```swift
func sendAudioPacket(_ pcm16: Data) async throws -> StreamingRecognitionEvent
func finish() async throws -> StreamingRecognitionEvent
func cancel() async
```

The concrete actor conforms; the coordinator depends on this protocol so tests can inject a fake.
A second internal provider seam creates a session from App ID/secret. The default provider is
`FeishuAPIService.shared`; test providers must not need Keychain, network, or the singleton actor.

### Audio ingress

The RED tests fix these names and callable shapes:

- `AudioIngressConfiguration(packetByteCount:minimumTailByteCount:maximumBufferedByteCount:)`
  and `bufferedElementCapacity`;
- `ByteBoundedAudioIngress(configuration:)`, public-in-module `stream`, synchronous `append`,
  idempotent `finish(streamEstablished:)`, and `fail`;
- `AudioIngressError.ingressOverflow` and `.captureFailed`.

Add `.cancelled` only as the typed lifecycle close reason. Do not rename or wrap the test-owned
surface. The production configuration is 6,400 / 3,200 / 1,920,000 bytes and therefore 300
buffered elements.

Use an `AsyncThrowingStream<Data, Error>` with buffering capacity derived from bytes, not callback
count. The normal yielded element is always exactly `packetByteCount`; the only smaller element is
the one final tail. A lock or private serial state boundary protects coalescing bytes, terminal
state, and continuation access. `append` returns an optional typed error (marked discardable) so
`AudioRecorder` can stop capture immediately on overflow; existing tests may ignore the return.
On the first `.dropped` yield, finish with `.ingressOverflow`, preserve all previously accepted
elements in order, and ignore every later append/finish/fail. The first terminal call is
authoritative.

`finish(streamEstablished: true)` emits at most one non-empty tail, pads only tails below 3,200
bytes with zero PCM, and then completes. A tail at or above the minimum is unchanged.
`finish(streamEstablished: false)` discards a sub-packet local tail and completes without a network
element. `onTermination` releases the continuation and prevents further buffering.

### AudioRecorder attachment

Do not introduce a sibling recorder or move AVFoundation ownership. Add explicit streaming-mode
entry/exit methods to the existing injectable `AudioRecorder`, sharing its current configuration
and conversion implementation:

- start takes a `ByteBoundedAudioIngress`, calls existing cleanup before attaching the new ingress,
  configures capture, and retains the current completion behavior;
- every converted Int16 `Data` block is appended on the existing serial `bufferQueue`; legacy
  `audioBuffer` receives data only in legacy mode;
- normal async stop runs `stopRunning`/session teardown on `sessionQueue`, crosses an `audioQueue`
  barrier so no capture callback remains, then seals the ingress on `bufferQueue` exactly once;
- force cleanup/reset fails an active ingress with `.cancelled` before releasing it; capture,
  device, interruption, or conversion exhaustion fails it with `.captureFailed`;
- synchronous overflow detection publishes a dedicated recorder overflow failure so the
  coordinator does not wait to drain 300 queued packets before stopping the microphone.

Keep `startRunning` and `stopRunning` off the main actor. Do not block the audio callback on HTTP.
Reorder failure publication if needed so the MainViewModel observer can invalidate the active
identity before its cleanup path; cleanup remains idempotent and still happens when no observer is
installed.

The boolean passed to ingress finish is based on whether this ingress emitted at least one full
first-packet candidate, not on speculative target text. If the first HTTP request later fails, the
consumer stops and no tail is replayed. If no full packet was emitted, the coordinator performs a
local cancel and sends neither action 2 nor action 3.

### Feishu token and HTTP seam

`FeishuAPIService` remains the only production owner of cached tenant tokens and URLSession HTTP.
Add an internal `makeStreamingSession(appId:appSecret:)` factory that:

1. checks current network availability;
2. obtains the initial token through the existing cache/fetch logic once, without `withRetry`;
3. constructs `FeishuStreamingSession(initialToken:refreshToken:requestSender:)`;
4. injects a refresh closure that clears the cached token and performs one fresh auth request;
5. injects a raw `URLRequest -> DirectHTTPResponse` sender that checks network state and calls the
   existing URLSession primitive exactly once.

Neither closure may call `recognizeSpeech`, `performRecognition`, `withRetry`, or
`sendSpeechRequest`. `recognizeSpeech` may remain for compatibility/tests but must not be referenced
by the new coordinator. Reset cancels the per-hold session first and then clears shared token state;
an already-created session owns its token snapshot.

### Exact-serial FeishuStreamingSession

The actor owns exactly these mutable facts: stream ID, next sequence (initially 0), token,
first-packet acceptance, first-token-refresh-used, terminal intent, terminal task/result,
current HTTP task, completion, and an actor-owned FIFO request gate.

Actor isolation alone is insufficient because an actor re-enters while awaiting HTTP. Implement an
explicit gate (`requestInFlight` plus FIFO checked continuations, or an equivalent actor-owned task
chain). Encoding/state selection happens only after acquiring the gate; the gate is released in a
single `defer`. Overlapping `sendAudioPacket` calls therefore produce at most one active sender and
observe state in accepted order.

Request behavior:

| Operation | Action | Sequence/state rule |
|---|---:|---|
| first non-empty packet | 1 | sequence 0; mark accepted and advance only after a successful code-0 response |
| later non-empty packet | 0 | current sequence; advance only after successful acceptance |
| first normal finish after acceptance | 2 | empty Base64 audio string; next sequence; emit/caches one `.final` |
| first cancel after acceptance | 3 | empty Base64 audio string; next sequence; bounded best effort; cache cancelled |
| finish/cancel before acceptance | none | complete locally; no network terminal action |

Generate the default stream ID from lowercase ASCII letters, digits, and underscore at exactly 16
characters. Encode the documented endpoint and JSON keys exactly and set
`Content-Type: application/json; charset=utf-8`. Do not log the ID, bearer header, or body.

The current RED parser requires terminal requests to contain `speech.speech` as an empty string,
not omit the field. The vendor evidence says the accepted action-2/action-3 empty-audio shape is
still a runtime unknown; retain this RED-owned encoding and put it behind credential-bearing UAT.
Similarly, current RED response fixtures deliberately do not echo later sequence/stream identity,
so response-ID matching cannot be added in this issue without a test-custodian contract change.
Decode the fields but do not reject those fixtures.

Only a known invalid credential before first acceptance may retry. The RED suite fixes Feishu
business code `9_999_1663`; HTTP 401 may share that classifier, but generic HTTP 400 must not be
treated as a proven token error. Refresh at most once and retry the same prepared action-1 body,
stream ID, and sequence 0. Every other HTTP, business, decoding, timeout, or network failure is
terminal and has no replay. This same-sequence retry is an accepted local policy, not a vendor
guarantee, and remains a UAT gate.

The first terminal intent wins. Repeated `finish()` returns the cached final event and never sends
another action 2. Repeated `cancel()` never sends another action 3. Cancellation may cancel the
stored current HTTP task before waiting for the serial gate; after an action 2 may have been
emitted, do not send action 3. Bound action-3 work with a short local deadline and swallow only its
sanitized failure. Never allow a terminal request to overlap the preceding packet.

### AccessibilityClient and CursorTextSession ownership

`AccessibilityClient` and its production adapter are `@MainActor`; `AXUIElement` and destination
tokens never cross an actor boundary or persist. The protocol surface must match the fake already
owned by `CursorTextSessionTests`: capture capability, same-destination validation, selected range
read, string-for-range read, selected range write, selected text write, and the test-observation
`rollback` method. Production `rollback` is a no-op; `CursorTextSession` must never call it.

The production adapter owns all raw AX calls. On capture it:

1. verifies AX trust and rejects Secure Event Input;
2. queries the focused element once, gets its PID, and proves that PID is frontmost;
3. rejects a secure/protected text role or any case where non-secure status cannot be established;
4. captures the selected range when available;
5. returns `.live(token)` only when selected text and selected range are settable and
   `kAXStringForRangeParameterizedAttribute` is available;
6. returns `.finalOnly(token)` for a non-secure editable destination lacking safe replacement;
7. returns `.rejected(.secureTarget)` rather than downgrading a secure target.

`isDestinationCurrent` rechecks frontmost PID and focused-element CF identity against the captured
token. It never returns a newly queried element for writing. AX errors are mapped to typed local
errors without element contents, process/app names, or titles.

`CursorTextSession` alone owns the live writer state. It is initialized with one generation and
client, and `begin()` is idempotent. The state names required by tests include armed/final-only and
terminal `.provisional(range:text:)`, `.invalid`, `.committed`, and `.preserved`.

For the first distinct non-contentless partial, verify generation, same destination, and original
selection; select the original range; write the entire opaque value; read a collapsed caret; derive
the owned length as `returnedCaret.location - originalLocation`; read that range; and establish
ownership only after exact text equality. For later partials/final, additionally require a collapsed
caret at the current owned end and exact previous owned text, then replace the whole range and
repeat post-write verification. Never derive range length from UTF-8, `String.count`, scalar count,
or even UTF-16 count; the fake's arbitrary returned lengths are authoritative.

A duplicate partial is a no-op. A callback for a different generation is silently discarded and
does not invalidate the current generation. Destination/caret/owned-text mismatch invalidates the
session permanently. A post-mutation AX failure also invalidates without rollback. Empty final or
stream failure changes a live session to preserved, including failure before a first write (zero
mutation). Non-empty verified final commits and leaves the AX-returned collapsed caret. Cancel,
reset, or explicit invalidation is terminal, and every late event becomes a no-op.

### Final-only output

`CursorTextSession` does not paste. MainViewModel stores the final-only token and only the latest
opaque response for the current generation. On a normal non-contentless final it calls the pure
`FinalOnlyFallbackDecision.evaluate` contract already fixed by tests:

- auto-insert + non-secure + current target -> `.insertOnce`;
- auto-insert + non-secure + stale target -> `.copyForManualRecovery`;
- auto-insert disabled or contentless final -> `.noInsertion`;
- secure target -> `.rejectSecureTarget`.

The current target check comes from the captured token's client. `.insertOnce` calls the existing
pasteboard/Cmd+V operation once. `.copyForManualRecovery` calls a new method that writes the final
text to the pasteboard without posting any CGEvent and does not restore the old clipboard; feedback
states only that recovery text was copied. Secure targets start no capture or network work.

Classify whitespace-only output as contentless for compatibility with existing empty-result tests,
but never trim or normalize a non-contentless value before AX replacement, final paste, or recovery
copy. `autoInsert=false` may retain the latest value transiently for lifecycle decisions but causes
no AX, pasteboard, or synthetic-input call.

### MainViewModel generation and sealing

`HotKeyService` allocates a monotonically increasing `StreamingSessionIdentity` only when its
0.3-second gate succeeds; it alone knows when a hold became accepted. `MainViewModel @MainActor`
becomes the authoritative owner as soon as it observes `.streaming(identity)`: it records that
identity, and every audio, HTTP, AX, timer, overlay, and cleanup callback captures and checks it.
This separates identity allocation from lifecycle authority.

`HotKeyService` retains `activeSessionIdentity` while streaming/sealing. Its callback predicate is
true only for that identity. `resetToIdle`, `setError`, stop monitoring, wake recovery, and pending
cancellation clear it before publishing terminal/idle state. `.streaming` is active and visible;
`.sealing` is not active (so a successor cannot start) but remains overlay-visible. Fn release and
`forceSealing()` transition only `.streaming(id) -> .sealing(id)`; later release/cap calls are
no-ops. The existing max timer calls `forceSealing`, not `forceTranscribing`.

MainViewModel stores one interaction bundle: identity, ingress, optional streaming session,
cursor capability/session, latest final-only value, consumer task, seal-started flag, and whether a
full packet was emitted. Startup ordering is:

1. accept only the currently registered hot-key identity;
2. run `CursorTextSession.begin()` before audio or network, even when `autoInsert=false`, so secure
   targets are rejected before capture;
3. choose live/final-only/no-insertion mode without changing the saved preference;
4. create ingress and start capture;
5. create the streaming session asynchronously and consume ingress packets serially;
6. marshal each typed event back to MainActor and recheck identity before writer/status work.

On release/cap, one sealing handler stops the timer, publishes `.sealing`, updates rather than hides
the overlay, plays stop sound at most once, and awaits the recorder's ordered stop/barrier/seal. The
single consumer continues draining accepted packets and the optional tail. When the ingress ends,
it sends one finish only if at least one packet was accepted; otherwise it cancels locally. Final
handling commits/preserves live output or executes the final-only decision, then invalidates the
active identity before releasing transient objects and returning both coordinator and hot-key to
idle.

All abnormal paths use one terminal helper. It first clears/invalidates the active identity and
cursor ownership, then closes recorder/ingress, best-effort cancels transport, cancels consumer and
timer tasks, clears fallback text, updates/hides overlay, and finally publishes idle or bounded
error. Stream failure is first delivered to the cursor session as `.failed` so a verified visible
partial becomes preserved; lifecycle cancellation uses `invalidate()` and never deletes text.
Guard against cancelling/awaiting the currently executing consumer task; schedule or split cleanup
so it cannot await itself.

Manual reset, sleep, wake, permission loss, app cleanup, capture failure, stream failure, and cursor
startup/write failure all use this helper. Sleep/wake still reset `FeishuAPIService`, and wake still
recovers the hot-key tap. Consecutive-failure reset may remain, but it cancels the current stream
before clearing shared API state and never retries that audio.

### Status-only UI and diagnostics

`RecordingState` provides at least idle, streaming/listening, final-only listening, sealing, and
error. Exact Chinese copy may be adjusted during UI review, but every label is a fixed status phrase
with no associated transcript. `RecordingOverlayView` receives only this status; Accessibility
labels in FeishuSpeech must not contain recognized text. `playSound` remains start/stop only and
never fires per partial.

Keep `OverlayWindowController`'s existing animation-generation integer independent of the speech
identity. `show(status:)` advances the animation generation and positions the panel on the mouse
screen; `update(status:)` changes the root status without advancing/recreating the speech session;
`hide()` keeps its stale-completion guard.

Allowed logs: typed lifecycle/capability/failure, speech generation, action, sequence, byte count,
and bounded queue occupancy. Remove the existing whole-file transcript/file-ID/raw-body/backend-msg
log interpolation in `MainViewModel` and `FeishuAPIService`; legacy error descriptions must no
longer reflect raw backend messages. Do not use privacy annotations as a substitute for omitting
sensitive values.

## 5. Dependency-safe TDD and implementation order

Tests remain in separate custody. Production implementers may read and run them but must not edit
them. Because all synchronized test files compile for every focused run, the four production owners
must first establish their declaration-complete surfaces; only then can focused behavior suites be
used independently.

### Task 0 — test-custodian contract completion (test owner only)

Files owned: all `FeishuSpeechTests/*.swift` changes for issue #26.

- Preserve the four current RED files and their exact signatures.
- Update old `.recording/.transcribing` assertions in `HotKeyServiceTests.swift` and
  `MainViewModelTests.swift` to the accepted identity-bound streaming/sealing contract; do not keep
  obsolete production behavior merely to satisfy stale tests.
- Add recorder/ingress integration coverage: converted-block order, normal barrier-before-tail,
  force-cancel closure, capture-failure closure, and overflow stopping capture.
- Extend coordinator coverage with injected stream provider/AX client/final-output router for:
  startup secure rejection before audio/network, live/final-only/autoInsert=false modes,
  release-vs-cap one finish, empty final, stale fallback copy-only, generation invalidation before
  reset/sleep/wake cleanup, and late event no-op.
- Add privacy assertions that injected secret transcript/backend/token/stream strings never enter
  typed errors, `status`, or `overlayMessage`.

This task is independent of production writes but must finish contract edits before implementers
adapt to any newly fixed signature.

### Task 1 — shared streaming values (contract implementer)

Owned file: new `FeishuSpeech/Models/StreamingSpeech.swift` only.

- Add identity, sanitized failure/event enums, session protocol, and provider protocol.
- Test: typed-event assertions in `FeishuStreamingSessionTests`; compile-only use by coordinator
  and cursor suites.

No other implementer edits this file. Tasks 2 and 4 may begin independently; tasks 3, 5, and 6
consume it.

### Task 2 — bounded ingress and recorder integration (audio implementer)

Owned files:

- new `FeishuSpeech/Services/ByteBoundedAudioIngress.swift`
- `FeishuSpeech/Services/AudioRecorder.swift`

Order within the task:

1. implement pure coalescing/bound/terminal behavior;
2. pass `StreamingAudioIngressTests` after the global declaration barrier;
3. attach the ingress to converted PCM and implement ordered normal seal/abnormal close;
4. pass the test-custodian recorder integration suite and existing capture-failure tests.

This task is genuinely independent of HTTP, AX, hot-key, and UI work: it touches disjoint files and
exports only PCM elements/typed terminal state.

### Task 3 — exact-serial Feishu transport (transport implementer)

Owned files:

- new `FeishuSpeech/Services/FeishuStreamingSession.swift`
- `FeishuSpeech/Services/FeishuAPIService.swift`

Order within the task:

1. implement wire models, request gate, action/sequence/terminal state, and sanitized failures;
2. pass `FeishuStreamingSessionTests` after the global declaration barrier;
3. add the API-service factory/token/raw-request adapters without a retry path;
4. add/pass provider integration tests in `FeishuAPIServiceTests` and preserve legacy API tests;
5. remove sensitive legacy logging/error propagation in the owned file.

Depends only on Task 1's values. It is otherwise independent of audio and AX and has an exclusive
write set.

### Task 4 — Accessibility adapter and cursor ownership (cursor implementer)

Owned files:

- new `FeishuSpeech/Services/AccessibilityClient.swift`
- new `FeishuSpeech/Services/CursorTextSession.swift`
- `FeishuSpeech/Services/TextInputSimulator.swift`

Order within the task:

1. implement AX value/range conversion and capability capture behind the protocol;
2. implement the pure session state machine against that protocol;
3. pass `CursorTextSessionTests` after Task 1 is present;
4. implement final-only insert/copy adapters without giving the cursor session pasteboard access.

Depends on Task 1 for event/failure values. It is independent of audio/HTTP/hot-key work and owns
all target mutation primitives.

### Task 5 — identity-bound hot-key and presentation states (state implementer)

Owned files:

- `FeishuSpeech/Services/HotKeyState.swift`
- `FeishuSpeech/Services/HotKeyService.swift`
- `FeishuSpeech/Models/RecordingState.swift`

- Implement identity allocation, callback validity, streaming/sealing transitions, and reset-first
  invalidation.
- Replace the max-duration entry point with idempotent `forceSealing`.
- Preserve the private event-tap thread, main-thread marshaling, pending cancellation, wake/tap
  recovery, and subscription behavior.
- Tests: `StreamingCoordinatorStateTests` hot-key/status cases plus migrated
  `HotKeyServiceTests`.

Depends on Task 1's identity type. It is independent of Tasks 2-4 and touches none of their files.

### Declaration barrier

Tasks 1-5 may be produced concurrently only with the ownership above. Do not interpret a focused
suite's compile failure as a slice failure until every new referenced declaration exists, because
Xcode compiles all synchronized tests. Once the barrier is complete, run the four focused suites
and route behavior failures to the test custodian; route compiler/concurrency/tooling failures to
the build-error resolver. Do not delete a RED file or add a membership exception.

### Task 6 — MainViewModel integration (single integrator)

Owned file: `FeishuSpeech/ViewModels/MainViewModel.swift` only.

Depends on completed Tasks 2-5. Replace the production whole-file path with the interaction bundle,
secure-first startup, serial consumer, generation gates, one sealing path, final/live/fallback
routing, and invalidation-first cleanup. Add only constructor defaults needed to inject the existing
audio recorder plus stream provider, AX client, and final-output adapter. Preserve existing default
call sites and wake-recovery injection.

Tests: extended `StreamingCoordinatorStateTests`, migrated coordinator sections of
`MainViewModelTests`, empty-result feedback, sleep/wake, capture-failure, and monitoring subscription
regressions. No other implementer edits MainViewModel, because it is the convergence point.

### Task 7 — status-only overlay docking (UI implementer)

Owned files:

- `FeishuSpeech/Views/RecordingOverlayView.swift`
- `FeishuSpeech/Controllers/OverlayWindowController.swift`

Depends on Task 5's `RecordingState` shape and must agree with Task 6's calls. It may run in parallel
with Task 6 after that interface is frozen because the files are disjoint. Test fixed status values
and preserve the animation-generation behavior; perform visual UAT for listening, final-only, and
sealing on multiple displays. Do not add transcript-bound state, accessibility labels, or a preview.

### Task 8 — convergence and privacy audit (main session)

- Review every write against this ownership map; resolve no clean/disjoint files through a
  synthesizer unless a real merge conflict exists.
- Search all logger calls in modified production files and remove sensitive interpolation.
- Confirm no production reference from MainViewModel to `recognizeSpeech`/`file_recognize` remains.
- Confirm `project.pbxproj`, deployment target, dependencies, entitlements, settings meaning, and
  docs were not changed by implementation.
- Run focused, regression, full, lint, and UAT gates below.

## 6. Validation commands

Run from the claimed worktree.

### Focused RED/green order

```bash
cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/StreamingAudioIngressTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/FeishuStreamingSessionTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/CursorTextSessionTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/StreamingCoordinatorStateTests test
```

Then run the integration/regression suites:

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/HotKeyServiceTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/MainViewModelTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/FeishuAPIServiceTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/PermissionManagerTests test
```

Use the exact test-custodian suite name for new recorder/coordinator integration tests. Do not count
`AudioRecorderRecoveryTests.swift`; it remains an intentional pre-existing target exclusion.

### Static architecture/privacy checks

```bash
rg -n 'recognizeSpeech|file_recognize|withRetry' FeishuSpeech/ViewModels/MainViewModel.swift
rg -n 'Recognition result:|Recognition successful:|Speech API error response:|Auth failed:|Sending speech request with fileId' FeishuSpeech
rg -n 'logger\.|os_log' \
  FeishuSpeech/Models/StreamingSpeech.swift \
  FeishuSpeech/Services/ByteBoundedAudioIngress.swift \
  FeishuSpeech/Services/FeishuStreamingSession.swift \
  FeishuSpeech/Services/AccessibilityClient.swift \
  FeishuSpeech/Services/CursorTextSession.swift \
  FeishuSpeech/Services/AudioRecorder.swift \
  FeishuSpeech/Services/FeishuAPIService.swift \
  FeishuSpeech/ViewModels/MainViewModel.swift
git diff --exit-code -- FeishuSpeech.xcodeproj/project.pbxproj
git diff --check
```

The first two `rg` commands should return no production whole-file call and no known sensitive log
patterns respectively. Review every hit from the logger inventory manually; a zero-hit rule is not
possible because typed lifecycle logging is required.

### Repository gates

```bash
xcodebuild -scheme FeishuSpeech -configuration Debug build
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test
swiftlint
git status --short --branch
```

### Credential-bearing and cross-application UAT

Use synthetic/non-private speech and record only semantic outcomes, never transcripts or raw
responses.

- Verify action-2/action-3 empty-audio JSON is accepted.
- Verify 16 kHz mono signed little-endian Int16 PCM, 6,400-byte packets, and padded/unpadded final
  tails.
- Observe whether intermediate responses are empty/revised/cumulative without making that shape a
  correctness dependency.
- Verify the non-empty action-2 response behavior and first invalid-token same-sequence refresh.
- Verify timeout/network failure never replays an established packet and cancel is bounded.
- Exercise TextEdit, a native rich editor, Safari/Chrome, Electron, terminal controls, and a
  document editor with undo.
- Exercise secure fields/Secure Event Input, focus switch, caret move, user edit, target close,
  reset, sleep/wake, app termination, and a 60-second hold under normal/slow network.
- Verify final-only same-target paste once, stale-target copy-only, and `autoInsert=false` zero
  mutation.
- Verify overlay/menu/accessibility labels remain status-only on multiple displays.

Automated green without this UAT is sufficient for code integration evidence but not for a broad
compatibility/general-availability claim.

## 7. Risk, rollback, and failure routing

| Risk/failure | Required response |
|---|---|
| Ingress overload | Fail the current generation and stop capture. Do not drop the new/oldest packet silently, enlarge the bound, or retry audio. |
| Actor reentrancy creates parallel HTTP | Treat as a transport correctness failure; fix the explicit serial gate and rerun overlap/cancel tests. Do not rely on actor declaration alone. |
| First-token same-sequence retry rejected in live UAT | Keep the stream failed closed and return to the accepted design/user decision. Do not invent a new sequence/replay policy in implementation. |
| Action-2/action-3 empty body rejected | Preserve test/runtime evidence and escalate the wire-contract change; do not silently vary payloads per attempt. |
| AX target lacks safe capabilities | Use final-only mode. Do not weaken pre/post verification or substitute synthetic partial editing. |
| AX mismatch/failure after a write | Preserve uncertain visible text, invalidate permanently, and do not call rollback. |
| Stale final-only target | Post no CGEvent; copy once for manual recovery and show status-only feedback. |
| Reset/sleep/wake race | Identity invalidation wins before all cleanup. Late callbacks are no-ops; do not wait for them before invalidating. |
| Build/concurrency/isolation failure | Route to build-error resolver. Keep `@MainActor` UI/AX, actor transport, and existing capture queues; do not solve by changing deployment/build settings. |
| Behavioral/coverage failure | Route to the test custodian with the failing contract. Production implementers do not edit tests. |
| UAT incompatibility in one app | Mark that target unsupported/final-only and the availability verdict PARTIAL. Do not advertise broad support or weaken ownership checks. |
| New files missing from a target | First verify synchronized-root placement and exceptions. Do not hand-edit PBX membership unless that mechanism is proven insufficient and separately approved. |

Rollback is interaction-local: invalidate the generation, stop capture, terminate ingress, cancel
the stream best-effort, release AX ownership, and preserve any already verified visible partial.
There is no destructive text rollback and no whole-file replay. At repository level, the new files
and the listed surgical edits form one feature unit; if integration cannot pass, leave the
production whole-file code reachable only as unselected compatibility code while the issue remains
unfinished—never silently route an established streaming hold back to it.

## 8. Explicit decisions and remaining evidence gates

This blueprint decides implementation mechanics that were previously open:

- evolve the existing `AudioRecorder`; add a separate pure ingress rather than a sibling recorder;
- inject token-refresh/raw-HTTP closures into `FeishuStreamingSession` through an API-service
  factory, so streaming cannot inherit whole-file retries;
- keep raw AX work in one production adapter, range ownership in `CursorTextSession`, and final-only
  paste/copy execution in MainViewModel through an output adapter;
- allocate accepted-hold identity in HotKeyService and give MainViewModel authoritative lifecycle
  gating/cleanup ownership;
- rely on synchronized groups and make no project-file/deployment/dependency change.

The blueprint does not decide or claim vendor behavior that remains unverified: exact terminal
payload acceptance, PCM encoding guarantees, intermediate hypothesis shape, action-2 completeness,
same-sequence token replay safety, or broad AX application compatibility. Those remain explicit UAT
gates. A contrary UAT result must update the accepted decision/tests before production behavior is
changed.

# Issue #26 repository exploration

Date: 2026-08-03  
Repository: `/Users/ylpromax5/Workspace/feishuspeech`  
Claimed implementation worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`  
Exploration baseline: commit `9fed83f` (`workflow/issue-26`, clean at initial inspection time)

## Scope and evidence boundary

This is a read-only map of the current repository. It does not select an implementation design beyond the already accepted D-25-01 contract. The only repository write made by this exploration is this promised deliverable.

Concurrent-work note: the implementation worktree was clean when exploration began. During final verification, two untracked test-owned artifacts appeared: `FeishuSpeechTests/StreamingAudioIngressTests.swift` and `FeishuSpeechTests/FeishuStreamingSessionTests.swift`. They were not created or modified by this explorer. This report maps them separately as concurrent RED contracts; all production facts remain the `9fed83f` baseline unless stated otherwise.

Issue #26 is locally represented only by the title `enhancement: implement cursor-bound streaming Feishu transcription`; the local roadmap record contains no additional acceptance text (`kaola-workflow/.roadmap/issue-26.md:1-5`, `kaola-workflow/ROADMAP.md:8-10`). The detailed behavior contract therefore comes from the accepted issue-#25 design artifacts:

- D-25-01 is accepted but explicitly design-only and names the affected boundaries as hot-key state, audio ingress, Feishu transport, coordinator, text insertion, overlay status, and lifecycle recovery (`docs/decisions/D-25-01.md:1-7`).
- The design says implementation belongs to a later issue and requires RED-first tests, focused suites, full build/test/lint validation, and live microphone/target-application UAT (`docs/streaming-speech-design.md:445-449`).

## Concise findings

1. The production path is still whole-file: `AudioRecorder` accumulates one `Data`, Fn release changes `.recording` to `.transcribing`, `MainViewModel` stops recording and launches `FeishuAPIService.recognizeSpeech`, and the final text is pasted to the then-current focus (`FeishuSpeech/Services/AudioRecorder.swift:36-50,148-159`; `FeishuSpeech/Services/HotKeyService.swift:317-330`; `FeishuSpeech/ViewModels/MainViewModel.swift:254-319`; `FeishuSpeech/Services/TextInputSimulator.swift:28-48`).
2. The accepted target is generation-bound streaming: 6,400-byte ordered PCM elements, a serial `FeishuStreamingSession` actor, and a captured `CursorTextSession` on the original AX element (`docs/architecture.md:11-24,26-41,46-67`). None of those production types exists yet.
3. The existing audio conversion boundary is reusable in location and format, but its ownership/overflow behavior is not the target behavior: converted 16 kHz mono Int16 is appended to one buffer, and overflow is logged then silently discarded (`FeishuSpeech/Services/AudioRecorder.swift:269-300,341-375`).
4. The API service already owns token caching and an injectable DEBUG HTTP sender, but the token getter and request construction are private inside a singleton actor; the current whole-file retry wraps authentication plus speech as a unit (`FeishuSpeech/Services/FeishuAPIService.swift:333-353,501-529,555-597,609-690`). A streaming session will need an explicit tested seam to reuse token/HTTP behavior without inheriting whole-file replay semantics; that seam is not specified by current source.
5. There is no AX destination abstraction or cursor ownership state. `PermissionManager` checks process trust and polls Secure Event Input, while `TextInputSimulator` is a static pasteboard/Cmd+V utility with no destination token or same-focus validation (`FeishuSpeech/Services/PermissionManager.swift:23-39,95-106`; `FeishuSpeech/Services/TextInputSimulator.swift:18-73`).
6. `MainViewModel` injects only `AudioRecorder` and a wake recoverer. Hot-key, API, permission, overlay, and text insertion are hard-coded singleton/static dependencies, which is a current test seam limitation for coordinator tests (`FeishuSpeech/ViewModels/MainViewModel.swift:28-33,52-65,293-305`).
7. Xcode uses file-system-synchronized root groups. New files under `FeishuSpeech/` and `FeishuSpeechTests/` normally join their respective targets automatically; only `Info.plist` and `AudioRecorderRecoveryTests.swift` are explicit membership exceptions (`FeishuSpeech.xcodeproj/project.pbxproj:14-48,88-133,200-214`).
8. Concurrent RED tests now name two concrete contracts that production does not yet provide: `AudioIngressConfiguration` / `ByteBoundedAudioIngress` / `AudioIngressError`, and `StreamingRecognitionEvent` / `FeishuStreamingSession`. Their untracked presence means the worktree is no longer clean even though tracked production remains unchanged (`FeishuSpeechTests/StreamingAudioIngressTests.swift:8-20,22-112`; `FeishuSpeechTests/FeishuStreamingSessionTests.swift:8-48`).

## Accepted target contract that constrains implementation

These are settled facts, not recommendations:

- Interaction state is `idle -> pending -> streaming -> sealing -> idle | error`; `pending` preserves the 0.3-second gate, and `sealing` rejects a new session (`docs/decisions/D-25-01.md:27-41`).
- Every accepted hold increments a generation used by audio callbacks, stream events, cursor writes, timers, overlay updates, and cleanup. Reset, sleep/wake, permission loss, manual reset, and terminal failure invalidate the generation before cancellation (`docs/streaming-speech-design.md:126-131`).
- Audio is 16 kHz mono signed Int16 PCM, normally coalesced into 6,400-byte elements. The 60-second bound is 1,920,000 bytes / 300 elements. Sustained overload fails the current stream rather than dropping/reordering (`docs/decisions/D-25-01.md:43-68`).
- A normal established-stream tail shorter than 3,200 bytes may be silence padded; no first packet means local cancellation without finish or abort (`docs/streaming-speech-design.md:154-178`).
- Feishu requests are strictly serial: first packet `action=1`, continuation `action=0`, finish exactly once with `action=2`, and active cancel best-effort at most once with `action=3`. Sequence begins at zero and advances monotonically (`docs/streaming-speech-design.md:181-214`).
- Only a known invalid token before first-packet acceptance may refresh and retry that same action/sequence once. An established stream has no packet replay, whole-audio retry, or `file_recognize` fallback (`docs/decisions/D-25-01.md:48-60`).
- Intermediate text is opaque replacement state, not an appendable delta (`docs/streaming-speech-design.md:43-48`).
- Live cursor output captures one original PID/focused AX element/selected range and uses pre/post verification. Accessibility-returned ranges, not Swift string counts, define the owned range (`docs/decisions/D-25-01.md:70-106`).
- Unsupported editable controls use a final-only stream path, with one existing paste path only after same-target revalidation. Secure Event Input and secure fields are rejected, not downgraded (`docs/decisions/D-25-01.md:120-131`).
- Final/failure semantics preserve the last verified visible partial when ownership becomes uncertain (`docs/decisions/D-25-01.md:108-118`).
- The overlay is status-only and `autoInsert=false` retains its existing no-insertion meaning (`docs/streaming-speech-design.md:334-343`).
- Logs must not contain transcript text, PCM, credentials/tokens, stream IDs, raw bodies/messages, focused-control contents, application/window titles, or clipboard payloads (`docs/streaming-speech-design.md:345-361`).

## Current production seams

### 1. Hot-key and presentation state

Current types:

- `HotKeyState`: `.idle`, `.pending(startTime:)`, `.recording`, `.transcribing`, `.cancelled`, `.error` (`FeishuSpeech/Services/HotKeyState.swift:18-24`). Only pending/recording are active, and only recording shows the overlay (`FeishuSpeech/Services/HotKeyState.swift:26-42`).
- `RecordingState`: `.idle`, `.recording`, `.transcribing`, `.error`, with fixed icon/color/text mappings (`FeishuSpeech/Models/RecordingState.swift:3-34`).

Current transition seam:

- Fn events originate on the private tap thread and are marshalled to main (`FeishuSpeech/Services/HotKeyService.swift:274-295`).
- An idle Fn press enters pending; the 0.3-second work item changes pending to recording (`FeishuSpeech/Services/HotKeyService.swift:298-315,390-410`).
- Early release cancels; recording release directly assigns `.transcribing`; releases in terminal/non-active states do nothing (`FeishuSpeech/Services/HotKeyService.swift:317-330`).
- The 60-second coordinator timer calls `forceTranscribing()`, which also assigns `.transcribing` from recording or pending (`FeishuSpeech/Services/HotKeyService.swift:360-372`; `FeishuSpeech/ViewModels/MainViewModel.swift:399-420`).

Affected existing files:

- `FeishuSpeech/Services/HotKeyState.swift`: target state names and active/overlay mappings.
- `FeishuSpeech/Services/HotKeyService.swift`: release and max-duration terminal transition behavior, and new-hold suppression while sealing.
- `FeishuSpeech/Models/RecordingState.swift`: listening/sealing/fallback status representation.
- `FeishuSpeech/Views/MenuBarView.swift`: currently renders only `RecordingState.text/color` and a static instruction (`FeishuSpeech/Views/MenuBarView.swift:35-52`).
- `FeishuSpeech/Views/RecordingOverlayView.swift` and `Controllers/OverlayWindowController.swift`: overlay content is currently a fixed listening message and `show()` has no status/model parameter (`FeishuSpeech/Views/RecordingOverlayView.swift:3-26`; `FeishuSpeech/Controllers/OverlayWindowController.swift:20-40,66-92`).

Test seams:

- `HotKeyServiceTests` directly exercises state values and DEBUG `forceState`, release, and `forceTranscribing` (`FeishuSpeechTests/HotKeyServiceTests.swift:23-123`).
- Coordinator duplicate-release/max-duration behavior is in `CoordinatorStateInterplayTests` (`FeishuSpeechTests/MainViewModelTests.swift:280-350`).

### 2. Audio capture, conversion, buffering, and failure

Current ownership:

- `AudioRecorder` owns `AVCaptureSession`, `AVCaptureAudioDataOutput`, one complete `audioBuffer`, serial `audioQueue`, serial `bufferQueue`, and serial `sessionQueue` (`FeishuSpeech/Services/AudioRecorder.swift:32-51`).
- `startRecording()` first calls cleanup, configures input/output, installs the sample delegate on `audioQueue`, then starts the capture session on `sessionQueue` (`FeishuSpeech/Services/AudioRecorder.swift:62-83,87-138`).
- `stopRecording()` synchronously snapshots the complete buffer and calls `forceCleanup()` (`FeishuSpeech/Services/AudioRecorder.swift:148-159`).
- `forceCleanup()` asynchronously stops/tears down capture on `sessionQueue`, clears converter/session references, synchronously clears the buffer, and publishes `isRecording=false` (`FeishuSpeech/Services/AudioRecorder.swift:161-193`).
- Runtime, interruption, device-loss, and conversion-exhaustion errors converge on cleanup then publish a typed `RecordingFailure` on main (`FeishuSpeech/Services/AudioRecorder.swift:12-30,195-252`).
- Conversion produces 16 kHz, mono, interleaved Int16 and appends converted callback-sized data in order on `bufferQueue` (`FeishuSpeech/Services/AudioRecorder.swift:269-300,341-375`).

Contract gaps at this seam:

- No packet coalescer, byte-accounted async ingress, continuation lifecycle, seal-tail operation, or typed ingress overflow exists.
- The current 1,920,000-byte cap happens to equal the target 60-second byte ceiling, but overflow is silently dropped (`guard ... else { logger.warning; return }`) rather than terminal (`FeishuSpeech/Services/AudioRecorder.swift:8-10,369-375`).
- `stopRecording()` returns a full copy; there is no stream-consumer handoff (`FeishuSpeech/Services/AudioRecorder.swift:148-159`).
- The accepted design says raw callbacks remain on `audioQueue`, conversion/coalescing stays on audio/buffer serial queues, and capture must never block on the network (`docs/streaming-speech-design.md:154-166,312-324`). This identifies the existing queues as the attachment seam, without deciding whether `AudioRecorder` is evolved or wrapped.

Name/shape ambiguity that must stay open:

- The design diagram names `StreamingAudioRecorder` (`docs/streaming-speech-design.md:85-100`), while the architecture docking says “streaming AudioRecorder” (`docs/architecture.md:11-16`). Current source has only `AudioRecorder`. The repository does not settle whether issue #26 renames/replaces it, adds a sibling recorder, or extracts a separate ingress/coalescer.

Likely test ownership locations, based on the accepted blueprint:

- A new focused audio-stream test file under `FeishuSpeechTests/` for arbitrary-size coalescing, order, byte bound, one tail, padding, no-first-packet, overflow, interruption/device/conversion failure, reset, and continuation closure (`docs/streaming-speech-design.md:400-408`).
- Existing `FeishuSpeechTests/AudioRecorderRecoveryTests.swift` is explicitly excluded from the test target (`FeishuSpeech.xcodeproj/project.pbxproj:22-28`), so it cannot supply RED coverage unless project membership changes. Documentation calls it a pre-existing blocker (`docs/api.md:161-166`). A differently named new test file under the synchronized test folder would normally be included automatically.
- `MainViewModelTests.AudioRecorderFailureTests` currently covers publication/cleanup of existing recorder failures (`FeishuSpeechTests/MainViewModelTests.swift:456-556`).

Concurrent RED contract now present:

- `FeishuSpeechTests/StreamingAudioIngressTests.swift` constructs `AudioIngressConfiguration(packetByteCount:minimumTailByteCount:maximumBufferedByteCount:)` and `ByteBoundedAudioIngress(configuration:)`, then expects a public `stream`, synchronous `append`, idempotent `finish(streamEstablished:)`, and `fail` surface (`FeishuSpeechTests/StreamingAudioIngressTests.swift:8-13,22-112`).
- It fixes concrete type names `AudioIngressError.ingressOverflow` and `.captureFailed` and verifies the 300-element bound, exact ordering, one padded/unpadded tail, local no-first-packet completion, and first-terminal-result authority (`FeishuSpeechTests/StreamingAudioIngressTests.swift:15-112`).
- These names and signatures are test-owned concurrent artifacts, not facts from commit `9fed83f`; production currently has no matching declarations.

### 3. Feishu authentication and transport

Current types and seams:

- `SpeechResult.swift` contains `AuthResponse`, whole-file `SpeechRequest`/`SpeechData`/`SpeechConfig`, `SpeechResponse`, and `RecognitionData`; all models are `nonisolated` and `Sendable` where appropriate (`FeishuSpeech/Models/SpeechResult.swift:3-65`).
- The current endpoint constant is `file_recognize` (`FeishuSpeech/Services/FeishuAPIService.swift:14-16`).
- `FeishuAPIService` is a singleton actor with cached token/expiry, network state, JSON encoder/decoder, and a private initializer (`FeishuSpeech/Services/FeishuAPIService.swift:333-353`).
- DEBUG hooks inject one request sender and retry sleeper and expose reset/snapshot helpers (`FeishuSpeech/Services/FeishuAPIService.swift:396-499`).
- `recognizeSpeech` checks audio/network, applies one 30-second deadline, and wraps auth plus speech in `withRetry` (`FeishuSpeech/Services/FeishuAPIService.swift:501-553`). `withRetry` can execute three attempts with delay (`FeishuSpeech/Services/FeishuAPIService.swift:555-607`).
- `getAccessToken` owns cache lookup/fetch/update but is private (`FeishuSpeech/Services/FeishuAPIService.swift:609-647`).
- `sendSpeechRequest` builds one whole-file request, clears token on HTTP 400/401, and returns final text (`FeishuSpeech/Services/FeishuAPIService.swift:649-690`).
- The shared hostname-based HTTP primitive is `sendRequest(path:headers:body:)`, also private (`FeishuSpeech/Services/FeishuAPIService.swift:693-705,784-818`).

Likely new contract types named by accepted docs:

- `SpeechStreamEvent`: partial, final, cancelled, failed.
- `StreamFailure`: typed/sanitized terminal failures.
- `SpeechStreamingSession`: the internal serial async interface named in API docs (`docs/api.md:29-40`).
- `FeishuStreamingSession`: actor and concrete state owner named in design/architecture (`docs/streaming-speech-design.md:181-223`; `docs/architecture.md:35-44`).
- Encodable streaming request/config and decodable streaming response models containing action, sequence ID, stream ID, Base64 PCM, `format=pcm`, and `engine_type=16k_auto` (`docs/decisions/D-25-01.md:43-60`).

Likely file placement, clearly marked as inference from current conventions:

- Model contracts would fit either the existing `FeishuSpeech/Models/SpeechResult.swift` or a new file under `FeishuSpeech/Models/`; service actor behavior would fit a new file under `FeishuSpeech/Services/`. File-system synchronization means either location enters the app target automatically. The repository does not prescribe exact filenames.

Dependency/unknown seam:

- A per-hold streaming actor needs token acquisition/cache invalidation and request sending, but both usable primitives are private inside a singleton (`FeishuSpeech/Services/FeishuAPIService.swift:609-647,693-705`). The current source does not specify whether the streaming actor is nested/owned by `FeishuAPIService`, receives token/transport protocols, or makes those actor APIs internal. Selecting among those is an implementation decision, not a repository fact.
- Existing tests use the singleton DEBUG sender to record request host/path/header/body and a result sequence (`FeishuSpeechTests/FeishuAPIServiceTests.swift:8-20,308-429`; `FeishuSpeechTests/MockURLProtocol.swift:5-60`). This is the current proven test pattern for request sequencing and cancellation.

Required test location from the accepted blueprint:

- A new streaming transport test suite under `FeishuSpeechTests/`, with action/sequence order, no parallel requests, first-packet token refresh using the same action/sequence, no established-stream retry/fallback, idempotent finish/cancel, bounded abort, and sanitized error cases (`docs/streaming-speech-design.md:389-398`).

Concurrent RED contract now present:

- `FeishuSpeechTests/FeishuStreamingSessionTests.swift` fixes a concrete initializer surface with `streamID` (optional in tests), `initialToken`, async `refreshToken`, and async `requestSender`; operations are `sendAudioPacket`, `finish`, and `cancel` (`FeishuSpeechTests/FeishuStreamingSessionTests.swift:16-31,50-75,77-105`).
- The expected event name is `StreamingRecognitionEvent` with `.partial`, `.final`, `.cancelled`, and `.failed(.timeout)` (`FeishuSpeechTests/FeishuStreamingSessionTests.swift:8-14`).
- The suite asserts action/sequence/audio/stream-ID/config/auth fields, maximum one active request, same-sequence first-token refresh, no established-stream refresh/replay, local pre-acceptance cancel, one active abort, finish idempotence, and sanitized HTTP/backend failure surfaces (`FeishuSpeechTests/FeishuStreamingSessionTests.swift:16-193`).
- Test-local actors `StreamingRequestStub` and `RefreshTokenStub` provide deterministic request gating, parsing, and token-call counts (`FeishuSpeechTests/FeishuStreamingSessionTests.swift:196-279`). Production currently has no matching declarations.

### 4. Cursor destination and text insertion

Current source has no `AXUIElement` use other than process trust calls in `PermissionManager`; `rg` found no cursor destination, selected-text range, string-for-range, secure subrole, or focused-element adapter in production.

Existing adjacent seams:

- `PermissionManager` is `@MainActor`, singleton-only, and publishes accessibility/microphone/secure-input status (`FeishuSpeech/Services/PermissionManager.swift:9-21`). It checks AX trust during general permission refresh and secure input via `IsSecureEventInputEnabled()` (`FeishuSpeech/Services/PermissionManager.swift:23-39,95-106`).
- `TextInputSimulator` is a static enum. It trims text, snapshots the whole general pasteboard, writes text, posts Cmd+V, polls `changeCount`, and restores the snapshot (`FeishuSpeech/Services/TextInputSimulator.swift:18-73,77-140`). It cannot accept or verify an original PID/focused AX element.
- Its notification helper is private and only handles Cmd+V creation/consumption failure (`FeishuSpeech/Services/TextInputSimulator.swift:143-162`). There is no public “copy for manual recovery without synthetic input” operation.
- The app target has Accessibility permission UX, audio/automation entitlements, and app sandbox disabled (`FeishuSpeech/FeishuSpeech.entitlements:4-9`; `FeishuSpeech.xcodeproj/project.pbxproj:350-375`). No external package/framework dependency is declared (`FeishuSpeech.xcodeproj/project.pbxproj:50-65,105-106`).

Likely new contract types explicitly named or implied by accepted docs:

- `CursorDestinationToken`: generation, original PID, original focused AX element, original selected-text range, and capability facts (`docs/decisions/D-25-01.md:70-84`).
- `CursorTextSession`: `@MainActor` writer state/capability/replace/read-back/finalization owner (`docs/streaming-speech-design.md:225-295,312-322`).
- An Accessibility client seam plus fake, explicitly required by implementation slice 1 (`docs/streaming-speech-design.md:363-367`). The concrete adapter must cover trust, secure input/secure fields, frontmost PID, focused element, AX selected text/range set/get, attribute settability, and string-for-range.
- Typed writer mode/state/failure values covering final-only, armed, provisional, invalid, committed, and preserved (`docs/streaming-speech-design.md:133-152`).

Likely file placement, marked as inference:

- New AX session/client code belongs near current services under `FeishuSpeech/Services/`; its pure tokens/events may live under `Models/`. Exact file/type partitioning is not prescribed.
- New fake AX client and `CursorTextSessionTests.swift` would belong under `FeishuSpeechTests/` and auto-join the test target.

Required tests are enumerated at `docs/streaming-speech-design.md:410-419`: initial selection, duplicate/revised/shorter partials, Unicode and newline ranges, every destination mismatch, AX failures before/after mutation, partial preservation, secure/final-only capability decisions, and late-event no-ops.

### 5. Coordinator, lifecycle, settings, and UI

Current coordinator:

- `MainViewModel` is `@MainActor`; it observes hot-key, permissions, monitoring state, and recorder failure (`FeishuSpeech/ViewModels/MainViewModel.swift:19-33,67-135`).
- On recording it shows a fixed overlay, starts capture, and starts the 60-second timer (`FeishuSpeech/ViewModels/MainViewModel.swift:146-160,233-252`).
- On transcribing it captures the entire audio, hides the overlay, starts one task, and later performs one paste when `autoInsert` is true (`FeishuSpeech/ViewModels/MainViewModel.swift:254-319`).
- Its generation protects only post-recording transcription task results (`transcriptionGeneration`), not audio callbacks, stream events, cursor writes, timers, overlay updates, or cleanup (`FeishuSpeech/ViewModels/MainViewModel.swift:45-46,274-278,310-313,356-389`).
- Manual reset and sleep/wake share `cancelTranscriptionAndReturnIdle`; wake additionally recovers the event tap (`FeishuSpeech/ViewModels/MainViewModel.swift:360-389`).
- `cleanup()` increments transcription generation, cancels one task, cleans recorder, stops monitoring/timer, but has no streaming transport or cursor session to terminate yet (`FeishuSpeech/ViewModels/MainViewModel.swift:469-477`).

Injection/testability facts:

- Constructor injection exists for `AudioRecorder`, `AppSettings`, and `HotKeyWakeRecovering` only (`FeishuSpeech/ViewModels/MainViewModel.swift:52-65`).
- Tests subclass concrete `AudioRecorder` and `MainViewModel` and use DEBUG methods to observe behavior (`FeishuSpeechTests/MainViewModelTests.swift:537-633`).
- `FeishuAPIService.shared`, `HotKeyService.shared`, `PermissionManager.shared`, `OverlayWindowController.shared`, and static `TextInputSimulator` are fixed dependencies (`FeishuSpeech/ViewModels/MainViewModel.swift:28-32,293-305`). New deterministic coordinator tests will need seams for stream events, cursor writes, and finish/cancel observation; their exact form is not specified.

Existing tests likely to be migrated or extended:

- Hot-key state and release tests: `FeishuSpeechTests/HotKeyServiceTests.swift`.
- Coordinator/lifecycle/failure/empty-result tests: `FeishuSpeechTests/MainViewModelTests.swift`.
- Permissions/secure input tests: `FeishuSpeechTests/PermissionManagerTests.swift`.
- API/token/current hostname behavior: `FeishuSpeechTests/FeishuAPIServiceTests.swift` and `MockURLProtocol.swift`.

New coordinator coverage is prescribed at `docs/streaming-speech-design.md:421-429`: state order, release-vs-cap one-finish race, sealing rejection, generation invalidation on reset/sleep/wake, complete cleanup after capture/stream failure, `autoInsert=false`, and transcript-free logs/feedback.

## File and type impact map

### Existing production files directly affected by the accepted contract

| File | Current responsibility | Issue-26 seam |
|---|---|---|
| `FeishuSpeech/Services/AudioRecorder.swift` | Capture, conversion, whole buffer, capture failures | Ordered packet ingress or attachment to a separate coalescer; terminal overflow; seal/reset continuation behavior |
| `FeishuSpeech/Models/SpeechResult.swift` | Auth and whole-file request/response models | Streaming action/sequence/request/response models or coexistence with a new model file |
| `FeishuSpeech/Services/FeishuAPIService.swift` | Token cache, hostname HTTP, whole-file retry | Token/transport seam for the per-hold actor; production path must not use whole-file retry after establishment |
| `FeishuSpeech/Services/HotKeyState.swift` | Pending/recording/transcribing state | Streaming/sealing state and active/overlay semantics |
| `FeishuSpeech/Services/HotKeyService.swift` | Fn gate/release/max-duration transitions | Release/cap to sealing and no new hold during sealing |
| `FeishuSpeech/ViewModels/MainViewModel.swift` | Whole-file coordinator | Per-hold generation owner, audio/event consumers, cursor mode, terminal ordering, lifecycle cleanup |
| `FeishuSpeech/Models/RecordingState.swift` | Menu/status icon/text | Listening, sealing/finalizing, fallback/error feedback |
| `FeishuSpeech/Services/TextInputSimulator.swift` | Unbound final paste | One final-only same-target path and copy-only recovery seam, if retained |
| `FeishuSpeech/Services/PermissionManager.swift` | Process trust and secure-input polling | Capability input is adjacent, but per-session AX/secure verification belongs behind the accepted AX client seam |
| `FeishuSpeech/Views/RecordingOverlayView.swift` | Fixed listening overlay | Status-only listening/sealing/fallback presentation |
| `FeishuSpeech/Controllers/OverlayWindowController.swift` | Fixed overlay show/hide and generation guard | Accept/update status while preserving existing show/hide race guard |
| `FeishuSpeech/Views/MenuBarView.swift` | Renders coordinator status | New state text/color docking; no transcript content |

### Likely new production artifacts (names from design where available; exact files unresolved)

| Contract artifact | Evidence | Likely repository area |
|---|---|---|
| `SpeechStreamEvent`, `StreamFailure`, `SpeechStreamingSession` | `docs/api.md:29-40` | `Models/` and/or `Services/` |
| `FeishuStreamingSession` actor | `docs/streaming-speech-design.md:181-223` | `Services/` |
| Streaming request/response/config models | `docs/decisions/D-25-01.md:43-60` | `Models/` |
| Byte-bounded coalescing ingress and typed overflow | `docs/streaming-speech-design.md:154-179` | `Services/` or inside recorder; unresolved |
| `CursorDestinationToken` | `docs/decisions/D-25-01.md:70-84` | `Models/`/`Services/` |
| `CursorTextSession` | `docs/streaming-speech-design.md:225-295` | `Services/` |
| Accessibility client protocol, production adapter, test fake | `docs/streaming-speech-design.md:363-376` | Production `Services/`, fake in tests |

## Dependency and delivery order already specified by the accepted design

The repository itself defines these dependent slices, so listing them is not an implementation choice (`docs/streaming-speech-design.md:363-384`):

1. Contract seams and fakes: typed stream events/failures, ingress configuration, AX client seam; tests own these contracts first.
2. Bounded streaming recorder/ingress: coalescing, byte bound, stop/tail/overflow/interruption/cleanup.
3. Feishu streaming actor: request models, stream ID, serialization, first-packet token refresh, finish, bounded abort, sanitized errors.
4. Cursor text session: capability probe, captured target, verified replacements, invalidation, final/fallback behavior.
5. Coordinator/state migration: generation-bound tasks and cleanup replace the whole-file production path.
6. UI/settings docking: listening/sealing/fallback state while preserving `autoInsert`/`playSound` meaning.
7. Credential-bearing Feishu and cross-application AX UAT before a broad availability claim.

Cross-slice dependencies visible in source:

- Audio must expose ordered elements before the transport consumer and coordinator can be tested end to end.
- Transport must expose typed partial/final/terminal events before coordinator/cursor integration.
- AX session tests require a fake client before real cross-application UI calls.
- Coordinator migration depends on all three contracts and must preserve existing hot-key tap-thread, `sessionQueue`, sleep/wake, and overlay generation invariants (`docs/architecture.md:142-170,195-242,278-290`).
- UI docking depends on final coordinator states and must not precede that state contract.

## Risks and conflicts found in current source

### Contract conflicts that implementation must remove from the production streaming path

- **Silent audio loss:** overflow logs and returns instead of failing (`FeishuSpeech/Services/AudioRecorder.swift:369-375`), contrary to `docs/decisions/D-25-01.md:62-68`.
- **Whole-operation retries:** current auth+speech is retried up to three times (`FeishuSpeech/Services/FeishuAPIService.swift:524-529,555-597`), contrary to established-stream no-replay rules.
- **Current-focus insertion:** the static paste helper posts Cmd+V without a destination token (`FeishuSpeech/Services/TextInputSimulator.swift:28-48,117-140`), while fallback requires same original PID/element revalidation.
- **Sensitive logging:** current source logs recognized transcript in `MainViewModel` and `FeishuAPIService`, raw speech error bodies, and backend messages (`FeishuSpeech/ViewModels/MainViewModel.swift:307`; `FeishuSpeech/Services/FeishuAPIService.swift:638-639,671-672,684-689`). This conflicts with the accepted privacy contract.
- **Generation is too narrow:** `transcriptionGeneration` guards only the current whole-file task, not every asynchronous boundary (`FeishuSpeech/ViewModels/MainViewModel.swift:45-46,274-278,356-389`).
- **No copy-only stale fallback:** current paste utility restores the old clipboard after consumption and only leaves text when event creation fails; it has no explicit “stale target, copy final for manual recovery, post no event” API (`FeishuSpeech/Services/TextInputSimulator.swift:35-73,143-162`).

### Concurrency and lifecycle risks

- Xcode enables `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for both app and test targets (`FeishuSpeech.xcodeproj/project.pbxproj:350-375,408-455`). New transport/audio/model types will need deliberate isolation and `Sendable` boundaries, following the existing `nonisolated` model pattern (`FeishuSpeech/Models/SpeechResult.swift:3-65`).
- Actor isolation alone does not guarantee one in-flight request if work is moved into child tasks; the accepted design explicitly requires a serial request gate (`docs/streaming-speech-design.md:206-207`).
- `AVCaptureSession.startRunning/stopRunning` must remain on `sessionQueue` because it blocks (`FeishuSpeech/Services/AudioRecorder.swift:41-44,119-136,165-179`).
- Existing `forceCleanup()` stops capture asynchronously but clears the buffer synchronously immediately afterward (`FeishuSpeech/Services/AudioRecorder.swift:161-193`). Exact “capture closed before at-most-one tail is sealed” coordination does not exist and needs deterministic tests.
- Recorder errors currently publish via Combine after cleanup (`FeishuSpeech/Services/AudioRecorder.swift:231-245`); streaming ingress continuation termination and coordinator generation invalidation must converge with this path.
- Reset/sleep/wake currently cancel only a transcription task and reset shared services (`FeishuSpeech/ViewModels/MainViewModel.swift:360-389`). New recorder ingress, transport request, cursor writer, event-consumer tasks, and overlay state all need the accepted invalidation-before-cleanup ordering (`docs/streaming-speech-design.md:323-332`).

### Build/configuration risks and unknowns

- `CLAUDE.md` describes macOS 13+ / Swift 5.9+, but the Xcode file currently sets `MACOSX_DEPLOYMENT_TARGET = 26.2` and `SWIFT_VERSION = 5.0` (`FeishuSpeech.xcodeproj/project.pbxproj:279-287,339-346,350-405`). Whether compatibility must actually remain macOS 13 is unresolved by current configuration and should not be silently changed as part of issue #26.
- The app target has no package dependencies and an empty explicit frameworks build phase (`FeishuSpeech.xcodeproj/project.pbxproj:50-65,105-106`). AX/ApplicationServices calls are currently reached through imported system modules; no repository evidence requires a new external dependency.
- The existing `AudioRecorderRecoveryTests.swift` exclusion is intentional and documented as a pre-existing blocker (`FeishuSpeech.xcodeproj/project.pbxproj:22-28`; `docs/api.md:161-166`). Issue #26 should not accidentally assume that file runs.
- The project uses synchronized groups, so adding files generally requires no PBX file-reference edit; only a new exception or moving files outside the synchronized roots would require project membership work (`FeishuSpeech.xcodeproj/project.pbxproj:31-48,101-126`).

## Unknowns that block a reliable implementation plan if left unresolved

These are not user-value decisions unless noted; most should be settled by tests/source evidence during implementation:

1. **Exact token/transport seam:** current token and HTTP methods are private inside `FeishuAPIService`; the repository does not select how `FeishuStreamingSession` accesses them.
2. **Recorder shape/name:** accepted docs use both `StreamingAudioRecorder` and streaming `AudioRecorder`; exact replacement/wrapper/extracted-ingress shape is not fixed.
3. **Feishu streaming response schema details:** local docs prescribe behavior but source contains no streaming model. Credential-bearing live evidence is explicitly required for intermediate semantic shape, and transcript content must not be recorded (`docs/streaming-speech-design.md:43-51,431-443`).
4. **Cross-application AX behavior:** compatibility is explicitly application-dependent and requires live UAT (`docs/streaming-speech-design.md:50-51,431-440`). Unit fakes can prove logic, not real target behavior.
5. **Fallback clipboard UX mechanism:** contract requires copy-only manual recovery for a stale fallback target, but the current simulator has only paste-and-restore plus a private notification helper. Exact public seam is absent.
6. **Startup ordering on secure target:** design requires secure field/Event Input rejection before audio/network work (`docs/decisions/D-25-01.md:81-84`), while current coordinator starts overlay/capture directly after generic permission checks (`FeishuSpeech/ViewModels/MainViewModel.swift:152-160,214-251`). Exact asynchronous capability/start acceptance handshake is not present.
7. **Product-facing wording and broad availability claim:** status-only states are fixed, but exact Chinese copy and what applications are advertised as supported require UAT/product judgment. Do not infer these from unit tests.
8. **Deployment target discrepancy:** whether macOS 13 remains a required supported baseline is a user-owned/public capability question if changing the target becomes necessary.

## Test map

### Existing suites to preserve

- `FeishuSpeechTests/HotKeyServiceTests.swift`: hot-key state/tap/wake behavior.
- `FeishuSpeechTests/MainViewModelTests.swift`: subscription lifecycle, sleep/wake, coordinator races, empty feedback, recorder failures.
- `FeishuSpeechTests/FeishuAPIServiceTests.swift`: token lifetime, HTTP parser, retry/cancellation, hostname routing, token refresh/reset.
- `FeishuSpeechTests/MockURLProtocol.swift`: thread-safe request/result sequence recorder.
- `FeishuSpeechTests/PermissionManagerTests.swift`: secure-input and permission refresh.
- `FeishuSpeechTests/AppSettingsCredentialStorageTests.swift`: credentials/preferences; `autoInsert` semantics must remain intact.

### New focused suites implied by the accepted blueprint

- `StreamingAudioIngressTests.swift` now exists as a concurrent untracked RED artifact for audio ingress/coalescing.
- `FeishuStreamingSessionTests.swift` now exists as a concurrent untracked RED artifact for request serialization/protocol/error privacy.
- `CursorTextSessionTests` (name inferred) with a fake AX client.
- Coordinator streaming-generation/state tests, either in `MainViewModelTests.swift` or a synchronized new test file.
- State/UI model tests for streaming/sealing/final-only presentation without transcript content.

Because production and test custody must remain separate, the test-owning role should establish RED assertions before the implementation-owning role changes production (`CLAUDE.md`, Non-Negotiable Rules; `docs/streaming-speech-design.md:363-387`).

## Validation commands

Run from `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`.

Project/target inspection:

```bash
xcodebuild -project FeishuSpeech.xcodeproj -list
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -showBuildSettings
```

Focused suites as they exist now:

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/HotKeyServiceTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/FeishuAPIServiceTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/MainViewModelTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/CoordinatorStateInterplayTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/PermissionManagerTests test
```

After new suite names are established, use the same `-only-testing:FeishuSpeechTests/<SuiteName>` pattern for audio ingress, streaming transport, and cursor writer before running the full gate.

The two concurrently established RED suite names can already be invoked with:

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/StreamingAudioIngressTests test
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/FeishuStreamingSessionTests test
```

Required repository gates from `CLAUDE.md`:

```bash
xcodebuild -scheme FeishuSpeech -configuration Debug build
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test
swiftlint
```

Required live UAT before a general-availability verdict is the matrix at `docs/streaming-speech-design.md:431-443`: native text fields/editors, browsers, Electron, terminal apps, document editors/undo, secure targets, focus/caret/user interference, target close/app termination, 60-second normal/slow-network behavior, and credential-bearing Feishu partial-shape observation without transcript capture.

## Fact vs assumption summary

### Confirmed facts

- The worktree HEAD is commit `9fed83f` on branch `workflow/issue-26`.
- The worktree was clean at initial inspection; two untracked concurrent RED test files appeared before final verification. Tracked production remained unchanged during this exploration.
- Issue #26 has only a local roadmap title; accepted detailed behavior is in D-25-01/design/architecture/API docs.
- Production is entirely whole-file today; streaming transport, bounded async ingress, and AX cursor writer do not exist.
- New files under synchronized app/test folders normally auto-join targets.
- `AudioRecorderRecoveryTests.swift` is excluded.
- Existing source contains several explicit conflicts with the accepted streaming contract, listed above.

### Inferences (not implementation decisions)

- New contract/service/test files are likely because the accepted design names new responsibilities and the current files contain no equivalent.
- Suggested directory locations follow current `Models/`, `Services/`, and `FeishuSpeechTests/` conventions; exact filenames and file partitioning are unresolved.
- Existing DEBUG request-sequence and subclass/fake patterns are likely reusable test patterns, but the accepted design does not mandate their exact reuse.

### User/value decisions intentionally not made

- No choice was made between evolving `AudioRecorder` and introducing a sibling/wrapper.
- No choice was made for token/transport dependency architecture.
- No compatibility claim or supported-application list was chosen before UAT.
- No deployment-target change or `autoInsert` semantic change was assumed.
- No UI wording beyond accepted status categories was selected.

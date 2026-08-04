# API

This page documents the Feishu integration contract implemented by
`FeishuAPIService` and `FeishuStreamingSession`.

## Feishu endpoints

`FeishuAPIService` sends HTTPS `POST` requests to `open.feishu.cn`.

| Purpose | Path | Request | Success response |
|---|---|---|---|
| Tenant token | `/open-apis/auth/v3/tenant_access_token/internal` | JSON object with `app_id` and `app_secret` | `AuthResponse` with `code == 0`, `tenant_access_token`, and optional `expire` |
| Production streaming recognition | `/open-apis/speech_to_text/v1/speech/stream_recognize` | Base64 PCM fragment plus stream/action/sequence config | Code-zero response; optional `data.recognition_text` with `data.text` fallback |
| Compatibility-only whole-file recognition | `/open-apis/speech_to_text/v1/speech/file_recognize` | `SpeechRequest` JSON with base64 PCM data and `SpeechConfig` | `SpeechResponse` with `code == 0` and `data.recognition_text` |

Speech requests use `Authorization: Bearer <tenant_access_token>`,
`format: "pcm"`, and `engine_type: "16k_auto"`.

The production Fn interaction never calls the compatibility-only whole-file endpoint. Recoverable
streaming failures may create a fresh streaming session and replay the current hold's ordered PCM
journal, but never fall back to whole-file recognition.

### Authentication startup and public failures

The streaming provider must obtain a tenant token before it constructs a session or sends any
request to `stream_recognize`. A tenant-token business rejection therefore means that the
streaming endpoint was not reached. An earlier installed-Release UAT passed this boundary,
accepted two HTTP-200 audio packets, and then received HTTP 200 with business code `10024` for
`action=0, sequence_id=2`. Three later fresh sessions received the same business code on
`action=1, sequence_id=0`. This proves transport reachability and separates the failure from the
earlier response-shape parser defect; it does not prove a completed recognition stream.

Current public [Feishu endpoint documentation](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/reference/ai/speech_to_text-v1/speech/stream_recognize)
and the [official generated Lark SDK](https://github.com/larksuite/oapi-sdk-go/blob/8dfbfff01d210b20ec9473bf383d38d1b54aa37b/service/speech_to_text/v1/model.go#L544-L559)
do not define business code `10024`. The endpoint documentation specifies 100–200 ms audio chunks,
a 20-stream tenant cap, and the action/sequence contract, but does not map `10024` to pacing, quota,
tenant edition, sequence, or leaked-stream state. FeishuSpeech treats `10024` as recoverable for
this hold as an application resilience policy, not as an authoritative interpretation of the
provider code.

`FeishuAPIService.APIError.authFailed` maps to the fixed public message
`认证失败，请检查应用凭据`. The associated backend message, credential values, transcript, and raw
response stay outside UI and logs. A recoverable failure while Fn remains held produces only a
sanitized diagnostic: it does not publish `RecordingState.error`, call `HotKeyService.setError`,
hide/re-show the overlay, copy text, or post a system notification. A non-recoverable failure still
invalidates the active generation, hides the overlay, and tears the interaction down once.

Newer build-5 evidence recorded 66 HTTP-200 transactions over 13.55 seconds while visible output
stopped after one word. This proves continued transport but not the scalar contents, coordinator
ownership outcomes, or target acceptance. Owner UAT must still verify the repaired replay, release,
continuous-output, and remaining runtime contract.

## Streaming recognition contract (issues #25/#26/#27)

Issues #25/#26 introduced production recognition; issue #27 corrects response interpretation at:

`POST /open-apis/speech_to_text/v1/speech/stream_recognize`

The official API describes chunked real-time recognition and recommends 100–200 ms audio
fragments. Requests retain bearer authentication and Base64 PCM JSON with `format: "pcm"` and
`engine_type: "16k_auto"`.

### Internal stream interface

`SpeechStreamingSession` exposes serial async operations equivalent to:

```swift
func sendAudioPacket(_ pcm16: Data) async throws -> StreamingRecognitionEvent
func finish() async throws -> StreamingRecognitionEvent
func cancel() async
```

Its typed events are `partial(String)`, `final(String)`, `cancelled`, and
`failed(StreamFailure)`. No raw Feishu response body or backend message crosses this boundary.

The concrete `FeishuStreamingSession` actor uses an explicit FIFO gate so actor reentrancy cannot
overlap requests. Each interaction owns a 16-character lowercase-letter/digit/underscore
`stream_id`. Accepted
requests use monotonically increasing `sequence_id` values beginning at zero:

| Action | Meaning | Audio |
|---:|---|---|
| 1 | open with first packet | non-empty PCM |
| 0 | continue | non-empty PCM |
| 2 | finish normally, exactly once | empty |
| 3 | best-effort abort of an accepted but not successfully finished stream, exactly once and within one total second | empty |

Requests are strictly serial. Only the exact known invalid-token business code in a bounded HTTP
400/401 response may refresh and retry the same action-1 packet and sequence once before any packet
is accepted; generic HTTP 400 is terminal. Recognition outcome and abort eligibility are separate:
a failed first action 1 sends no abort; a failed established action 0 or action 2 attempts one
action 3 at the next unconsumed sequence; a successfully completed action 2 forbids action 3.
Repeated cancellation cannot emit another abort, and action 3 never overlaps an in-flight packet.
Its response is diagnostic only and cannot turn the failed recognition into success.

Audio ingress emits ordered 6,400-byte elements (about 200 ms at 16 kHz mono Int16) and is bounded
at exactly 1,920,000 captured bytes for the 60-second maximum. In production replay mode, delivered
packet bytes remain charged under the same storage lock because the coordinator retains them for a
possible fresh-session replay; queued and pending bytes share that one hold-wide budget. The
non-replay initializer retains the older occupancy behavior and releases exact packet capacity on
dequeue. After recorder stop crosses the real audio callback queue barrier, an established stream's
non-empty seal tail may pad to the 3,200-byte local 100 ms minimum; generated silence is not charged
as newly captured audio. Overflow is a typed terminal failure; audio is not dropped or reordered.

### Hold-local retry and replay

One Fn hold owns one `AudioRecorder`, one `ByteBoundedAudioIngress`, and a coordinator journal of
every drained packet in capture order. It owns at most one active `FeishuStreamingSession` at a
time. Before a packet's first send, the coordinator appends it to the journal, so a failed packet
remains replayable. On a recoverable failure it cancels/aborts the failed session once, waits with
cancellable exponential backoff, creates a fresh stream, and serially replays the journal from
index zero without re-chunking, combining, dropping, or parallelizing packets.

Historical replay responses do not churn the target. The coordinator uses each journal packet's
stable index as output identity: an already-owned index is suppressed on every replay, while a
previously failed unowned index may be claimed once when replay first succeeds. Audio captured
during abort, backoff, and replay continues through the same ingress. There is no
`file_recognize` fallback.

The retry policy is hold-wide and has no attempt-count limit independent of the 60-second hold cap.
Its base delays are 250 ms, 500 ms, 1 s, 2 s, then 4 s; injected jitter is clamped to 0.8–1.2 and
the final delay is clamped to 200 ms–4 s. The ordinal never resets after a partially successful
replacement stream. Recoverable classifications are:

- `StreamFailure.network` and `.timeout`;
- HTTP 408, 425, 429, and 5xx;
- backend business code `10024` only;
- API/session-factory `.timeout`, `.networkUnavailable`, `.connectionFailed`, and `.networkError`.

Malformed responses, response-identity mismatches, invalid request/response, authentication,
recognition-contract failures, unknown/unclassified errors, other backend business codes, and
other HTTP statuses are not retried by this outer hold loop. Audio ingress/capture and
permission/security failures remain lifecycle-owned rather than reconnectable. Output
destination/security changes suspend automatic output for the hold; they do not authorize a
transport reconnect or retarget.

Fn release and the 60-second cap set sealing before any suspension point and close admission to a
new session. Pending delay and session-creation tasks are actively cancelled. A live attempt may
drain the sealed ingress and finish once; a replaying replacement is cancelled once and production
typed cancellation is treated as sealed control flow, not a new failure. Every early exit waits
for the old recorder's stop/barrier task before returning idle, so a successor cannot inherit or be
closed by stale ingress/resource cleanup. A recoverable failure after sealing cannot claim or route
response text. If no usable held recognition was ever observed, it produces one fixed stream error;
otherwise completion does not invent an output or empty-result error. Reset, sleep/wake,
permission/security loss, capture failure, and cleanup invalidate
generation and output authority and cancel the current transport immediately, making late callbacks
inert. When recorder shutdown is already in flight, its barrier remains independently retained: it
blocks successor admission and final idle/error publication, but never delays authority revocation
or transport cancellation.

Feishu responses are treated as complete opaque recognition snapshots. The coordinator keeps
packet-index replay ownership separate from `latestSnapshot`: each eligible journal index may own a
response once, but an equal snapshot emits no output and any different snapshot replaces the held
recognition state. Historical replay indices remain suppressed even if a replacement attempt
returns different text; a previously failed unowned index may advance the snapshot once. Action 2
is not output authority and cannot mutate text after release.

Response decoding follows KaolaTerminal's credential-bearing, proven streaming implementation:
after valid JSON and `code == 0`, response `stream_id` and `sequence_id` echoes are ignored;
`data.recognition_text` is preferred, `data.text` is accepted as a fallback, and missing `data` or
both text fields maps to an empty partial/final value. Identity, action, and sequence remain strict
request-side invariants. A nonzero business `code` still fails the stream (with the existing
bounded first-packet token-refresh exception), and malformed JSON still fails as an invalid
response. Raw bodies, backend messages, IDs, text, audio, credentials, and tokens remain outside
public diagnostics.

The public Feishu contract confirms the endpoint, fields, action meanings, Base64 PCM, and a
100–200 ms fragment recommendation. Lowercase-only IDs, exact packet/tail sizes, empty strings for
terminal audio, same-sequence first-token retry, strict serialization/idempotence, and
snapshot replacement and packet-index replay suppression are FeishuSpeech policies rather than
vendor guarantees. They remain
behind credential-bearing UAT.

### Internal cursor-writer interface

Post-UAT refinement: the earlier strict destination gate is superseded. Recognition startup does
not require a successfully captured Accessibility cursor or focused element. AX range replacement
is used opportunistically where the target exposes the required safe, verifiable operations.

`CursorTextSession` opens one destination token containing the interaction generation,
original PID, original focused `AXUIElement`, and original selected-text range. Live mode requires
settable selected-text and selected-range attributes plus string-for-range verification.

Every update replaces the complete app-owned provisional range on that captured element. Before
and after a mutation, the writer validates generation, frontmost PID, focused element, caret,
owned range, and exact prior text. Accessibility-returned ranges define ownership; Swift
`String.count` does not. Any mismatch invalidates the writer permanently for that hold, and late
events write nothing. Verified AX replacement may carry LF/newline as multiline text data; it does
not synthesize Return.

When a non-secure destination was captured but cannot support live range replacement, the initial
`.finalOnly` result arms a continuous keyboard owner bound to the captured PID and exact
`AXUIElement`. A first-partial rebind that returns `.finalOnly` does the same and offers that
triggering partial immediately. Thus every eligible packet response received before sealing can
claim its index once; only a different complete snapshot is offered while Fn remains held.
Release only closes that existing owner and cannot create output.

When AX destination capture or confirmation is unavailable, the first non-contentless hypothesis
causes one more `CursorTextSession.begin()` attempt. If that yields live AX capability, normal
verified range replacement takes ownership. If it remains unavailable,
`CurrentFocusAppendSession` binds the then-frontmost PID and receives complete snapshots. It
compares Swift `Character` arrays without normalization, finds the exact longest common prefix,
posts one Backspace pair for every previously owned divergent grapheme, then posts the replacement
suffix. Equal snapshots post nothing; unsafe and contentless values remain ineligible.

Route eligibility is intentionally asymmetric. All routes reject action-capable controls except
that verified AX replacement may write LF as text data. The generic keyboard route rejects LF and
all other C0/C1/DEL controls before snapshot ownership or event construction, so it cannot turn
recognized text into Return, submit, or execute input.

Every keyboard transaction rechecks generation/admission, live Secure Input, and the bound
frontmost PID immediately before and after posting. A captured owner additionally validates the token's current security, original PID,
and `CFEqual` identity of the current focused element before and after the synchronous mutation.
Application activation change, PID/element drift, security rejection, generation invalidation, or
uncertain delivery permanently suspends the owner.

The existing HID `CGEventTap` is the synchronous interference authority. Input-monitor installation
and baseline capture are atomic under a shared `NSLock` gate. Each destructive Backspace pair and
the optional insertion pair acquire that gate, verify the armed epoch, and retain the lock
continuously across both key-down and key-up posts. Physical key-down, non-Fn modifier-change,
mouse-down, and mouse-drag events must acquire the same gate before advancing the epoch; the tap
callback cannot return them for dispatch until an in-progress synthetic pair releases it.
FeishuSpeech-tagged events and Fn transitions are excluded. Tap timeout/user-input disable advances
the epoch as loss of observability before recovery. Local/global AppKit monitors provide
supplemental early suspension only; both must arm successfully or the owner fails closed.

The keyboard poster accepts a positive bound PID and one replacement plan. It creates one tagged
`.privateState` source and fully constructs all modifier-neutral Backspace down/up pairs followed
by the Unicode insertion down/up pair, when needed, before posting anything. Source/event
construction failure or the final security sample causes zero posts. `.posted` means only that the
ordered transaction was submitted: CoreGraphics provides no target-control acceptance
acknowledgement.

An epoch change after some Backspaces may leave a partial visible mutation. A physical event cannot
split a complete synthetic pair; it advances immediately after that pair releases the gate, and the
next pair observes the drift. The poster then permanently suspends the owner and never rolls back.

After any provisional delivery attempt, destination/security loss, or uncertainty, no full-text
resend, one-shot current-focus insertion, Cmd+V, alternate target, or clipboard recovery is allowed.
Release-time one-shot/final-only insertion and manual-copy recovery are removed even when no output
owner was created or no post was attempted.

The unbound path uses no pasteboard, selection, or cursor navigation. D-27-01 narrowly permits
Backspace only up to this hold's recorded owned grapheme tail; it never deletes pre-existing text.
Because it has no AX range, it cannot observe a caret move within the same process; text may
therefore reach a different caret in that process. This residual risk is explicit. The previous
snapshot advances only after a full transaction is submitted. Physical keyboard or
mouse input, PID/activation change, security rejection, generation mismatch, or delivery
uncertainty permanently suspends the owner without rollback. FeishuSpeech-tagged events and Fn
transitions are exempt. At release, response/retry admission is already closed: action-2 and late
packet/final values cannot append or replace text.

The generic route does not ask the user to confirm cursor position and does not request a new macOS
permission during the hold. Same-PID caret movement initiated by the target application cannot be
proven without AX and remains an explicit best-effort limitation.

`autoInsert=false` keeps recognition active but discards cursor-writing capability and produces no
target or pasteboard mutation. Usable held recognition is tracked independently, so disabled,
unsafe, or ownerless output is not misreported as an empty result or stream error. Secure targets
and Secure Event Input still fail closed before
audio/network work when affirmatively detected.

The coordinator's response receipt is transcript-free. It records only generation, attempt and
journal index, source/event kind, eligibility, ownership and output outcome, coarse raw-response
snapshot decision, previous/new/common-prefix UTF-16 and `Character` counts, Backspace/insertion
counts, route, and outcome. It does not contain or hash text and does not record audio,
credentials/tokens, stream IDs, raw response bodies/messages, PID, AX identity/value, application
or window names, or clipboard payloads. Shape is diagnostic only and never determines ownership.

These are verified local routing and event-construction contracts, not an end-to-end acceptance
claim. Installed owner UAT must still observe visible held output on the real target. A submitted
pair with no visible text remains a PARTIAL result and does not authorize global HID posting,
retries, destructive editing, or fallback after uncertainty.

See [D-25-01](decisions/D-25-01.md), [D-26-01](decisions/D-26-01.md),
[D-27-01](decisions/D-27-01.md), and the
[full design](streaming-speech-design.md) for state, lifecycle, failure, fallback, privacy, and test
requirements.

## Credential storage

The Feishu App ID and App Secret are runtime `AppSettings` values, but they are
not encoded into the `FeishuSpeechSettings` user-defaults payload. `AppSettings`
persists credentials through `CredentialStoring`; the default store is
`KeychainCredentialStore`, which uses macOS Security.framework generic password
items.

The keychain service is `Siji.FeishuSpeech.credentials`. The credential account
values are `appId` and `appSecret`, matching `CredentialAccount.appId.rawValue`
and `CredentialAccount.appSecret.rawValue`.

`FeishuSpeechSettings` stores only non-credential preferences:

- `autoInsert`
- `playSound`
- `launchAtLogin`

On load, `AppSettings` migrates legacy credentials from encoded
`FeishuSpeechSettings` fields and from standalone user-default keys named
`appId` / `appSecret`. Standalone values take precedence when both legacy
sources exist. Legacy defaults are scrubbed only after migration succeeds and the
credentials can be read from the credential store. If migration, read, or write
fails, the legacy credentials are preserved as a fallback instead of being
deleted.

## HTTP transport and deadline

Authentication and speech requests use `URLSession` with the hostname
`open.feishu.cn`. System DNS therefore selects a current Feishu CDN endpoint;
the runtime path does not depend on a static IP list.

The streaming factory obtains one token through the existing cache/fetch path without the
whole-file retry wrapper, snapshots it into the per-hold actor, and injects one-request HTTP and
one-time pre-establishment token refresh closures. Raw response bodies and backend messages are
mapped to typed failures and never reach the coordinator, UI, or logs.

`FeishuAPIService.recognizeSpeech` owns one 30-second end-to-end deadline that
covers authentication, retries, backoff, and the speech request. When the
deadline expires, cancellation propagates into the active URLSession task and
the service reports `APIError.timeout`. `MainViewModel` does not add a competing
timer.

## Token cache

`AuthResponse` decodes Feishu's optional `expire` field as either an integer or
an integer string. Cache lifetime is calculated as follows:

- positive `expire`: `expire - 300` seconds, reserving a 300 second safety
  margin.
- missing, zero, or negative `expire`: fallback to the legacy 6000 second
  default.

Short positive values do not use the long fallback. For example, `expire: 299`
produces an already-expired lifetime, forcing a fresh token on the next request.

The token cache is cleared on network recovery and on speech API HTTP 400/401
responses so the next retry can obtain a fresh tenant token.

System wake also resets Feishu API client state. `MainViewModel` calls
`FeishuAPIService.resetStateForWake()` from both sleep and wake handlers. That
method clears the cached tenant token, token expiry, and last network error, and
sets network availability back to true so later requests perform fresh
post-wake network work instead of reusing a stale unavailable state.

The DEBUG wake-reset snapshot exposes only non-secret state used by tests:
whether a cached token exists, whether token expiry exists, the last network
error description, and the current network-availability flag.

## Retry and cancellation

The legacy `FeishuAPIService.withRetry` helper retries retriable whole-file/API work up to three
attempts with linear backoff. It is separate from the production Fn hold-local streaming loop
described above. `CancellationError` and task cancellation are terminal to the helper:

- retry attempts stop immediately;
- the active URLSession request is cancelled;
- no later retry starts after the end-to-end deadline.

This preserves the caller's timeout/cancel semantics instead of converting
cancelled work into additional network attempts.

## Test target caveat

`FeishuSpeechTests` is wired into the Xcode project. Issue #26 added automated coverage for exact
audio ingress accounting, recorder sealing barriers, streaming action/sequence/token/cancel races,
cursor replacement, captured and unbound output, lifecycle generation, settings, and fixed
completion feedback. Direct lifecycle-free execution of the complete XCTest bundle reports 272/272
passing. That evidence predates issue #27 and does not prove snapshot reconciliation. Issue #27
requires focused and full-suite coverage for duplicate, extension, shorter, revision, replay,
Unicode-grapheme Backspace counts, transaction ordering/suspension, AX replacement, and release
suppression. Multiline tests must prove LF is accepted only by AX range replacement and rejected by
the generic keyboard route. `8ebf31e` and `81dbfc8` provide earlier atomic race and unified-seam
evidence, including baseline capture, continuous lock hold across each complete pair, physical
advance through the same gate, tap-disable loss-of-observability, and fail-closed monitor arming.
Production is `ec4ddd6`; `cd1132c` directly exercises `SystemFinalTextCurrentFocusEventPoster`
through the real `CurrentFocusInputInterferenceEpoch` gate and is the final production-gate test
provenance.

`AudioRecorderRecoveryTests.swift` remains excluded from the test target because it is a recorded
pre-existing AudioRecorder-owned blocker outside the #11/#12/#21 API recovery bundle.

Automated fakes do not complete the runtime contract. Installed Release UAT with real credentials
must still verify failed-stream action 3, fresh-session replay, release during backoff, terminal
empty-audio encoding, real response text shape, same-sequence token refresh, PCM/tail acceptance,
slow-network behavior, tenant permission/edition, and the cross-application AX/current-focus
matrix. No transcript, audio, credential, token, stream ID, raw body/backend message, target
content/title, or clipboard payload may be recorded during that UAT.

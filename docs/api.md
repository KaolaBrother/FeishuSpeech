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
streaming endpoint was not reached. The latest recorded installed-Release UAT passed this boundary,
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

Owner UAT must still verify the new failed-stream abort, fresh-session replay, release boundary,
continuous output, successful finalization, and remaining runtime contract. The observed accepted
packets and `10024` failures do not close that gate.

## Streaming recognition contract (issues #25/#26)

Issue #25 defined and issue #26 implements production recognition at:

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

Historical replay responses do not churn the target. While catching up, the coordinator retains
only the latest accepted replay hypothesis; when it reaches the journal frontier it offers that
single opaque value, then resumes live packet delivery. Audio captured during abort, backoff, and
replay continues through the same ingress. There is no `file_recognize` fallback.

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
typed cancellation is treated as sealed control flow, not a new failure. Every early fallback waits
for the old recorder's stop/barrier task before returning idle, so a successor cannot inherit or be
closed by stale ingress/resource cleanup. A recoverable failure after sealing routes the latest
usable value through its selected output capability; no usable hypothesis produces one fixed stream
error. Reset, sleep/wake, permission/security loss, capture failure, and cleanup invalidate
generation and output authority and cancel the current transport immediately, making late callbacks
inert. When recorder shutdown is already in flight, its barrier remains independently retained: it
blocks successor admission and final idle/error publication, but never delays authority revocation
or transport cancellation.

Feishu does not define the semantic shape of intermediate `recognition_text`. Every partial is
therefore the complete opaque replacement state, never an appendable delta. A non-empty action-2
response is the final authority.

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
terminal audio, same-sequence first-token retry, strict serialization/idempotence, and opaque
replacement/final authority are FeishuSpeech policies rather than vendor guarantees. They remain
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
events write nothing.

When a non-secure destination was captured but cannot support live range replacement, the initial
`.finalOnly` result arms a continuous append owner bound to the captured PID and exact
`AXUIElement`. A first-partial rebind that returns `.finalOnly` does the same and offers that
triggering partial immediately. Thus every non-contentless hypothesis received before sealing is
routed to the selected owner while Fn remains held; release is only the seal/finalize boundary.
Only if the append factory cannot create this owner before any provisional attempt does the older
release-time, process-targeted Cmd+V final-only route remain available.

When AX destination capture or confirmation is unavailable, the first non-contentless hypothesis
causes one more `CursorTextSession.begin()` attempt. If that yields live AX capability, normal
verified range replacement takes ownership. If it remains unavailable,
`CurrentFocusAppendSession` binds the then-frontmost PID and provides best-effort continuous output
for the hold: it posts the first safe value as direct Unicode input, then posts only the unseen
UTF-16 suffix when every later hypothesis starts exactly with the already emitted UTF-16 units.
Duplicates are no-ops; revisions, shortenings, unsafe control characters, and contentless values
are suppressed by that same owner rather than deferred to release.

Every append mutation samples live Secure Input and the bound frontmost PID twice before and once
after posting. A captured append additionally validates the token's current security, original PID,
and `CFEqual` identity of the current focused element before and after the synchronous mutation.
Application activation change, PID/element drift, security rejection, generation invalidation, or
uncertain delivery permanently suspends the owner.

The Unicode poster accepts a positive bound PID and safe non-empty text, creates one
`.privateState` source, and fully constructs key-down and key-up with the same UTF-16 payload and
explicit empty flags before either can be posted. It samples live Secure Input only after the pair
exists; on success, the two `CGEventPostToPid` submissions are adjacent. Source/down/up construction
failure or the final security sample causes zero posts. `.posted` means only that both events were
submitted: CoreGraphics provides no target-control acceptance acknowledgement.

After any provisional delivery attempt, destination/security loss, or uncertainty, no full-text
resend, one-shot current-focus insertion, Cmd+V, alternate target, or clipboard recovery is allowed.
The only manual-copy path retained for a captured append owner requires proof of zero poster
attempts, an unsafe control-bearing retained value, and one final successful live validation of
Secure Input, the captured token, original PID, and exact AX element. It closes eligibility before
validation and can copy at most once.

The unbound append path uses no pasteboard, Backspace, selection, deletion, or cursor navigation.
Because it has no AX range, it cannot observe a caret move within the same process; text may
therefore reach a different caret in that process. This residual risk is explicit and is why
divergent hypotheses are preserved rather than rewritten. At release, an exact or strictly
extending final may append one last suffix; a divergent/shorter final preserves output state but
the UI uses neutral wording because target acceptance is not acknowledged.

`autoInsert=false` keeps recognition active but discards cursor-writing capability and produces no
target or pasteboard mutation. Secure targets and Secure Event Input still fail closed before
audio/network work when affirmatively detected.

These are verified local routing and event-construction contracts, not an end-to-end acceptance
claim. Installed owner UAT must still observe visible held output on the real target. A submitted
pair with no visible text remains a PARTIAL result and does not authorize global HID posting,
retries, destructive editing, or fallback after uncertainty.

See [D-25-01](decisions/D-25-01.md), [D-26-01](decisions/D-26-01.md), and the
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

`FeishuSpeechTests` is wired into the Xcode project. Issue #26 adds automated coverage for exact
audio ingress accounting, recorder sealing barriers, streaming action/sequence/token/cancel races,
cursor replacement, captured and unbound output, lifecycle generation, settings, and fixed
completion feedback. Focused green suites now cover typed numeric failures and exact-once failed
stream abort (24/24), retry policy and coordinator state (6/6), retry/replay/release plus
continuous-output integration (34/34), and current-focus UTF-16 suffix output (16/16). A fresh full
suite/build receipt belongs to final release validation rather than this API contract.

`AudioRecorderRecoveryTests.swift` remains excluded from the test target because it is a recorded
pre-existing AudioRecorder-owned blocker outside the #11/#12/#21 API recovery bundle.

Automated fakes do not complete the runtime contract. Installed Release UAT with real credentials
must still verify failed-stream action 3, fresh-session replay, release during backoff, terminal
empty-audio encoding, real response text shape, same-sequence token refresh, PCM/tail acceptance,
slow-network behavior, tenant permission/edition, and the cross-application AX/current-focus
matrix. No transcript, audio, credential, token, stream ID, raw body/backend message, target
content/title, or clipboard payload may be recorded during that UAT.

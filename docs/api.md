# API

This page documents the Feishu integration contract implemented by
`FeishuAPIService` and `FeishuStreamingSession`.

## Feishu endpoints

`FeishuAPIService` sends HTTPS `POST` requests to `open.feishu.cn`.

| Purpose | Path | Request | Success response |
|---|---|---|---|
| Tenant token | `/open-apis/auth/v3/tenant_access_token/internal` | JSON object with `app_id` and `app_secret` | `AuthResponse` with `code == 0`, `tenant_access_token`, and optional `expire` |
| Production streaming recognition | `/open-apis/speech_to_text/v1/speech/stream_recognize` | Base64 PCM fragment plus stream/action/sequence config | Code-zero response with optional IDs and `recognition_text` |
| Compatibility-only whole-file recognition | `/open-apis/speech_to_text/v1/speech/file_recognize` | `SpeechRequest` JSON with base64 PCM data and `SpeechConfig` | `SpeechResponse` with `code == 0` and `data.recognition_text` |

Speech requests use `Authorization: Bearer <tenant_access_token>`,
`format: "pcm"`, and `engine_type: "16k_auto"`.

The production Fn interaction never calls the compatibility-only whole-file endpoint and does not
fall back to it after a streaming failure.

### Authentication startup and public failures

The streaming provider must obtain a tenant token before it constructs a session or sends any
request to `stream_recognize`. A tenant-token business rejection therefore means that the
streaming endpoint was not reached. The recorded second installed-Release UAT failed at this token
acquisition boundary; it is evidence of an authentication rejection, not of a successful live
streaming request.

`FeishuAPIService.APIError.authFailed` maps to the fixed public message
`认证失败，请检查应用凭据`. The associated backend message, credential values, transcript, and raw
response stay outside UI and logs. Any terminal provider or streaming failure invalidates the
active generation, hides the recording overlay, and tears the interaction down once. Republishing
the same `HotKeyService` error is suppressed so it cannot re-enter teardown or indefinitely defer
the overlay's hide completion.

Owner UAT with a valid App ID/App Secret must still verify the tenant's
`speech_to_text:speech` permission, published application state, supported edition, and the real
streaming contract. The observed authentication rejection does not close that gate.

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
| 3 | best-effort active cancellation, at most once and within one total second | empty |

Requests are strictly serial. Only the exact known invalid-token business code in a bounded HTTP
400/401 response may refresh and retry the same action-1 packet and sequence once before any packet
is accepted; generic HTTP 400 is terminal. An established stream is never replayed and does not
fall back to `file_recognize` or the legacy whole-file retry path. Cancellation never sends action
3 after action 2 has been emitted, and it does not overlap an in-flight packet.

Audio ingress emits ordered 6,400-byte elements (about 200 ms at 16 kHz mono Int16) and is bounded
at exactly 1,920,000 queued-plus-pending bytes for the 60-second maximum. The custom async ingress
decrements exact queued bytes when a consumer drains a packet, so that capacity is immediately
reusable. After recorder stop crosses the real audio callback queue barrier, an established
stream's non-empty seal tail may pad to the 3,200-byte local 100 ms minimum. Overflow is a typed
terminal failure; audio is not dropped or reordered.

Feishu does not define the semantic shape of intermediate `recognition_text`. Every partial is
therefore the complete opaque replacement state, never an appendable delta. A non-empty action-2
response is the final authority.

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

When a non-secure destination was captured but cannot support live range replacement, final-only
mode may post one process-targeted Cmd+V only after the captured PID, focused element, and security
state are validated; the sink validates again after posting. A stale/uncertain captured
destination uses copy-only manual recovery.

When AX destination capture or confirmation is unavailable, the coordinator instead retains
opaque responses and, for a non-empty final, samples Secure Input and the frontmost PID twice
before posting one direct Unicode CGEvent to current focus. Successful unbound delivery never
touches the pasteboard. This fallback does not confirm a cursor position and does not require the
current focus to match an originally captured destination. It never writes partials. Ordinary
Unicode-event or PID-stability failure and C0/C1 control characters use copy-only recovery. An
affirmatively detected secure target or Secure Event Input performs no synthetic input and no
clipboard recovery. Per-partial pasteboard writes and synthetic deletion/navigation keys are
outside the contract.

`autoInsert=false` keeps recognition active but discards cursor-writing capability and produces no
target or pasteboard mutation. Secure targets and Secure Event Input still fail closed before
audio/network work when affirmatively detected.

See [D-25-01](decisions/D-25-01.md) and the
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

`withRetry` retries retriable API/network failures up to three attempts with
linear backoff. `CancellationError` and task cancellation are terminal:

- retry attempts stop immediately;
- the active URLSession request is cancelled;
- no later retry starts after the end-to-end deadline.

This preserves the caller's timeout/cancel semantics instead of converting
cancelled work into additional network attempts.

## Test target caveat

`FeishuSpeechTests` is wired into the Xcode project. Issue #26 adds automated coverage for exact
audio ingress accounting, recorder sealing barriers, streaming action/sequence/token/cancel races,
cursor replacement, captured and unbound final-only output, lifecycle generation, settings, and
fixed completion feedback. The current full macOS run reports 184 passed, 0 failed, and 0 skipped;
post-UAT regressions cover AX-unavailable startup, exact-once current-focus final delivery,
terminal-provider exact-once teardown, overlay dismissal, identical-error suppression, and private
authentication feedback.

`AudioRecorderRecoveryTests.swift` remains excluded from the test target because it is a recorded
pre-existing AudioRecorder-owned blocker outside the #11/#12/#21 API recovery bundle.

Automated fakes do not complete the runtime contract. Installed Release UAT with real credentials
must still verify terminal empty-audio encoding, real response identity/text shape, same-sequence
token refresh, PCM/tail acceptance, slow-network behavior, tenant permission/edition, and the
cross-application Accessibility matrix. No transcript, audio, credential, token, stream ID, raw
body/backend message, target content/title, or clipboard payload may be recorded during that UAT.

# API

This page documents the Feishu integration contract implemented by
`FeishuAPIService`.

## Feishu endpoints

`FeishuAPIService` sends HTTPS `POST` requests to `open.feishu.cn`.

| Purpose | Path | Request | Success response |
|---|---|---|---|
| Tenant token | `/open-apis/auth/v3/tenant_access_token/internal` | JSON object with `app_id` and `app_secret` | `AuthResponse` with `code == 0`, `tenant_access_token`, and optional `expire` |
| Speech recognition | `/open-apis/speech_to_text/v1/speech/file_recognize` | `SpeechRequest` JSON with base64 PCM data and `SpeechConfig` | `SpeechResponse` with `code == 0` and `data.recognition_text` |

Speech requests use `Authorization: Bearer <tenant_access_token>`,
`format: "pcm"`, and `engine_type: "16k_auto"`.

## Planned streaming recognition contract (issue #25)

Issue #25 defines the future production contract; the current Swift implementation still uses
`file_recognize`. The accepted design moves production recognition to:

`POST /open-apis/speech_to_text/v1/speech/stream_recognize`

The official API describes chunked real-time recognition and recommends 100–200 ms audio
fragments. Requests retain bearer authentication and Base64 PCM JSON with `format: "pcm"` and
`engine_type: "16k_auto"`.

### Internal stream interface

The planned `SpeechStreamingSession` exposes serial async operations equivalent to:

```swift
func sendAudioPacket(_ pcm16: Data) async throws -> SpeechStreamEvent
func finish() async throws -> SpeechStreamEvent
func cancel() async
```

Its typed events are `partial(String)`, `final(String)`, `cancelled`, and
`failed(StreamFailure)`. No raw Feishu response body or backend message crosses this boundary.

Each interaction owns a 16-character lowercase-letter/digit/underscore `stream_id`. Accepted
requests use monotonically increasing `sequence_id` values beginning at zero:

| Action | Meaning | Audio |
|---:|---|---|
| 1 | open with first packet | non-empty PCM |
| 0 | continue | non-empty PCM |
| 2 | finish normally, exactly once | empty |
| 3 | best-effort active cancellation, at most once | empty |

Requests are strictly serial. A known invalid token may refresh and retry the same action-1 packet
and sequence once before any packet is accepted. An established stream is never replayed and does
not fall back to `file_recognize` or the legacy three-attempt whole-file retry path.

Audio ingress emits ordered 6,400-byte elements (about 200 ms at 16 kHz mono Int16) and is bounded
at 1,920,000 bytes / 300 elements for the 60-second maximum. An established stream's non-empty
seal tail may pad to the 3,200-byte 100 ms minimum. Overflow is a typed terminal failure; audio is
not dropped or reordered.

Feishu does not define the semantic shape of intermediate `recognition_text`. Every partial is
therefore the complete opaque replacement state, never an appendable delta. A non-empty action-2
response is the final authority.

### Internal cursor-writer interface

The planned cursor writer opens one destination token containing the interaction generation,
original PID, original focused `AXUIElement`, and original selected-text range. Live mode requires
settable selected-text and selected-range attributes plus string-for-range verification.

Every update replaces the complete app-owned provisional range on that captured element. Before
and after a mutation, the writer validates generation, frontmost PID, focused element, caret,
owned range, and exact prior text. Accessibility-returned ranges define ownership; Swift
`String.count` does not. Any mismatch invalidates the writer permanently for that hold, and late
events write nothing.

Unsupported editable targets use final-only mode and may call `TextInputSimulator` once only after
the same PID and focused element are revalidated. Secure fields and Secure Event Input are rejected.
Per-partial pasteboard writes and synthetic deletion/navigation keys are outside the contract.

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

`FeishuSpeechTests` is wired into the Xcode project and runs the API regression
tests plus the existing passing suites. `AudioRecorderRecoveryTests.swift`
remains excluded from the test target because it is a reproduced pre-existing
AudioRecorder-owned blocker outside the #11/#12/#21 API recovery bundle.

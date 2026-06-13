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

## Direct HTTP completion

The primary request path uses `DirectFeishuHTTPClient` over `NWConnection` and
tries the configured direct Feishu IP list before falling back to URLSession DNS.
Direct HTTP responses complete as soon as the buffered response proves that the
body is complete:

- `Content-Length`: complete when at least the declared byte count has arrived.
- `Transfer-Encoding: chunked`: complete when the terminal zero-size chunk and
  trailer terminator have arrived.
- No body length marker: complete only when the connection closes.

If the direct connection reaches the request timeout, the buffered data is parsed
one last time. A complete `Content-Length` or terminal chunked response is
accepted; an incomplete response still throws `APIError.timeout`.

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

## Retry and cancellation

`withRetry` retries retriable API/network failures up to three attempts with
linear backoff. `CancellationError` and task cancellation are terminal:

- retry attempts stop immediately;
- the direct-IP loop does not try later IPs after cancellation;
- URLSession DNS fallback is skipped after cancellation.

This preserves the caller's timeout/cancel semantics instead of converting
cancelled work into additional network attempts.

## Test target caveat

`FeishuSpeechTests` is wired into the Xcode project and runs the API regression
tests plus the existing passing suites. `AudioRecorderRecoveryTests.swift`
remains excluded from the test target because it is a reproduced pre-existing
AudioRecorder-owned blocker outside the #11/#12/#21 API recovery bundle.

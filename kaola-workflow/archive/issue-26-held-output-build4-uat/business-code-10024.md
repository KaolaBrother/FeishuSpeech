# Feishu streaming ASR business code `10024`: authoritative lookup

Lookup date: 2026-08-03 (Asia/Shanghai). Scope was limited to current official Feishu/Lark
documentation and the official Lark OpenAPI Go SDK. No credentials were read and no speech API
request was made.

## Result

**The current official public Feishu/Lark material does not define business code `10024`.** It is
therefore not possible to authoritatively label it as packet pacing, a stream-lifecycle violation,
a tenant concurrency/session quota, a sequence/action error, or an unsupported tenant from the
published sources alone.

This is a documentation gap, not evidence that the client should ignore the code. The endpoint's
official response contract says a nonzero `code` is failure, and the official SDK likewise reports
success only when `Code == 0`.

## Confirmed official contract

- The endpoint recommends **100–200 ms of audio per chunk**. This is a chunk-duration/size
  recommendation; the documentation does **not** specify a 100–200 ms delay between HTTP requests,
  a minimum inter-request interval, or a silence timeout. Consequently, calling this an official
  “packet interval” would overstate the source.
- A `stream_id` is one session. The current Feishu page states a tenant-wide maximum of **20
  concurrent streams** and says the free edition is unsupported. It does not publish the business
  code returned when either condition is violated.
- `sequence_id` starts at `0` and increments by `1` for every request in the stream.
- `action = 1` is the first packet; `action = 0` is an intermediate audio packet; `action = 2`
  normally ends the stream and waits for the final result; `action = 3` aborts the stream and does
  not return a final result.
- The streaming endpoint's published error table contains only HTTP 400 / `1040101` (`invalid
  param`) and HTTP 500 / `1040102` (`network anomaly`). `10024` is absent from both that table and
  the endpoint schema served by the official documentation site.
- The official Go SDK generated from Feishu API metadata contains the same action and sequencing
  contract. At current commit `8dfbfff01d210b20ec9473bf383d38d1b54aa37b` (2026-07-31), it has no
  `10024` mapping; the generated response treats every nonzero business code generically as
  unsuccessful.
- Feishu's general OpenAPI rate-limit documentation identifies the standard rate-limit response as
  HTTP `429` (or HTTP `400` for some old APIs) with business code `99991400`, plus
  `x-ogw-ratelimit-reset`. That contract does **not** match an HTTP 200 / `10024` response. Because
  this endpoint is marked “special rate limit,” this difference rules out identifying `10024` as
  the documented standard OpenAPI rate-limit code, but it does not prove that no undocumented
  speech-service quota or pacing check exists.

## Implications for the observed failure sequence

The observed accepted action-1/action-0 packets followed by HTTP 200 / `10024` on
`action=0, sequence=2`, and then repeated `10024` on fresh `action=1, sequence=0` sessions, does not
select one official diagnosis:

| Candidate explanation | Authoritative status |
|---|---|
| Standard OpenAPI request-rate limit | **Contradicted as the documented code/HTTP shape**: the official generic limit is `99991400` with HTTP 429/400, not HTTP 200 / `10024`. An undocumented ASR-specific limit remains possible. |
| Audio chunk too large or requests too fast | **Unconfirmed.** Officially, 100–200 ms is only a recommended audio chunk duration. No error mapping, hard maximum, or inter-request delay is published. |
| Invalid sequence/action | **Unconfirmed.** Sequence must start at 0 and increase by 1, and actions have the meanings above, but no official source maps violations to `10024`. |
| Unfinished/leaked prior stream | **Plausible inference, not confirmed.** Action 2 and action 3 are the documented terminal operations, and sessions count toward the 20-stream tenant cap. The docs do not say whether action 3 is required or accepted after the server has already rejected a packet, how long a failed stream remains allocated, or whether a fresh action-1 request can be rejected because an earlier stream was not terminated. |
| 20-session tenant concurrency quota | **Possible but unconfirmed.** The cap is official; its returned code and recovery timing are undocumented. |
| Unsupported/free tenant | **Possible only as a general capability check, not a `10024` mapping.** Free edition is officially unsupported, but the returned code is undocumented; acceptance of earlier packets also prevents inferring this from the public contract alone. |

## Terminal/abort boundary

The only safe official conclusions are:

1. Send `action = 2` to normally finish an established healthy stream and wait for its final result.
2. Send `action = 3` to intentionally abort an established stream when no final result is wanted.
3. Do **not** claim that an abort after an already-failed request is officially required, will be
   accepted, or will immediately release quota; Feishu publishes no such recovery guarantee.
4. Do **not** retry/replay audio or reinterpret `10024` as success based on the public contract.
   Escalating the response's sanitized request/log ID and timestamps to Feishu technical support is
   required for the exact server-side meaning.

## Official sources

- [Feishu: Streaming speech recognition endpoint](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/reference/ai/speech_to_text-v1/speech/stream_recognize) — live endpoint contract, chunk recommendation, 20-stream tenant cap, free-edition restriction, actions, sequence, and published errors (retrieved 2026-08-03).
- [Feishu: OpenAPI rate-control policy](https://open.feishu.cn/document/ukTMukTMukTM/uUzN04SN3QjL1cDN) — documented HTTP 429/400 + `99991400` rate-limit response and the meaning of “special rate limit” (retrieved 2026-08-03).
- [Official Lark Go SDK: generated streaming models at commit `8dfbfff`](https://github.com/larksuite/oapi-sdk-go/blob/8dfbfff01d210b20ec9473bf383d38d1b54aa37b/service/speech_to_text/v1/model.go#L184-L193) — generated action/sequence fields from API metadata (retrieved 2026-08-03).
- [Official Lark Go SDK: generated response success test at commit `8dfbfff`](https://github.com/larksuite/oapi-sdk-go/blob/8dfbfff01d210b20ec9473bf383d38d1b54aa37b/service/speech_to_text/v1/model.go#L544-L559) — success is `Code == 0`, with no endpoint-specific `10024` mapping (retrieved 2026-08-03).
- [Official Lark Go SDK: generated endpoint resource at commit `8dfbfff`](https://github.com/larksuite/oapi-sdk-go/blob/8dfbfff01d210b20ec9473bf383d38d1b54aa37b/service/speech_to_text/v1/resource.go#L53-L78) — generated 100–200 ms recommendation and 20-stream/free-edition note (retrieved 2026-08-03).


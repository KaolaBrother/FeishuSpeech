# Feishu streaming speech transport evidence for issue #26

Status: external contract review complete; credential-bearing runtime behavior remains unverified  
Review date: 2026-08-03 (Asia/Shanghai)  
Scope: `docs/decisions/D-25-01.md`, `docs/streaming-speech-design.md`, and `docs/api.md` in the issue-26 worktree

## Executive verdict

The accepted design has the correct official endpoint, tenant-token authentication, JSON envelope,
stream identity/sequence fields, action values, Base64 PCM field, supported `format` and
`engine_type`, and response field names. The official contract also confirms that streaming can
return data in real time and recommends 100–200 ms fragments.

Several details in the local design are **not vendor-documented wire requirements**:

- signed Int16, mono PCM (and therefore the byte calculations derived from it);
- exactly 6,400-byte packets and a 3,200-byte padded final tail;
- lowercase-only `stream_id` values (Feishu allows letters, digits, and underscore, without a
  lowercase restriction);
- an empty-audio representation for actions 2 and 3;
- strict one-request-at-a-time transport, exact-once terminal emission, retry/replay behavior, and
  idempotency;
- whether intermediate `recognition_text` is a delta, accumulated transcript, stable segment, or
  revisable hypothesis;
- an explicit response-side final/partial discriminator.

Those are valid application policies where they are conservative, but tests and documentation
must not label them as guarantees made by Feishu. In particular, retrying the same first
`sequence_id` is not confirmed: the official text says the sequence starts at 0 and increments by
1 **for every request**. Whether an authentication-rejected request consumes a stream sequence is
a credential-bearing runtime unknown.

## Primary sources

1. [Feishu Open Platform: Streaming speech recognition (official Markdown)](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/reference/ai/speech_to_text-v1/speech/stream_recognize.md),
   accessed 2026-08-03. This is the official page's advertised pure-Markdown alternate and is the
   primary normative source used below.
2. [Feishu Open Platform: Streaming speech recognition (official rendered page)](https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/reference/ai/speech_to_text-v1/speech/stream_recognize),
   accessed 2026-08-03. The page identifies the API as streaming ASR and links the Markdown form.
3. [Official Lark Go OpenAPI SDK v3.9.10: generated speech-to-text models at commit `8dfbfff`](https://github.com/larksuite/oapi-sdk-go/blob/8dfbfff01d210b20ec9473bf383d38d1b54aa37b/service/speech_to_text/v1/model.go),
   accessed 2026-08-03. This independently confirms the generated request/response JSON field
   names and types but adds no audio-format or hypothesis-shape guarantees.
4. [Official Lark Go OpenAPI SDK v3.9.10: generated streaming resource at commit `8dfbfff`](https://github.com/larksuite/oapi-sdk-go/blob/8dfbfff01d210b20ec9473bf383d38d1b54aa37b/service/speech_to_text/v1/resource.go),
   accessed 2026-08-03. This confirms POST, the endpoint path, and tenant-token support.

The official SDK is corroborative rather than an independent behavioral specification: its files
state that they are generated from OpenAPI metadata, and their comments reproduce the public page.

## Documented wire contract

### Endpoint, access, and limits

| Item | Officially documented fact | Local claim assessment |
|---|---|---|
| Method and URL | `POST https://open.feishu.cn/open-apis/speech_to_text/v1/speech/stream_recognize` | Confirmed. |
| Authorization | Required `Authorization` header carrying a `tenant_access_token`, formatted `Bearer <access_token>` | Confirmed. Do not log the header or token. |
| Content type | Required fixed value `application/json; charset=utf-8` | The implementation should send this exact media type. |
| Permission | `speech_to_text:speech` (speech recognition) | Runtime application grant/publication state is unknown. |
| App types | Custom app and Store app | Confirmed. |
| Availability | Free edition does not support the API | Deployment entitlement is a runtime/account unknown. |
| Tenant concurrency | 20 concurrent streams per tenant; one `stream_id` counts as one stream | Relevant operational limit; the single-user app should still surface capacity failures safely. |

### Request body

The request is a JSON object with required top-level objects `speech` and `config`:

```json
{
  "speech": {
    "speech": "<base64-encoded PCM fragment>"
  },
  "config": {
    "stream_id": "<16 characters>",
    "sequence_id": 0,
    "action": 1,
    "format": "pcm",
    "engine_type": "16k_auto"
  }
}
```

Field-by-field contract:

| JSON field | Type / presence | Official semantics |
|---|---|---|
| `speech` | object, required | Audio resource wrapper. |
| `speech.speech` | string, shown as optional in the official schema | A PCM file (file API) or streaming audio fragment encoded with Base64. |
| `config` | object, required | Streaming configuration wrapper. |
| `config.stream_id` | string, required | User-generated 16-character stream identifier containing only letters, digits, and underscore. |
| `config.sequence_id` | integer, required | Fragment sequence starts at 0 and increments by 1 on every request. |
| `config.action` | integer, required | `1` first packet; `0` middle audio packet; `2` normal end and wait for result; `3` interrupt and do not return a final result. |
| `config.format` | string, required | Only `pcm` is supported. |
| `config.engine_type` | string, required | Only `16k_auto` is supported; described as mixed Chinese/English. |

Important precision points:

- Feishu says “letters, digits, and underscore”; it does **not** say lowercase-only. Generating
  lowercase ASCII is a compatible local restriction, not the external contract.
- The official example uses `sequence_id: 1` even with `action: 1`, while the field description
  says sequences start at 0. The field description is the explicit rule and should control;
  issue #26's first request at 0 is therefore supported despite the inconsistent example.
- The schema marks nested `speech.speech` optional, and the official Go SDK models it with
  `omitempty`. That makes an empty `speech` object representable. Neither source explicitly states
  whether action 2 or action 3 must send `{"speech":{}}`, an empty Base64 string, an omitted nested
  field, or some other shape. Server acceptance of the chosen terminal encoding requires UAT.
- The action descriptions do not explicitly say audio is forbidden or ignored on action 2/3.

### Action and sequence semantics

The following is official:

1. The stream begins with action 1.
2. Audio transfer between start and termination uses action 0.
3. Action 2 normally ends the stream and waits for a result.
4. Action 3 interrupts the stream and does not return a final result.
5. Sequence numbering begins at 0 and increments by 1 per request.

The following is a reasonable application state-machine interpretation, **not stated as a vendor
guarantee**:

- emit action 1 once, then zero or more action-0 requests, then at most one action 2 or action 3;
- keep requests strictly serial so ordering is unambiguous;
- never send more audio after a terminal action;
- treat finish/cancel as locally idempotent;
- validate that a successful response's `stream_id` and `sequence_id` match the request.

These rules are defensible fail-closed design choices. The official source does not describe
parallel-request handling, duplicate terminal requests, replay, timeout recovery, or request
idempotency.

The planned “refresh an invalid token and retry the same action-1/sequence-0 request once” is
**unverified and potentially in tension with the literal sequence rule**. It may be safe if an
authentication failure occurs before Feishu creates/advances the stream, but the public contract
does not say so. No credential-free source can establish this. A safer interpretation until UAT
is that retries are an application policy with no server idempotency guarantee.

### PCM and fragment constraints

Officially documented:

- fragment bytes are Base64-encoded into `speech.speech`;
- `format` currently supports only `pcm`;
- `engine_type` currently supports only `16k_auto`;
- each audio fragment is **recommended** to represent 100–200 ms;
- the API description says the whole audio is divided into fragments and data can be returned in
  real time.

Not documented on this API page or in the official generated Go/Python models:

- sample representation (signed vs unsigned, integer vs float);
- bit depth or byte order;
- channel count;
- a normative sample rate (the name `16k_auto` strongly suggests 16 kHz but is not an encoding
  specification);
- minimum/maximum fragment byte size;
- a requirement that every fragment be exactly 100–200 ms rather than a recommendation;
- silence-padding behavior;
- total audio duration or byte cap for the streaming endpoint.

Consequently, 16 kHz mono signed little-endian Int16 PCM is a **reasonable project input profile**
and is consistent with the existing recorder, but it is not fully proven by the streaming API
contract. Under that chosen profile, the arithmetic is correct:

- 16,000 samples/s × 2 bytes × 1 channel = 32,000 bytes/s;
- 200 ms = 6,400 bytes;
- 100 ms = 3,200 bytes;
- 60 seconds = 1,920,000 bytes = 300 × 6,400-byte chunks.

The arithmetic does not turn those values into vendor requirements. The 6,400-byte target,
3,200-byte padded tail, 60-second/1,920,000-byte ingress ceiling, and overflow policy should be
documented and tested as FeishuSpeech's bounded-ingress design. The 100–200 ms recommendation is
the only externally documented part. Credential-bearing UAT should test short final tails and
the exact PCM profile before compatibility is claimed.

### Response and errors

The success/error envelope documented by Feishu is:

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "stream_id": "<16-character string>",
    "sequence_id": 1,
    "recognition_text": "<recognized text>"
  }
}
```

| Field | Official description | Implementation consequence |
|---|---|---|
| `code` | integer; non-zero means failure | Success must require zero, not merely HTTP success. |
| `msg` | error description | Treat as untrusted backend text; sanitize rather than log/display raw content. |
| `data.stream_id` | 16-character string identifying the stream | Decode it; matching it to the request is a reasonable defensive check. |
| `data.sequence_id` | integer stream fragment sequence | Decode it; matching it to the request is a reasonable defensive check. |
| `data.recognition_text` | text recognized from the speech stream | It may be absent/empty in practice because generated SDK fields are optional; the public table does not give requiredness. |

The only streaming-specific errors listed are:

- HTTP 400 / business code `1040101`: invalid parameter;
- HTTP 500 / business code `1040102`: backend or network anomaly; the page says it may be retried.

That troubleshooting sentence does not define replay safety for an already-established stream.
It also does not guarantee which HTTP status is used for an invalid/expired token. The local
400/401 token-refresh behavior comes from the existing whole-file client policy, not from a
streaming-specific official guarantee.

There is no documented `data.error` field, no response `action`, no `is_final`, no stability flag,
no segment list, and no word timestamps in the official schema or generated SDK model.

## Intermediate versus final response shape

Feishu states that the API can return data in real time and that action 2 normally ends the stream
while waiting for a result. It exposes the same `data.recognition_text` shape for the API response
and provides no separate intermediate/final schemas.

Therefore:

- **Documented fact:** responses may contain `recognition_text`; action 2 is the normal terminal
  request that waits for a result; action 3 returns no final result.
- **Reasonable inference:** a successful response to action 2 can be treated as the terminal
  response for the application's request chain, because there is no other final marker.
- **Not documented:** whether every action-0 request returns text; whether empty text is normal;
  whether action-1/action-0 text is partial; whether each value is a delta, accumulated transcript,
  stable segment, or revisable hypothesis; whether the action-2 text is guaranteed non-empty or
  contains the complete utterance.

The local rule to treat every intermediate string as an opaque whole replacement is therefore a
sound safety policy, not a factual claim about Feishu's hypothesis semantics. Likewise, preferring
a non-empty action-2 value as final authority is a reasonable application rule, but “authoritative”
is not terminology or a guarantee present in the official contract.

## Claim disposition for issue #26

| Local claim | Disposition |
|---|---|
| POST `.../speech/stream_recognize` | Confirmed official fact. |
| Tenant bearer auth and JSON UTF-8 content type | Confirmed official fact. |
| Base64 PCM, `format=pcm`, `engine_type=16k_auto` | Confirmed official fact. |
| First sequence is 0; increment each request | Confirmed by field description; official example is inconsistent. |
| Actions 1/0/2/3 meanings | Confirmed official fact. |
| Action 3 returns no final result | Confirmed official fact. |
| 16-character `stream_id` from letters/digits/underscore | Confirmed official fact. |
| Lowercase-only `stream_id` | Compatible local choice, not an official restriction. |
| Strictly serial requests | Reasonable local correctness policy; not explicitly documented. |
| Exactly one finish / at most one abort; idempotent methods | Local state-machine policy; server duplicate/idempotency behavior unknown. |
| Empty audio on finish/abort | Nested audio is optional in schema, but exact accepted terminal JSON is unknown. |
| 16 kHz mono signed Int16 PCM | Reasonable existing project profile; not fully specified by the streaming page/SDK. |
| Exactly 6,400 bytes per normal packet | Local choice derived from the profile and the recommended 200 ms; not official. |
| Tail at least 3,200 bytes, padded with silence | Local choice derived from the recommended 100 ms; not official. |
| 1,920,000-byte / 300-element bound | Correct local arithmetic for the retained 60-second cap; not a Feishu limit. |
| Retry same first action/sequence after token refresh | Runtime unknown; official per-request increment wording does not promise this replay. |
| No retry/replay after establishment | Conservative local safety policy; official error table merely says 1040102 may be retried without defining stream semantics. |
| Intermediate text is opaque replacement | Correct safety stance because semantics are undocumented; not a description of vendor behavior. |
| Non-empty action-2 text is final authority | Reasonable application inference/policy; not explicitly guaranteed. |
| Response fields `stream_id`, `sequence_id`, `recognition_text` | Confirmed official schema and SDK model. |
| Error fields `code`, `msg` | Confirmed official envelope. No `data.error` field is documented. |

## Credential-bearing/runtime unknowns and required UAT

No request was sent and no credentials, tokens, audio, or transcripts were accessed. The
following cannot be resolved safely from public documentation and should remain explicit UAT
items using synthetic/non-private audio and redacted diagnostics:

1. Exact accepted terminal request JSON for actions 2 and 3, including whether `speech.speech`
   should be omitted or an empty string.
2. Acceptance of 16 kHz mono signed little-endian Int16 PCM and behavior for a final fragment under
   100 ms, with and without silence padding.
3. Whether successful action-1/action-0 responses always include `data`, IDs, and
   `recognition_text`, and whether text may be empty.
4. Whether intermediate text is cumulative, delta, segmented, or revisable; tests must not depend
   on an answer until observed and documented, and even observation is not a vendor guarantee.
5. Whether action-2 `recognition_text` is complete and non-empty, and whether its response IDs echo
   the terminal request.
6. Invalid/expired-token status/envelope, and whether retrying the same action/sequence/stream is
   accepted before stream establishment.
7. Timeout, duplicate request, out-of-order sequence, and already-established network-failure
   behavior. These tests must avoid replaying user audio and must not log raw backend bodies.
8. Actual tenant permission, edition entitlement, and concurrency availability for the deployed
   Feishu app.

## Implementation guidance bounded by the evidence

- Keep the current local packet/buffer sizing if desired, but name it as an application invariant,
  not an SDK/API constant.
- Encode and decode the documented fields exactly. Treat `data` and its fields as potentially
  missing because both generated official SDKs model them as optional/omittable.
- Classify a response as terminal from local request state (the response to action 2), not from a
  nonexistent response final flag.
- Preserve the opaque-replacement handling for intermediate text; it is the safest behavior under
  the documentation gap.
- Keep raw `msg`, HTTP bodies, credentials, stream IDs, audio, and recognition text out of logs and
  UI errors. Map them to typed sanitized failures.
- Do not claim vendor-supported first-packet replay or post-establishment retry. If implemented,
  isolate it behind an injectable policy and a credential-bearing UAT gate.

## Blocking documentation gaps

The public Feishu contract is insufficient to prove the exact PCM encoding profile, terminal
empty-audio body, intermediate/final transcript semantics, or replay/idempotency behavior. These
gaps do not block implementing a conservative serial client with opaque replacement and sanitized
failure, but they **do block** describing 6,400/3,200-byte sizing, same-sequence token retry, or a
non-empty complete final transcript as Feishu-guaranteed behavior. Credential-bearing UAT is the
only available verification path found for those points.

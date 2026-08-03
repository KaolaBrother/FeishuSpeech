# Issue #26 installed Release live-failure investigation

## Scope and success criterion

Claim under investigation: with the owner's real credentials, the installed Release still reports
`流式识别失败` immediately. Success means locating the narrowest measured failure boundary without
launching or terminating the app, reading credentials/token/audio/transcript, issuing a
credential-bearing request, or triggering a permission prompt.

This investigation was read-only except for this report. The already-running application was left
running.

## Setup

- Repository: `/Users/ylpromax5/Workspace/feishuspeech`
- Owned worktree inspected: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`
- Source commit: `2e5a022cf1e931b4894c4eba533fbe1d069e3b0d`
  (`chore: archive issue-26 [sink]`, 2026-08-03 14:49:43 +08:00)
- Installed bundle: `/Applications/FeishuSpeech.app`, version `1.0`, build `1`, identifier
  `Siji.FeishuSpeech`
- Installed executable SHA-256:
  `300e486b6d7174dd55c483478ec34b1d9699b09c4b6a794f1072cfbad2bbeb25`
- Runtime: macOS 26.6 (25G72), arm64
- Existing process at baseline: PID 38363, launched 2026-08-03 14:55:39 +08:00 from the installed
  bundle. It was still running when sampled.
- The bundle does not expose a source commit marker, so version/build plus executable digest identify
  the measured artifact, but equivalence to the worktree commit is not independently proven.

Commands used included:

```text
git rev-parse HEAD
git status --short --branch
pgrep -afil 'FeishuSpeech(.app)?'
ps -p 38363 -o pid=,lstart=,etime=,%cpu=,%mem=,command=
/usr/bin/log show --start ... --end ... --style compact --info --debug \
  --predicate 'process == "FeishuSpeech" && subsystem == "com.feishuspeech.app"'
/usr/bin/log show --start ... --end ... --style compact --info --debug \
  --predicate 'process == "FeishuSpeech"'
rg / sed / git blame over FeishuAPIService.swift, FeishuStreamingSession.swift,
MainViewModel.swift, StreamingSpeechModels.swift, and their tests/docs
```

The explicit baseline checks for unified-log access, exact process presence, and Git commit all
returned exit code 0. One first attempt used a fractional-second `log show --end` value; macOS
rejected that timestamp format. It produced no measurement and was rerun with whole-second bounds.

## Observations

| Measurement | Command / method | Result | Exit |
|---|---|---|---:|
| Source baseline | `git rev-parse HEAD`; `git status --short --branch` | commit above; branch `workflow/issue-26` | 0 |
| Installed process | `pgrep`, then `ps -p 38363 ...` | installed Release was already running; no launch/termination performed | 0 |
| Installed artifact | `PlistBuddy`, `codesign -dv`, `shasum -a 256` | version 1.0/build 1, identifier and digest above | 0 |
| Current attempt startup | app-subsystem log, 14:56:58.329–14:56:58.765 | Fn pending -> generation 5 streaming; AX destination fell back to current-focus final output; 48 kHz/32-bit/mono -> 16 kHz/16-bit/mono converter created; recording started | 0 |
| Provider acquisition | same log | `Using cached token` at 14:56:58.765; no auth rejection in this interaction | 0 |
| First live streaming request | process-wide CFNetwork log | request sent 14:56:58.914, request body 9,821 bytes | 0 |
| First response | process-wide CFNetwork log | response at 14:56:59.136; HTTP 200; transaction 222 ms; CFNetwork summary reports 9,935 request bytes and 856 response bytes | 0 |
| Terminal transition | app-subsystem log | audio force-cleanup and `Setting error state: 流式识别失败` at 14:56:59.139, 3 ms after the HTTP response | 0 |
| Repetition | process-wide CFNetwork + app logs | five first-packet requests failed the same way through the latest generation 6 interaction at 15:02:13.505/506; every response was HTTP 200 | 0 |
| Retry behavior | chronological task/log inspection | no token refresh request or same-packet retry followed any of those five HTTP-200 streaming responses | 0 |
| Failure-before-release timing | app log for latest generation 6 | cached token at 15:02:12.982; capture started 15:02:13.030; first response at 15:02:13.505; error at 15:02:13.506; Fn release only at 15:02:14.875 | 0 |
| Permission state | app log after failure | microphone and accessibility both logged `true`; no prompt was caused by this investigation | 0 |

The five CFNetwork streaming measurements were:

| Response time | Request body | HTTP | Duration | Response bytes | Error publication lag |
|---|---:|---:|---:|---:|---:|
| 14:56:32.142 | 8,955 B | 200 | 291 ms | 836 B | 6 ms |
| 14:56:37.005 | 9,822 B | 200 | 249 ms | 925 B | 3 ms |
| 14:56:40.077 | 9,835 B | 200 | 213 ms | 856 B | 5 ms |
| 14:56:59.136 | 9,821 B | 200 | 222 ms | 856 B | 3 ms |
| 15:02:13.505 | 9,724 B | 200 | 306 ms | 1,025 B | 1 ms |

No response body, recognition text, audio bytes, bearer token, App ID, or App Secret was inspected
or recorded.

## Reproduction status

**Reproduced from existing runtime evidence.** The current real-credential process produced five
stable failures. Each interaction reached the first streaming HTTP response, received HTTP 200,
and then entered terminal cleanup within 1–6 ms. The latest interaction proves the owner's timing
description directly: generation 6 failed 1.369 seconds before the Fn-release log. The session sends
its first audio packet while Fn remains held; release is needed for sealing/action 2, not for the
initial action-1 request.

The request action and sequence are not logged by this Release. They are code-determined rather
than directly observed: a newly created `FeishuStreamingSession` starts with
`didAcceptFirstPacket == false` and `nextSequenceID == 0`, so its first non-empty packet is built as
`action=1`, `sequence_id=0`. Every failed interaction terminated before accepting that packet, and
the next Fn interaction created a new generation/session. Thus the measured boundary is the
`action=1 / sequence_id=0` response path, with that action/sequence conclusion labeled as a
high-confidence code inference.

## Narrowing legs

### Leg 1 — startup versus live transport

The current interaction logged a cached tenant token, successful recording startup, and a real
outbound request. This rules out missing local configuration, token-acquisition failure for the
current interaction, permission denial, recorder startup failure, and failure before transport.

### Leg 2 — network/HTTP versus application response handling

CFNetwork completed the request successfully with HTTP 200 in 222 ms. This rules out DNS,
connection, timeout, cancellation-before-response, and non-200 HTTP status as the current terminal
cause.

### Leg 3 — token-invalid refresh branch versus other response validation

`sendWithInitialTokenRefreshIfNeeded` refreshes once and retries the same action-1/sequence-0 packet
when `send` throws `StreamFailure.authentication`. The current code classifies only business code
`99_991_663` as that failure. No refresh request or same-packet retry followed any of the five
responses. Therefore the installed code did **not** classify them as its known invalid-token case.

### Leg 4 — remaining exact branches

After a status-200 response, `FeishuStreamingSession.send` can terminate at only these response
checks:

1. JSON cannot decode into the expected response model -> `malformedResponse`;
2. decoded business `code` is nonzero and is not `99_991_663` -> `backend`;
3. code is zero but `data` is absent -> `malformedResponse`;
4. returned `stream_id` or `sequence_id`, when present, does not equal the request ->
   `responseIdentityMismatch`.

`MainViewModel.streamingFailureMessage` recognizes only provider-level
`FeishuAPIService.APIError.authFailed`. All `StreamFailure` values above are collapsed to
`流式识别失败`. `FeishuStreamingSession` currently emits no safe classification log, business code,
action, sequence, body size, or identity-match booleans. Consequently the existing artifact cannot
distinguish these four remaining branches without inspecting the raw response, which was outside
the investigation's privacy boundary.

## Inferences

### High confidence

The strongest supported root cause is a deterministic **first-packet application-level response
contract/rejection failure** after the Feishu streaming endpoint returns HTTP 200. It is not the
previous invalid-credential boundary and not a transport or audio-start failure.

An independent diagnostics defect makes the public symptom generic: the production code discards
the safe `StreamFailure` classification and does not log the non-sensitive branch metadata, so the
owner sees the same text for backend rejection, malformed response, and response identity mismatch.

### Medium confidence

A nonzero Feishu business code (for example a permission, tenant-edition, publication, or request
contract rejection) is plausible because Feishu commonly returns business failures inside HTTP
200 and the failure repeats immediately on every action-1 response. This is **not proven** by the
available log; malformed JSON/model mismatch or an ID mismatch remain viable and must not be
reported as settled.

The preceding 14:56:31.650 request (81-byte body, HTTP 200) immediately followed by the first
8,955-byte streaming request, plus later `Using cached token`, is consistent with successful token
acquisition after the owner updated credentials. Its body was not inspected, so that specific
request-purpose identification is an inference, not a raw observation.

## What remains unmeasured

- The exact `StreamFailure` case for the HTTP-200 action-1 response.
- The Feishu business `code`, if nonzero.
- Whether the response decoded, contained `data`, and returned stream/sequence IDs matching the
  request.
- Whether tenant scope, app publication, tenant edition, engine selection, or another backend
  rule is the service-side reason.
- Cryptographic equivalence of the installed executable to source commit `2e5a022`; the installed
  digest is recorded for reproducibility, but the bundle embeds no commit marker.

The next discriminating measurement requires a new instrumented build that logs only safe metadata:
generation, action, sequence, HTTP status, response byte count, decoded business code, data-present,
stream-ID-match, sequence-ID-match, and final sanitized `StreamFailure` case. It must not log raw
headers/body, credentials/token, audio, response message, or transcript. This report does not choose
or implement that remedy; it records why the current Release cannot provide the missing fact.
